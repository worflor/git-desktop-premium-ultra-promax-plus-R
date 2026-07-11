import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Architectural tripwire, not a behavior test — same shape and same
/// justification as `test/backend/manifold_refs_transport_guard_test.dart`
/// and `test/architecture/theme_compliance_ratchet_test.dart`: no compiler
/// or lint rule distinguishes "this line reads real ambient nondeterminism"
/// from "this line is an ordinary, harmless call" by its type signature
/// alone. A source scan is the only mechanism that catches the regression
/// class before it lands.
///
/// Why this specific regression class matters here: `test/support/`
/// (`prop`, `gen`, `scratch_repo`, `os_probe_corpus`) and
/// `test/fuzz/cross_os_differential_test.dart` both stand on one load-
/// bearing assumption — that the engine/pure layer (`lib/backend/`,
/// especially anything spectral/coupling/logos/gyat/engram-shaped) is a
/// deterministic function of its explicit inputs. The cross-OS oracle runs
/// the SAME corpus on Windows and under WSL2 Linux and diffs the output
/// byte-for-byte; the property/fuzz harness re-runs the SAME seed and
/// expects the SAME result. An unseeded `Random()`, a `DateTime.now()`
/// read inside engine code, a `String.hashCode` persisted as a cache key,
/// or a `Map.values.first` pulled from a map built out of unordered input
/// doesn't fail loudly — it produces a flaky assertion hours or runs later
/// that looks like a fuzz-harness bug and sends someone hunting through the
/// wrong file. See MEMORY: project_test_hardening_swarm — this whole
/// fuzz/property foundation exists because prior nondeterminism bugs (B5-
/// B25) were real and expensive to chase down after the fact; this test
/// is the tripwire that should have caught them before they were committed.
///
/// RATCHET philosophy (see `lib/backend/review_ratchet.dart`): every rule
/// below measures today's violating-file count and pins it as a ceiling.
/// Rules whose measured baseline is 0 are hard gates instead (nothing to
/// grandfather in) — see the per-rule comments for which is which.
void main() {
  final libDir = Directory(p.join(Directory.current.path, 'lib'));
  final backendDir =
      Directory(p.join(Directory.current.path, 'lib', 'backend'));

  List<File> dartFilesIn(Directory dir) => dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  String relPath(File f) =>
      p.posix.joinAll(p.split(p.relative(f.path, from: Directory.current.path)));

  // ---------------------------------------------------------------------
  // Rule 1 — no unseeded Random() in lib/backend/.
  //
  // `math.Random()` with no seed draws from OS entropy: two runs, two
  // different sequences. That's exactly wrong for a layer that fuzz/
  // property tests expect to reproduce byte-for-byte given the same
  // inputs. `lib/backend/git.dart` is the one documented, legitimate
  // exception: `_gitRetryJitter` exists purely to de-correlate the
  // transient-`index.lock` backoff of two of our own colliding
  // subprocesses — if it were seeded/reproducible, two racing retries
  // would stay perfectly in lockstep and keep re-colliding forever. The
  // whole point of that jitter is that it must NOT be reproducible.
  // ---------------------------------------------------------------------
  test('no unseeded Random() in lib/backend/ outside the documented '
      'git.dart retry-jitter holdout', () {
    final pattern = RegExp(r'Random\(\s*\)');
    const allowlistedForJitter = 'lib/backend/git.dart';
    final offenders = <String>[];
    for (final f in dartFilesIn(backendDir)) {
      final rel = relPath(f);
      if (rel == allowlistedForJitter) continue;
      if (pattern.hasMatch(f.readAsStringSync())) offenders.add(rel);
    }
    offenders.sort();
    const baseline = 1; // measured 2026-07-09: lib/backend/external_tools.dart
    // (_newId() mixes an unseeded 4-char Random suffix into a tool-list
    // id — fine for avoiding collisions in a <100-item user list, not
    // fine as a precedent; new engine code should not copy this pattern).
    if (offenders.length < baseline) {
      // ignore: avoid_print
      print('Random() offender count dropped to ${offenders.length} '
          '(baseline $baseline) — lower the baseline in '
          'determinism_tripwire_test.dart.');
    }
    expect(offenders.length, lessThanOrEqualTo(baseline),
        reason: 'unseeded Random() found outside the git.dart jitter '
            'holdout in: ${offenders.take(5).toList()}. Every unseeded '
            'Random() in lib/backend/ is a place two runs of the same '
            'input can diverge — either seed it explicitly, or if it is a '
            'genuine anti-collision/jitter use (like git.dart\'s retry '
            'backoff), allowlist it here with the same justification.');
  });

  // ---------------------------------------------------------------------
  // Rule 2 — no DateTime.now() in engine-named lib/backend/ files.
  //
  // Filename-based, not call-site-based: the point is that files whose
  // names advertise "I am the pure engine" (logos/spectral/coupling/
  // gyat/engram) should not read the wall clock at all, so nobody has to
  // audit call sites individually to trust the cross-OS oracle's output.
  // Measured 2026-07-09, every hit here is currently a cache-freshness/
  // TTL timestamp or a diagnostics-event stamp (not a value that feeds
  // into a computed engine result) — legitimate today, but exactly the
  // kind of thing that quietly stops being legitimate the next time
  // someone reuses one of these `now` locals for real math instead of
  // freshness bookkeeping. That's what this ratchet is watching for.
  // ---------------------------------------------------------------------
  test('no DateTime.now() in logos/spectral/coupling/gyat/engram-named '
      'lib/backend/ files', () {
    final namePattern =
        RegExp(r'logos|spectral|coupling|gyat|engram', caseSensitive: false);
    final nowPattern = RegExp(r'DateTime\.now\(\)');
    final offenders = <String>[];
    for (final f in dartFilesIn(backendDir)) {
      final rel = relPath(f);
      final baseName = p.basename(rel);
      if (!namePattern.hasMatch(baseName)) continue;
      if (nowPattern.hasMatch(f.readAsStringSync())) offenders.add(rel);
    }
    offenders.sort();
    const baseline = 6; // measured 2026-07-09
    if (offenders.length < baseline) {
      // ignore: avoid_print
      print('DateTime.now() offender count dropped to ${offenders.length} '
          '(baseline $baseline) — lower the baseline in '
          'determinism_tripwire_test.dart.');
    }
    expect(offenders.length, lessThanOrEqualTo(baseline),
        reason: 'DateTime.now() found in engine-named files: '
            '${offenders.take(5).toList()}. The cross-OS differential '
            'oracle and the property/fuzz harness both assume the engine '
            'layer is a pure function of the repo — a wall-clock read '
            'inside it is either dead weight (should be passed in as an '
            'explicit parameter) or a live bug (the computed result now '
            'depends on when the test happened to run).');
  });

  // ---------------------------------------------------------------------
  // Rule 3 — no Platform.is* outside the cross-OS probe corpus's
  // documented INTENTIONAL:: allowlist.
  //
  // `test/support/os_probe_corpus.dart` already draws this exact line:
  // ordinary probe keys are asserted EQUAL across Windows and WSL2 Linux
  // (a mismatch is a genuine cross-OS bug), while `INTENTIONAL::`-
  // prefixed keys read ambient `Platform.is*` by design and are asserted
  // per-OS instead. `LogosSseStore.lockKeyFor`
  // (lib/backend/logos_git_calibration.dart) is the one documented case
  // today. This test does not re-derive that allowlist — it just pins
  // the total COUNT of lib/ files that read a `Platform.is*` getter at
  // all, so that every NEW one is a forcing function: either it needs an
  // `INTENTIONAL::` entry in the probe corpus (so the differential oracle
  // actually exercises both branches), or it's an untested cross-OS
  // divergence waiting to bite someone on the platform nobody's laptop
  // runs.
  // ---------------------------------------------------------------------
  test('Platform.is* reads in lib/ are pinned to the measured baseline', () {
    final pattern = RegExp(r'Platform\.is(Windows|Linux|macOS|MacOS)\b');
    final offenders = <String>[];
    for (final f in dartFilesIn(libDir)) {
      if (pattern.hasMatch(f.readAsStringSync())) offenders.add(relPath(f));
    }
    offenders.sort();
    const baseline = 19; // measured 2026-07-11; atomic fsync capability probed
    if (offenders.length < baseline) {
      // ignore: avoid_print
      print('Platform.is* offender count dropped to ${offenders.length} '
          '(baseline $baseline) — lower the baseline in '
          'determinism_tripwire_test.dart.');
    }
    expect(offenders.length, lessThanOrEqualTo(baseline),
        reason: 'Platform.is* reads found in: ${offenders.take(5).toList()} '
            '(full measured set: $offenders). A new Platform.is* read '
            'needs either an INTENTIONAL:: entry in '
            'test/support/os_probe_corpus.dart (so the WSL2 differential '
            'oracle actually exercises the branch) or removal — otherwise '
            'it is an untested cross-OS divergence.');
  });

  // ---------------------------------------------------------------------
  // Rule 4 — no `hashCode` used for persistence.
  //
  // `String.hashCode` in Dart is explicitly NOT guaranteed stable across
  // VM versions, and is not guaranteed stable across isolates either
  // (several files in this codebase already carry comments to this
  // effect — see nudge_ledger.dart, review_ratchet_store.dart,
  // repo_native_embedding.dart). Writing it to disk, or using it as a
  // cache key that's compared across process restarts, silently
  // invalidates everything the moment the Dart SDK is upgraded. The
  // heuristic: flag any line containing `hashCode` that ALSO mentions
  // `write`, `store`, `persist`, `key`, or `cacheKey` — the vocabulary a
  // real persistence call site uses.
  // ---------------------------------------------------------------------
  test('hashCode is never combined with a persistence/key verb on the '
      'same line in lib/backend/', () {
    final pattern = RegExp(
      r'hashCode.*(write|store|persist|key|cacheKey)|(write|store|persist|key|cacheKey).*hashCode',
      caseSensitive: false,
    );
    // Match CODE, not prose. This rule is about a `hashCode` being *used* as
    // persistence, so a doc comment that MENTIONS both words — usually to
    // explain "this hashCode is in-memory and never persisted", exactly the
    // safe pattern — must not trip it. Strip everything from the first `//`
    // to end-of-line before matching. (A `//` inside a string literal that
    // ALSO carries a hashCode+persistence-verb on the same line is not a
    // shape that occurs; the simple cut is sufficient here.)
    String stripComment(String line) {
      final i = line.indexOf('//');
      return i < 0 ? line : line.substring(0, i);
    }

    final offenders = <String>[];
    for (final f in dartFilesIn(backendDir)) {
      final lines = f.readAsLinesSync();
      if (lines.map(stripComment).any(pattern.hasMatch)) {
        offenders.add(relPath(f));
      }
    }
    offenders.sort();
    // Baseline 1 (2026-07-09, comment-stripped): only
    // lib/backend/diff_logos_facade.dart's `_requestCacheKey`, which folds
    // `request.diffText.hashCode` into a cache-key string in CODE. The former
    // lru_cache.dart and file_coupling.dart hits were doc comments EXPLAINING
    // why a hashCode is safe there — correctly excluded now that the scan
    // ignores comments.
    const baseline = 1;
    if (offenders.length < baseline) {
      // ignore: avoid_print
      print('hashCode/persistence offender count dropped to '
          '${offenders.length} (baseline $baseline) — lower the baseline '
          'in determinism_tripwire_test.dart.');
    }
    expect(offenders.length, lessThanOrEqualTo(baseline),
        reason: 'hashCode used alongside a persistence/key verb (in CODE, '
            'comments stripped) in: ${offenders.take(5).toList()}. The one '
            'baseline hit — lib/backend/diff_logos_facade.dart\'s '
            '`_requestCacheKey` — folds `request.diffText.hashCode` into a '
            'cache key, safe ONLY because that key lives in an in-memory Map '
            'for one running session and is never written to disk or compared '
            'across process restarts. A NEW hit means a hashCode is being '
            'used where a stable content hash is required — replace it (see '
            'FileCouplingMatrix.contentHash for the pattern).');
  });

  // ---------------------------------------------------------------------
  // Rule 5 — no relying on Map iteration order via .keys.first /
  // .values.first / .entries.first in lib/backend/.
  //
  // Dart's `Map` (LinkedHashMap under the hood for the built-in literal)
  // iterates in insertion order, so `.first` is *usually* harmless — but
  // "usually" is exactly the nondeterminism this whole test file exists
  // to flag. The moment one of these maps is built by merging two other
  // maps, deserializing JSON (whose key order is not guaranteed to
  // survive a round trip the same way on every parser), or populated from
  // a `Set`/concurrent source, `.first` silently starts picking whichever
  // entry happened to land first instead of a deliberately-chosen one.
  // ---------------------------------------------------------------------
  test('no .keys.first / .values.first / .entries.first in lib/backend/',
      () {
    final pattern = RegExp(r'\.keys\.first|\.values\.first|\.entries\.first');
    final offenders = <String>[];
    for (final f in dartFilesIn(backendDir)) {
      if (pattern.hasMatch(f.readAsStringSync())) offenders.add(relPath(f));
    }
    offenders.sort();
    const baseline = 7; // measured 2026-07-09
    if (offenders.length < baseline) {
      // ignore: avoid_print
      print('.first-on-map offender count dropped to ${offenders.length} '
          '(baseline $baseline) — lower the baseline in '
          'determinism_tripwire_test.dart.');
    }
    expect(offenders.length, lessThanOrEqualTo(baseline),
        reason: '.keys.first / .values.first / .entries.first found in: '
            '${offenders.take(5).toList()}. Each site is worth a manual '
            'check for whether the underlying map\'s insertion order is '
            'actually deliberate (fine) or incidental (a latent '
            'nondeterminism — prefer an explicit sort/selection instead '
            'of relying on whatever order the map happened to be built '
            'in).');
  });
}
