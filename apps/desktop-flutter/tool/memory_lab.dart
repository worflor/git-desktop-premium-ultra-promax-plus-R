// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// tool/memory_lab.dart — reproduce the "open a repo with multi-hundred-MB
// working-tree files, analysis pipelines fan out, switch repos" scenario in
// a CHILD process and report memory behaviour as JSON, so this never has to
// be tried on a developer's real machine.
//
// WHY a child process (never the host running the test): the whole point is
// to observe what happens when ingestion pressure gets close to — or past —
// a memory budget. That must be physically unable to take down the process
// running the test suite, so each invocation of this tool IS the sacrificial
// process: `dart run tool/memory_lab.dart --scenario=X` runs ONE lifecycle
// end to end and exits, win or die. The test (test/memory/
// ingestion_lifecycle_test.dart) only ever spawns this file via
// `Process.run` and parses its stdout.
//
// WHAT IT DRIVES (mirrors production exactly, not a toy):
//   PHASE analyze          -> lib/backend/logos_flow.dart analyzeFlowCached,
//                              batched 8-wide like ChangesetController._runFlow.
//   PHASE selectionDiff    -> the SAME transport choice lib/backend/git.dart's
//                              getSelectionDiff / spoolSelectionDiff make
//                              (sum on-disk bytes, spool above 64MB — see
//                              changes_page.dart's `_kSpoolSelectionThreshold`),
//                              landing in the SAME disk-backed index
//                              (lib/features/diff/predictive_diff_index.dart +
//                              byte_store.dart) DiffDocument builds on top of.
//   PHASE admissionPressure -> lib/backend/analysis_admission.dart directly:
//                              24 concurrent AnalysisAdmission.instance.run
//                              calls sized off the repo's real files, proving
//                              the queue drains back to zero in-flight bytes.
//   scenario=switch additionally drives lib/backend/analysis_admission.dart's
//   repoAnalysisScope.bump() mid-flight — the production repo-switch signal
//   — exactly where the marble incident stacked old-repo reads under new-repo
//   spin-up.
//
// FLUTTER-FREE ADAPTATION (read before touching this file). This tool runs
// under plain `dart run`, with NO Flutter engine — that is the whole point:
// no engine baseline muddying the RSS numbers. lib/backend/git.dart and
// lib/features/diff/diff_document.dart were expected to be pure Dart but, as
// of this writing, git.dart transitively imports
// lib/backend/repository_xray.dart -> lib/diagnostics/diagnostics_state.dart
// -> package:flutter/foundation.dart (and diff_document.dart imports git.dart
// just for the SpooledDiff type), so BOTH now drag in dart:ui under `dart
// run`. Per instructions, lib/ is not touched to fix that drift. Instead this
// tool talks to `git` itself exactly as getSelectionDiff/spoolSelectionDiff
// do (same flags, same base-revision logic, same streamed-to-disk shape) and
// builds directly on the actually-pure-Dart diff engine
// (predictive_diff_index.dart + byte_store.dart + dtos.dart + logos_flow.dart
// + analysis_admission.dart, all verified import-clean below) instead of
// going through DiffDocument. The memory shape measured is the same: an
// index over either a resident String or a FileByteStore-backed spool.
//
// SAFETY (never OOM the host): a periodic 25ms sampler aborts the run the
// instant currentRss crosses --budget-mb, emitting a partial verdict and
// calling `exit(0)` immediately — no unwind, no cleanup, on purpose (an
// isolate at the edge of OOM cannot be trusted to run further Dart code
// cleanly; the OS reclaims the temp dirs when the process dies). This
// mirrors tool/diff_load_profiler.dart's watchdog exactly.
//
// Usage:
//   dart run tool/memory_lab.dart --scenario=normal|heavy|switch \
//     [--budget-mb=2048]
//
// Emits exactly one JSON object on stdout (plus human notes on stderr).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:git_desktop/backend/analysis_admission.dart';
import 'package:git_desktop/backend/dtos.dart';
import 'package:git_desktop/backend/git_diff_paths.dart' show unCQuoteGitPath;
import 'package:git_desktop/backend/logos_flow.dart';
import 'package:git_desktop/features/diff/byte_store.dart';
import 'package:git_desktop/features/diff/predictive_diff_index.dart';

const int _mib = 1024 * 1024;

/// Above this estimated combined-selection size, [_selectionDiffPhase] routes
/// through the disk-backed spool transport instead of the in-RAM path —
/// the SAME threshold changes_page.dart gates on (see its
/// `_kSpoolSelectionThreshold`), reproduced here rather than imported because
/// changes_page.dart transitively pulls in package:flutter.
const int _kSpoolSelectionThreshold = 64 * _mib;

/// `-c diff.binary=false diff` — mirrors lib/backend/git.dart's `_kDiffCmd`
/// exactly (there is no `--no-binary` flag; pinning the config key is the
/// only way to turn binary diffs off). Content pins mirror `_kDiffContentPins`
/// — no color/ext-diff noise, stable a/ b/ prefixes so the synthetic
/// untracked-file diffs below parse identically to git's own tracked output.
const List<String> _kDiffCmd = ['-c', 'diff.binary=false', 'diff'];
const List<String> _kDiffContentPins = [
  '--no-color',
  '--no-ext-diff',
  '--src-prefix=a/',
  '--dst-prefix=b/',
];

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

void _emit(Map<String, Object?> row) {
  stdout.writeln(jsonEncode(row));
}

// ---------------------------------------------------------------------------
// RSS sampling / watchdog
// ---------------------------------------------------------------------------

/// Samples `ProcessInfo.currentRss` every 25ms, tracks a resettable
/// per-phase peak, and fires [onAbort] the instant `currentRss` crosses
/// [budgetBytes] — the cooperative backstop that keeps this tool's own OOM
/// (deliberately provoked by the heavy/switch scenarios) contained to THIS
/// process. [onAbort] is expected to emit a verdict and call `exit(0)`.
class _RssSampler {
  final int budgetBytes;
  final void Function() onAbort;
  int peak;
  late final Timer _timer;
  bool _aborted = false;

  _RssSampler(this.budgetBytes, {required this.onAbort})
    : peak = ProcessInfo.currentRss {
    _timer = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (_aborted) return;
      final r = ProcessInfo.currentRss;
      if (r > peak) peak = r;
      if (r > budgetBytes) {
        _aborted = true;
        _timer.cancel();
        onAbort();
      }
    });
  }

  /// Start attributing peak-RSS to a new phase window.
  void resetPeak() => peak = ProcessInfo.currentRss;

  void cancel() => _timer.cancel();
}

/// Run [body], attributing wall time and peak RSS (sampled by [sampler])
/// to phase [name] in [perPhase].
Future<void> _timedPhase(
  String name,
  _RssSampler sampler,
  Map<String, Map<String, Object?>> perPhase,
  Future<void> Function() body,
) async {
  sampler.resetPeak();
  final sw = Stopwatch()..start();
  await body();
  sw.stop();
  perPhase[name] = {'peakRss': sampler.peak, 'wallMs': sw.elapsedMilliseconds};
}

// ---------------------------------------------------------------------------
// Scratch repo construction — STREAMING writes only. Building an 8MB or
// 192MB String in RAM before writing it would make the harness itself the
// memory hazard it exists to measure.
// ---------------------------------------------------------------------------

Future<ProcessResult> _git(String repoPath, List<String> args) async {
  final result = await Process.run('git', args, workingDirectory: repoPath);
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      result.stderr.toString(),
      result.exitCode,
    );
  }
  return result;
}

Future<Directory> _initGitRepo(String prefix) async {
  final dir = await Directory.systemTemp.createTemp(prefix);
  await _git(dir.path, ['init', '-q']);
  // Local, repo-scoped identity — never touches the developer's global
  // gitconfig.
  await _git(dir.path, ['config', 'user.email', 'lab@memory-lab.test']);
  await _git(dir.path, ['config', 'user.name', 'Memory Lab']);
  return dir;
}

/// Streams ~[targetBytes] of deterministic DIMACS-ish content
/// (`a <t> <h> <w>\n`, seeded LCG — byte-identical every run) to [path] in
/// bounded 1MB chunks. Never holds the whole file in RAM. [mode] lets a
/// caller append to simulate a post-commit modification without rewriting
/// the file from scratch.
void _writeSeededContent(
  String path,
  int targetBytes,
  int seed, {
  FileMode mode = FileMode.write,
}) {
  final raf = File(path).openSync(mode: mode);
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

  while (written < targetBytes) {
    final t = next() % 90000000 + 1000000;
    final h = next() % 90000000 + 1000000;
    final w = next() % 900 + 100;
    buf.write('a $t $h $w\n');
    if (buf.length >= 1 << 20) flush();
  }
  flush();
  raf.closeSync();
}

/// `heavy`: one 8MB tracked file (committed, then modified so it shows as a
/// change) plus untracked working-tree data files at 192MB + 48MB + 48MB —
/// ~290MB total, the shape of the marble repo-switch incident (a few large
/// files, not thousands of small ones).
Future<Directory> _buildHeavyRepo() async {
  final dir = await _initGitRepo('memlab_heavy_');
  final sep = Platform.pathSeparator;
  final trackedPath = '${dir.path}$sep' 'tracked_big.gr';
  _writeSeededContent(trackedPath, 8 * _mib, 1001);
  await _git(dir.path, ['add', 'tracked_big.gr']);
  await _git(dir.path, ['commit', '-q', '-m', 'initial heavy']);
  // Post-commit modification: this is what makes the file show up as a
  // change for the analyze/selectionDiff phases to fan out over.
  _writeSeededContent(
    trackedPath,
    512 * 1024,
    2002,
    mode: FileMode.append,
  );

  _writeSeededContent('${dir.path}$sep' 'untracked_192.dat', 192 * _mib, 3003);
  _writeSeededContent('${dir.path}$sep' 'untracked_48a.dat', 48 * _mib, 4004);
  _writeSeededContent('${dir.path}$sep' 'untracked_48b.dat', 48 * _mib, 5005);
  return dir;
}

/// `normal`: 40 small (~2KB) tracked files modified after an initial commit,
/// plus 5 small untracked files — the human-scale changeset the admission
/// budget should never even notice.
Future<Directory> _buildNormalRepo() async {
  final dir = await _initGitRepo('memlab_normal_');
  final sep = Platform.pathSeparator;
  for (var i = 0; i < 40; i++) {
    _writeSeededContent(
      '${dir.path}$sep' 'tracked_$i.txt',
      2 * 1024,
      10000 + i,
    );
  }
  await _git(dir.path, ['add', '.']);
  await _git(dir.path, ['commit', '-q', '-m', 'initial normal']);
  for (var i = 0; i < 40; i++) {
    _writeSeededContent(
      '${dir.path}$sep' 'tracked_$i.txt',
      256,
      20000 + i,
      mode: FileMode.append,
    );
  }
  for (var i = 0; i < 5; i++) {
    _writeSeededContent(
      '${dir.path}$sep' 'untracked_$i.txt',
      2 * 1024,
      30000 + i,
    );
  }
  return dir;
}

// ---------------------------------------------------------------------------
// Phases — each replicates a real production ingestion path exactly, so
// what this tool measures is what the app actually does, not a proxy.
// ---------------------------------------------------------------------------

String _absPath(String repoPath, String relPath) =>
    '$repoPath${Platform.pathSeparator}'
    '${relPath.replaceAll('/', Platform.pathSeparator)}';

/// `git status --porcelain` (v1, not v2 — this tool only needs path + XY,
/// not the header/rename-score fields v2 adds) parsed into the same
/// [RepositoryStatusFile] shape production status parsing produces, so
/// downstream phases (analyze/selectionDiff/admissionPressure) see exactly
/// the file set the app would fan out over.
Future<List<RepositoryStatusFile>> _statusFiles(String repoPath) async {
  final r = await Process.run('git', [
    'status',
    '--porcelain',
  ], workingDirectory: repoPath);
  if (r.exitCode != 0) return const [];
  final files = <RepositoryStatusFile>[];
  for (final line in (r.stdout as String).split('\n')) {
    if (line.length < 4) continue;
    final staged = line[0];
    final unstaged = line[1];
    var path = line.substring(3).trim();
    final arrow = path.indexOf(' -> ');
    if (arrow >= 0) path = path.substring(arrow + 4);
    path = unCQuoteGitPath(path);
    if (path.isEmpty) continue;
    files.add(
      RepositoryStatusFile(
        path: path,
        staged: canonicalGitStatusCode(staged, stagedSlot: true),
        unstaged: canonicalGitStatusCode(unstaged, stagedSlot: false),
      ),
    );
  }
  return files;
}

/// `HEAD` when it resolves, else the repo's empty tree — mirrors
/// lib/backend/git.dart's `_selectionDiffBase` (unborn-HEAD repos diff
/// against nothing rather than failing).
Future<String> _selectionDiffBase(String repoPath) async {
  final head = await Process.run('git', [
    'rev-parse',
    '--verify',
    'HEAD',
  ], workingDirectory: repoPath);
  if (head.exitCode == 0) return 'HEAD';
  final emptyTree = await Process.run('git', [
    'hash-object',
    '-t',
    'tree',
    '/dev/null',
  ], workingDirectory: repoPath);
  return (emptyTree.stdout as String).trim();
}

List<String> _untrackedDiffArgs(String path) => [
  ..._kDiffCmd,
  '--no-index',
  ..._kDiffContentPins,
  '--',
  '/dev/null',
  path,
];

/// Mirrors ChangesetController._runFlow: every changed/untracked path,
/// 8-wide concurrency, through the SAME admission-gated, worker-isolate
/// analyzer production uses.
Future<void> _analyzePhase(
  String repoPath,
  List<RepositoryStatusFile> files,
) async {
  final paths = files
      .where((f) => f.hasAnyChange)
      .map((f) => _absPath(repoPath, f.path))
      .toList();
  const concurrency = 8;
  for (var i = 0; i < paths.length; i += concurrency) {
    final batch = paths.skip(i).take(concurrency).map((abs) async {
      try {
        await analyzeFlowCached(abs);
      } catch (_) {
        // A vanished/unreadable path is not this phase's failure mode.
      }
    });
    await Future.wait(batch);
  }
}

/// Mirrors changes_page.dart's transport choice: sum the selection's
/// on-disk bytes; above [_kSpoolSelectionThreshold] stream every `git diff`
/// invocation straight to a spool file and index it through a
/// [FileByteStore] (the disk-backed shape [DiffDocument.lazyFromSpool] builds
/// on internally); otherwise fetch the combined diff into one String and
/// index it directly (the in-RAM shape [DiffDocument.lazyAsync] builds on).
/// See the file-level FLUTTER-FREE ADAPTATION note for why this talks to
/// `git`/`PredictiveDiffIndex` directly instead of through git.dart /
/// DiffDocument.
Future<void> _selectionDiffPhase(
  String repoPath,
  List<RepositoryStatusFile> files,
) async {
  if (files.isEmpty) return;

  var totalBytes = 0;
  for (final f in files) {
    try {
      final stat = await File(_absPath(repoPath, f.path)).stat();
      if (stat.type == FileSystemEntityType.file) totalBytes += stat.size;
    } catch (_) {
      // Vanished between status and stat — not this phase's concern.
    }
    if (totalBytes > _kSpoolSelectionThreshold) break; // early out
  }

  final trackedPaths = files
      .where((f) => !f.isUntracked)
      .map((f) => f.path)
      .toList();
  final hasTrackedChange = files.any(
    (f) => !f.isUntracked && (f.hasStagedChange || f.hasUnstagedChange),
  );
  final untrackedPaths = files.where((f) => f.isUntracked).map((f) => f.path);

  if (totalBytes > _kSpoolSelectionThreshold) {
    // Streamed transport: every git invocation's stdout piped straight to
    // one spool file, nothing whole-diff ever resident.
    final dir = await Directory.systemTemp.createTemp('memlab_spool');
    final spoolPath = '${dir.path}${Platform.pathSeparator}selection.diff';
    final sink = File(spoolPath).openWrite();
    try {
      if (trackedPaths.isNotEmpty && hasTrackedChange) {
        final base = await _selectionDiffBase(repoPath);
        await _streamGitInto(sink, repoPath, [
          ..._kDiffCmd,
          ..._kDiffContentPins,
          '--full-index',
          '-U3',
          base,
          '--',
          ...trackedPaths,
        ]);
      }
      for (final path in untrackedPaths) {
        await _streamGitInto(
          sink,
          repoPath,
          _untrackedDiffArgs(path),
          okCodes: const {0, 1},
        );
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    final spoolStore = FileByteStore.open(
      spoolPath,
      pageSize: 512 * 1024,
      maxPages: 48,
    );
    try {
      final idx = await PredictiveDiffIndex.buildFromStoreAsync(spoolStore);
      _touchViewport(idx);
    } finally {
      // Windows cannot delete a directory containing an open file handle
      // (see DiffDocument.lazyFromSpool's spool-ownership contract for the
      // same constraint in production) — close the store BEFORE deleting.
      spoolStore.dispose();
    }
    await dir.delete(recursive: true);
  } else {
    // In-RAM transport: one combined String, indexed directly.
    final parts = <String>[];
    if (trackedPaths.isNotEmpty && hasTrackedChange) {
      final base = await _selectionDiffBase(repoPath);
      final r = await Process.run('git', [
        ..._kDiffCmd,
        ..._kDiffContentPins,
        '--full-index',
        '-U3',
        base,
        '--',
        ...trackedPaths,
      ], workingDirectory: repoPath);
      final out = (r.stdout as String).trim();
      if (out.isNotEmpty) parts.add(out);
    }
    for (final path in untrackedPaths) {
      final r = await Process.run(
        'git',
        _untrackedDiffArgs(path),
        workingDirectory: repoPath,
      );
      final out = (r.stdout as String).trim();
      if (out.isNotEmpty) parts.add(out);
    }
    final combined = parts.join('\n');
    if (combined.isNotEmpty) {
      final idx = await PredictiveDiffIndex.buildAsync(combined);
      _touchViewport(idx);
    }
  }
}

/// Touch a first-viewport-sized slice, like a real render would.
void _touchViewport(PredictiveDiffIndex idx) {
  var sink = 0;
  final n = idx.lineCount;
  for (final row in idx.hydrateRange(0, n < 60 ? n : 60)) {
    sink ^= row.text.length;
  }
  if (sink == -0x7fffffff) stderr.writeln('unreachable: $sink');
}

/// Pipe one `git` invocation's stdout into [sink] with backpressure — the
/// same shape as lib/backend/git.dart's `_streamGitDiffInto`, reimplemented
/// here because that helper is private to a Flutter-tainted library (see the
/// file-level FLUTTER-FREE ADAPTATION note).
Future<void> _streamGitInto(
  IOSink sink,
  String repoPath,
  List<String> args, {
  Set<int> okCodes = const {0},
}) async {
  final proc = await Process.start(
    'git',
    args,
    workingDirectory: repoPath,
  );
  final errDone = proc.stderr.drain<void>();
  await sink.addStream(proc.stdout);
  final code = await proc.exitCode;
  await errDone;
  if (!okCodes.contains(code)) {
    throw ProcessException('git', args, 'exit $code', code);
  }
}

/// Fires 24 concurrent [AnalysisAdmission.run] calls declared at the repo's
/// real file sizes (stat, not guesses) — the direct stress test of the
/// budget itself: files well over the 64MB budget must decline or queue,
/// never all admit at once, and in-flight bytes must return to zero.
Future<void> _admissionPressurePhase(
  String repoPath,
  List<RepositoryStatusFile> files,
) async {
  final sizes = <int>[];
  for (final f in files) {
    try {
      final stat = await File(_absPath(repoPath, f.path)).stat();
      if (stat.type == FileSystemEntityType.file) sizes.add(stat.size);
    } catch (_) {}
  }
  if (sizes.isEmpty) sizes.add(1024);

  final tasks = <Future<void>>[];
  for (var i = 0; i < 24; i++) {
    final bytes = sizes[i % sizes.length];
    tasks.add(
      AnalysisAdmission.instance
          .run(bytes, () => Future<void>.delayed(const Duration(milliseconds: 50)))
          .then((_) {}),
    );
  }
  await Future.wait(tasks);
}

/// Runs all three phases in order for one repo, recording each under
/// `$label.<phase>` in [perPhase].
Future<void> _runLifecycle(
  String label,
  String repoPath,
  _RssSampler sampler,
  Map<String, Map<String, Object?>> perPhase,
) async {
  final files = await _statusFiles(repoPath);

  await _timedPhase(
    '$label.analyze',
    sampler,
    perPhase,
    () => _analyzePhase(repoPath, files),
  );
  await _timedPhase(
    '$label.selectionDiff',
    sampler,
    perPhase,
    () => _selectionDiffPhase(repoPath, files),
  );
  await _timedPhase(
    '$label.admissionPressure',
    sampler,
    perPhase,
    () => _admissionPressurePhase(repoPath, files),
  );
}

// ---------------------------------------------------------------------------

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);
  final scenario = args['scenario'] ?? 'normal';
  final budgetBytes = int.parse(args['budget-mb'] ?? '2048') * _mib;

  final baseRss = ProcessInfo.currentRss;
  final perPhase = <String, Map<String, Object?>>{};

  late final _RssSampler sampler;
  sampler = _RssSampler(
    budgetBytes,
    onAbort: () {
      // Emit whatever partial data exists and die immediately — no unwind,
      // no temp-dir cleanup. This IS the "never OOM the host" guarantee:
      // trusting an isolate this close to the budget to run more Dart code
      // cleanly (including a finally block) is exactly the risk this exists
      // to remove. The OS reclaims this process's memory and temp files.
      _emit({
        'scenario': scenario,
        'status': 'aborted-at-budget',
        'baseRss': baseRss,
        'perPhase': perPhase,
        'peakRss': ProcessInfo.maxRss,
        'budgetBytes': budgetBytes,
      });
      exit(0);
    },
  );

  final dirs = <Directory>[];
  try {
    switch (scenario) {
      case 'normal':
        final repo = await _buildNormalRepo();
        dirs.add(repo);
        await _runLifecycle('normal', repo.path, sampler, perPhase);
        break;

      case 'heavy':
        final repo = await _buildHeavyRepo();
        dirs.add(repo);
        await _runLifecycle('heavy', repo.path, sampler, perPhase);
        break;

      case 'switch':
        // Build both repos up front (mirrors "the old repo's files are
        // still on disk when you switch away" — nothing about a repo
        // switch deletes the old working tree).
        final heavy = await _buildHeavyRepo();
        final normal = await _buildNormalRepo();
        dirs.addAll([heavy, normal]);

        final heavyFiles = await _statusFiles(heavy.path);

        // Launch heavy's analyze fan-out but do NOT await it — this is the
        // exact shape of the incident: analysis for the repo you're
        // LEAVING is still in flight when you open the next one.
        sampler.resetPeak();
        final launchSw = Stopwatch()..start();
        final heavyAnalyzeFuture = _analyzePhase(heavy.path, heavyFiles);
        // The production repo-switch signal: drop everything still QUEUED
        // for the old repo before it reads a byte. Already-running work
        // (admitted before the bump) drains under budget regardless.
        repoAnalysisScope.bump();
        launchSw.stop();
        perPhase['heavy_analyze_launch'] = {
          'peakRss': sampler.peak,
          'wallMs': launchSw.elapsedMilliseconds,
        };

        // The repo you switched TO gets its full lifecycle.
        await _runLifecycle('normal', normal.path, sampler, perPhase);

        // Whatever heavy work was already admitted must still drain cleanly.
        await _timedPhase(
          'heavy_leftover_await',
          sampler,
          perPhase,
          () => heavyAnalyzeFuture,
        );
        break;

      default:
        throw ArgumentError('unknown scenario: $scenario');
    }

    // Drop every reference this scope held, then give the VM's GC repeated
    // chances to actually reclaim before reading the settled RSS — a single
    // delay often lands mid-collection.
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final endRss = ProcessInfo.currentRss;
    sampler.cancel();

    _emit({
      'scenario': scenario,
      'status': 'ok',
      'baseRss': baseRss,
      'perPhase': perPhase,
      'peakRss': ProcessInfo.maxRss,
      'endRss': endRss,
      'retainedOverBase': endRss - baseRss,
      'admissionEndInFlight': AnalysisAdmission.instance.inFlightBytes,
      'admissionEndQueued': AnalysisAdmission.instance.queuedCount,
    });
  } finally {
    sampler.cancel();
    for (final d in dirs) {
      try {
        await d.delete(recursive: true);
      } catch (_) {
        // Best-effort — a locked file on Windows must not fail the run.
      }
    }
  }
}
