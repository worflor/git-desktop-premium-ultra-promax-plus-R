// tool/diff_load_profiler.dart — measure ONE diff-pipeline stage at ONE input
// size, in a fresh isolated process, and report peak RSS + wall time as JSON.
//
// WHY a standalone `dart run` (not a flutter test): the diff core is Flutter-
// free, so this runs with NO engine baseline — the RSS we read is the pipeline's
// own, not the framework's. And because each invocation is its OWN OS process
// running exactly ONE stage at ONE size, `ProcessInfo.maxRss` at exit is that
// stage's true high-water mark (the OS records it even while a synchronous CPU-
// bound stage blocks the Dart event loop, which a Timer-based poller cannot).
//
// SAFETY (never OOM this host): the parent sweep (diff_load_sweep.dart) only
// asks for sizes it PREDICTS are under budget from the fitted growth curve, so
// the crash size is extrapolated, never run. As a backstop, the async stages
// self-abort when `currentRss` crosses --budget-mb between cooperative yields;
// and because every run is a child process, even a hard OOM kills only the
// child — the parent records "died at N bytes" as a data point and lives on.
//
// Usage:
//   dart run tool/diff_load_profiler.dart \
//     --stage=eager|slice|index|lazy --bytes=<N> [--files=<K>] \
//     [--budget-mb=2048] [--source=synthetic|file:<path>] [--seed=<s>]
//
// Emits exactly one JSON object on stdout (plus human notes on stderr).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/features/diff/byte_store.dart';
import 'package:git_desktop/features/diff/diff_document.dart';
import 'package:git_desktop/features/diff/diff_models.dart';
import 'package:git_desktop/features/diff/predictive_diff_index.dart';

const int _mib = 1024 * 1024;

Map<String, String> _parseArgs(List<String> argv) {
  final m = <String, String>{};
  for (final a in argv) {
    if (!a.startsWith('--')) continue;
    final eq = a.indexOf('=');
    if (eq < 0) {
      m[a.substring(2)] = 'true';
    } else {
      m[a.substring(2, eq)] = a.substring(eq + 1);
    }
  }
  return m;
}

/// Deterministic DIMACS-road-graph-shaped unified diff of ~[targetBytes] across
/// [files] files, modelled on the real marble corpus (arc lines `a t h w`, line
/// length mean ~22 / sd ~1). A full-rewrite diff: every old line deleted, every
/// new line re-added (only the weight column changes), wrapped in valid git file
/// + hunk headers so EVERY parser accepts it. Seeded LCG — no wall-clock, no
/// platform RNG, byte-identical every run.
String _genDimacsDiff(int targetBytes, int files, int seed) {
  final sb = StringBuffer();
  var rng = seed & 0x7fffffff;
  int next() {
    // Numerical Recipes LCG; only the high bits are used, so low-bit bias
    // doesn't matter for synthetic node ids.
    rng = (rng * 1664525 + 1013904223) & 0x7fffffff;
    return rng;
  }

  final bytesPerFile = (targetBytes / files).floor();
  for (var f = 0; f < files; f++) {
    final name = 'graph_$f.gr';
    sb.write('diff --git a/$name b/$name\n');
    sb.write('index 0000000..1111111 100644\n');
    sb.write('--- a/$name\n');
    sb.write('+++ b/$name\n');
    // One big hunk covering a full rewrite. We size the body by bytes, not a
    // known line count, so first estimate lines then emit the exact header.
    // Average emitted pair ("-...\n+...\n") is ~48 bytes; solve for line count.
    final approxLines = (bytesPerFile / 48).floor().clamp(1, 1 << 30);
    sb.write('@@ -1,$approxLines +1,$approxLines @@\n');
    final startBytes = sb.length;
    var emitted = 0;
    while (sb.length - startBytes < bytesPerFile && emitted < approxLines) {
      final t = next() % 90000000 + 1000000;
      final h = next() % 90000000 + 1000000;
      final wOld = next() % 900 + 100;
      final wNew = wOld + (next() % 9) + 1;
      sb.write('-a $t $h $wOld\n');
      sb.write('+a $t $h $wNew\n');
      emitted++;
    }
  }
  return sb.toString();
}

/// Stream a DIMACS-shaped diff of ~[targetBytes] straight to [path], flushing a
/// bounded buffer so the whole diff never resides in RAM — the disk-backed input
/// for the `filebacked` stage. Returns the bytes written.
int _genDimacsDiffToFile(String path, int targetBytes, int files, int seed) {
  final raf = File(path).openSync(mode: FileMode.write);
  var rng = seed & 0x7fffffff;
  int next() {
    rng = (rng * 1664525 + 1013904223) & 0x7fffffff;
    return rng;
  }

  var written = 0;
  final buf = StringBuffer();
  void flush() {
    if (buf.isEmpty) return;
    final bytes = utf8.encode(buf.toString());
    raf.writeFromSync(bytes);
    written += bytes.length;
    buf.clear();
  }

  final bytesPerFile = (targetBytes / files).floor();
  for (var f = 0; f < files; f++) {
    final name = 'graph_$f.gr';
    buf.write('diff --git a/$name b/$name\n');
    buf.write('index 0000000..1111111 100644\n');
    buf.write('--- a/$name\n');
    buf.write('+++ b/$name\n');
    final approxLines = (bytesPerFile / 48).floor().clamp(1, 1 << 30);
    buf.write('@@ -1,$approxLines +1,$approxLines @@\n');
    var fileBytes = 0;
    var emitted = 0;
    while (fileBytes < bytesPerFile && emitted < approxLines) {
      final t = next() % 90000000 + 1000000;
      final h = next() % 90000000 + 1000000;
      final wOld = next() % 900 + 100;
      final wNew = wOld + (next() % 9) + 1;
      final line = '-a $t $h $wOld\n+a $t $h $wNew\n';
      fileBytes += line.length;
      buf.write(line);
      emitted++;
      if (buf.length >= 1 << 20) flush();
    }
  }
  flush();
  raf.closeSync();
  return written;
}

/// Run the named stage on [raw]. Async stages poll currentRss between yields and
/// throw [_BudgetExceeded] if they cross [budgetBytes] — a cooperative backstop
/// so the harness self-limits before the OS has to.
Future<Object?> _runStage(String stage, String raw, int budgetBytes,
    {String? spoolPath}) async {
  switch (stage) {
    case 'eager':
      // The CURRENT broken combined path: one full DiffFileDocument per file,
      // materializing ~one ParsedLine per line. This is the OOM baseline.
      return DiffFileDocument.fromRawContent(rawContent: raw, pathHint: 'x.gr');
    case 'slice':
      // sliceDiffByFile's split('\n') + sublist/join — the copy cost alone.
      return sliceDiffByFile(raw);
    case 'index':
      // Just the sparse predictive index (no document wrapper).
      return PredictiveDiffIndex.build(raw);
    case 'filebacked':
      // Phase 3: the diff lives ONLY on disk (spoolPath). We build the index
      // over a FileByteStore — no in-RAM copy of the bytes at all. Peak RSS
      // should be ~flat across input sizes: resident = index + bounded page
      // cache, NOT the diff. This is the true disk-backed steady state (main()
      // never built a String for this stage).
      final store =
          FileByteStore.open(spoolPath!, pageSize: 512 * 1024, maxPages: 48);
      final idx = PredictiveDiffIndex.buildFromStore(store);
      // Touch a scattered sample of rows (viewport-sized) to exercise paging.
      var sink = 0;
      final n = idx.lineCount;
      for (final frac in [0.0, 0.25, 0.5, 0.75, 0.99]) {
        final start = (n * frac).floor().clamp(0, n > 0 ? n - 1 : 0);
        for (final row in idx.hydrateRange(start, 40)) {
          sink ^= row.text.length;
        }
      }
      return [store, idx, sink];
    case 'lazy':
      // The Phase-1 target: one lazy document over the whole combined buffer.
      final doc = await DiffDocument.lazyAsync(rawContent: raw, pathHint: 'x.gr');
      // Touch the first viewport so we measure real first-paint hydration too.
      final n = doc.lines.length;
      var sink = 0;
      for (var i = 0; i < 60 && i < n; i++) {
        sink ^= doc.lines[i].text.length;
      }
      return [doc, sink];
    default:
      throw ArgumentError('unknown stage: $stage');
  }
}

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final stage = args['stage'] ?? 'lazy';
  final bytes = int.parse(args['bytes'] ?? '${8 * _mib}');
  final files = int.parse(args['files'] ?? '1');
  final seed = int.parse(args['seed'] ?? '1234567');
  final budgetBytes = int.parse(args['budget-mb'] ?? '2048') * _mib;
  final source = args['source'] ?? 'synthetic';

  final baseRss = ProcessInfo.currentRss;

  // --- filebacked: the diff lives ONLY on disk; never build a String ---
  if (stage == 'filebacked') {
    String spoolPath;
    int inBytes;
    if (source.startsWith('file:')) {
      spoolPath = source.substring(5);
      inBytes = File(spoolPath).lengthSync();
    } else {
      final dir = Directory.systemTemp.createTempSync('diffspool');
      spoolPath = '${dir.path}/spool.diff';
      inBytes = _genDimacsDiffToFile(spoolPath, bytes, files, seed);
    }
    final rssAfterSpool = ProcessInfo.currentRss;
    final sw = Stopwatch()..start();
    var status = 'ok';
    Object? result;
    try {
      result = await _runStage('filebacked', '', budgetBytes,
          spoolPath: spoolPath);
    } catch (e) {
      status = 'error: $e';
    }
    sw.stop();
    final maxRss = ProcessInfo.maxRss;
    final reachable = result == null ? 0 : result.hashCode & 1;
    _emit({
      'stage': 'filebacked',
      'status': status,
      'source': source,
      'files': files,
      'inputBytes': inBytes,
      'wallMs': sw.elapsedMilliseconds,
      'baseRss': baseRss,
      'rssAfterGen': rssAfterSpool,
      'maxRss': maxRss,
      'peakOverBaseBytes': maxRss - baseRss,
      'stageDeltaBytes': maxRss - rssAfterSpool,
      'peakOverBasePerByte': inBytes == 0 ? 0 : (maxRss - baseRss) / inBytes,
      'stageDeltaPerByte': inBytes == 0 ? 0 : (maxRss - rssAfterSpool) / inBytes,
      'reachable': reachable,
    });
    return;
  }

  // --- build input ---
  String raw;
  if (source.startsWith('file:')) {
    // Already a unified diff on disk.
    raw = File(source.substring(5)).readAsStringSync();
  } else if (source.startsWith('newfile:')) {
    // Wrap a REAL file (e.g. a marble road graph) as the diff git produces for
    // an untracked/new file: header + `@@ -0,0 +1,N @@` + every line as `+`.
    // This is real content at real scale, exactly what stressed the app.
    final path = source.substring(8);
    final content = File(path).readAsStringSync();
    final name = path.split(RegExp(r'[\\/]')).last;
    final lineCount = '\n'.allMatches(content).length + 1;
    final sb = StringBuffer()
      ..write('diff --git a/$name b/$name\n')
      ..write('new file mode 100644\n')
      ..write('index 0000000..1111111\n')
      ..write('--- /dev/null\n')
      ..write('+++ b/$name\n')
      ..write('@@ -0,0 +1,$lineCount @@\n');
    for (final line in const LineSplitter().convert(content)) {
      sb.write('+');
      sb.write(line);
      sb.write('\n');
    }
    raw = sb.toString();
  } else {
    raw = _genDimacsDiff(bytes, files, seed);
  }
  final inputBytes = raw.length;
  final rssAfterGen = ProcessInfo.currentRss;

  // --- run stage, guarded ---
  final sw = Stopwatch()..start();
  Object? result;
  var status = 'ok';
  try {
    // A watchdog Timer catches budget breaches for stages that yield (async).
    // Synchronous stages can't be interrupted mid-alloc — the parent guarantees
    // it only requests sizes predicted under budget, so those never get here.
    final watchdog = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (ProcessInfo.currentRss > budgetBytes) {
        stderr.writeln('watchdog: currentRss over budget, aborting');
        // Best-effort: record and exit cleanly before the OS must intervene.
        _emit({
          'stage': stage,
          'status': 'aborted-at-budget',
          'inputBytes': inputBytes,
          'files': files,
          'wallMs': sw.elapsedMilliseconds,
          'baseRss': baseRss,
          'rssAfterGen': rssAfterGen,
          'maxRss': ProcessInfo.maxRss,
          'budgetBytes': budgetBytes,
        });
        exit(0);
      }
    });
    result = await _runStage(stage, raw, budgetBytes);
    watchdog.cancel();
  } catch (e) {
    status = 'error: $e';
  }
  sw.stop();

  final maxRss = ProcessInfo.maxRss;
  // Keep result reachable until after measurement so GC can't free the object
  // graph we're trying to weigh.
  final reachable = result == null ? 0 : result.hashCode & 1;

  _emit({
    'stage': stage,
    'status': status,
    'source': source,
    'files': files,
    'inputBytes': inputBytes,
    'wallMs': sw.elapsedMilliseconds,
    'baseRss': baseRss,
    'rssAfterGen': rssAfterGen,
    'maxRss': maxRss,
    // Peak RSS attributable to the whole pipeline (input string + stage), and
    // to the stage alone (marginal over the resident input). Both per input
    // byte — the multiplier the growth law fits.
    'peakOverBaseBytes': maxRss - baseRss,
    'stageDeltaBytes': maxRss - rssAfterGen,
    'peakOverBasePerByte': inputBytes == 0 ? 0 : (maxRss - baseRss) / inputBytes,
    'stageDeltaPerByte': inputBytes == 0 ? 0 : (maxRss - rssAfterGen) / inputBytes,
    'reachable': reachable,
  });
}

void _emit(Map<String, Object?> row) {
  stdout.writeln(jsonEncode(row));
}
