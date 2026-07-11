// source_laws_test.dart — the codebase reads itself.
//
// Structural laws over lib/'s real AST (test/support/law_corpus.dart). Each
// law converts a convention that previously lived in review discipline or a
// dossier into a failing test the moment it is violated. Two enforcement
// shapes:
//
//   EXACT laws have zero violations today and must stay at zero — the bug
//   class is closed and this suite keeps it closed.
//
//   RATCHET laws freeze today's violation surface as a per-file baseline.
//   A count above baseline = a NEW site of the risky pattern → the failure
//   message says what to use instead (usually a seam). A count below
//   baseline = progress → the message prints the regenerated literal to
//   paste, so the surface only ever shrinks (same doctrine as the review
//   ratchet). Either way the fix is a one-line paste, never archaeology.
//
// Run: flutter test test/laws/  (runs with the normal suite; no new step)

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/law_corpus.dart';

// ── Ratchet baselines ──────────────────────────────────────────────────────
// Regenerate any of these by running the suite: the failure message prints
// the exact literal to paste.

/// Process.run/start/runSync call sites per file. New spawn sites belong
/// behind the existing seams (backend/git.dart's runner, process_utils) so
/// they inherit fault injection, chaos scheduling, and telemetry for free.
const _processSpawnBaseline = <String, int>{
  'lib/app/desk_issue_state.dart': 1,
  'lib/app/desk_pr_state.dart': 1,
  'lib/backend/ai.dart': 4,
  'lib/backend/ai_api_keys_store.dart': 2,
  'lib/backend/aperture_sweep.dart': 4,
  'lib/backend/desk_pr_diff.dart': 3,
  'lib/backend/gh.dart': 4,
  'lib/backend/git.dart': 2,
  'lib/backend/glab.dart': 3,
  'lib/backend/history_surgery.dart': 25,
  'lib/backend/ipc/pipe_commands.dart': 1,
  'lib/backend/logos_git_probe.dart': 2,
  'lib/backend/logos_git_stats.dart': 3,
  'lib/backend/manifold_refs.dart': 2,
  'lib/backend/process_utils.dart': 3,
  'lib/backend/release_state.dart': 1,
  'lib/backend/repo_blob_walk.dart': 1,
  'lib/backend/spectral_trajectory_builder.dart': 1,
  'lib/backend/system_browser.dart': 3,
  'lib/backend/system_paths.dart': 16,
  'lib/backend/tool_detection.dart': 1,
  'lib/backend/wick.dart': 3,
  'lib/features/branches/branches_page.dart': 2,
  'lib/features/changes/changes_page.dart': 2,
  'lib/features/changes/merge_conflict_editor.dart': 1,
  'lib/features/history/worldline_field.dart': 1,
  'lib/features/history_surgery/history_surgery_page.dart': 1,
  'lib/features/palette/palette_registry.dart': 3,
  'lib/features/xray/repo_xray_panel.dart': 3,
};

/// Raw truncating writeAsString/writeAsBytes sites per file (atomic_write.dart
/// itself is the seam and is exempt). Durable app-state writes belong on
/// writeFileAtomic/writeFileAtomicString — the torn-snapshot bug class (B20).
const _rawWriteBaseline = <String, int>{
  'lib/backend/ai.dart': 3,
  'lib/backend/command_telemetry_store.dart': 2,
  'lib/backend/engram_file_index_cache.dart': 1,
  'lib/backend/git.dart': 13,
  'lib/backend/ipc/pipe_server.dart': 2,
  'lib/backend/logos_git_calibration.dart': 1,
  'lib/backend/nudge_ledger.dart': 1,
  'lib/backend/spectral_persistence.dart': 1,
  'lib/backend/system_paths.dart': 2,
  'lib/features/branches/branches_page.dart': 1,
  'lib/features/changes/changes_page.dart': 5,
  'lib/features/changes/merge_conflict_editor.dart': 1,
  'lib/features/changes/merge_conflict_flow.dart': 2,
  'lib/features/palette/palette_state.dart': 1,
  'lib/features/xray/repo_xray_panel.dart': 3,
};

/// Wall-clock reads (DateTime.now / unseeded Random) inside the deterministic
/// engine files (logos_/spectral_/engram_/gyat/lrg_/resonance_). Wall-clock
/// inside engine math breaks replayability — inject a clock or seed instead.
const _engineWallClockBaseline = <String, int>{
  'lib/backend/logos_branch_orbit.dart': 1,
  'lib/backend/logos_git_calibration.dart': 13,
  'lib/backend/logos_git_diagnostics.dart': 5,
  'lib/backend/logos_git_resolver.dart': 5,
  'lib/backend/spectral_trajectory_builder.dart': 2,
};

/// Files allowed to mention the `refs/manifold` namespace in a string
/// literal. The staging-namespace laws (never fetch remote refs onto
/// refs/manifold/*) are only auditable while the namespace's blast radius
/// stays enumerable — a new file touching it must be a conscious decision.
const _manifoldRefFiles = <String>{
  'lib/backend/manifold_ref_types.dart',
  'lib/backend/manifold_refs.dart',
};

/// lib/backend files that persist state (raw writes, openWrite sinks, or
/// writeFileAtomic) but are deliberately NOT covered by the torn-write
/// crash-consistency corpus, with the reason on record.
const _tornWriteExemptions = <String, String>{
  'lib/backend/git.dart':
      'writes are working-tree / patch / index plumbing inside the USER repo '
          '(git\'s own crash domain), not app-data snapshots',
  'lib/backend/ai.dart':
      'ephemeral per-invocation artifacts (codex piggyback proxy config, '
          'prompt temp files) in temp dirs; the model disk cache rides '
          'writeFileAtomic — documented in the torn-write suite header',
  'lib/backend/ipc/pipe_server.dart':
      'per-pid discovery beacons (manifold-<pid>.lock) — ephemeral by '
          'construction; stale/torn beacons are skipped and re-created',
  'lib/backend/logos_git_calibration.dart':
      'recomputable calibration cache with its own pid+timestamp tmp '
          'choreography; loss degrades to recompute, never to data loss',
  'lib/backend/system_paths.dart':
      'throwaway shell/reveal scripts in a fresh systemTemp dir, executed '
          'once and abandoned — not state anything loads back',
};

void main() {
  final corpus = LawCorpus.load();
  final byPath = {for (final f in corpus.files) f.path: f};

  test('L0: every lib/ file parses cleanly', () {
    final broken = [
      for (final f in corpus.files)
        if (f.syntaxErrors.isNotEmpty) '${f.path}\n  ${f.syntaxErrors.join('\n  ')}',
    ];
    expect(broken, isEmpty,
        reason: 'Files the law corpus could not parse — every other law '
            'silently undercounts on these:\n${broken.join('\n')}');
  });

  test('L1: dart:ffi is confined to the audited FFI files', () {
    // The two audited FFI edges: win_job_object.dart (Windows kill-on-close
    // job objects) and atomic_write.dart (POSIX parent-directory fsync for
    // rename durability — dart:io has no directory-fsync API).
    const auditedFfiFiles = {
      'lib/backend/win_job_object.dart',
      'lib/backend/atomic_write.dart',
    };
    final offenders = [
      for (final f in corpus.files)
        if (f.facts.imports.contains('dart:ffi') &&
            !auditedFfiFiles.contains(f.path))
          f.path,
    ];
    expect(offenders, isEmpty,
        reason: 'dart:ffi is the one memory-unsafe edge in the app; it stays '
            'behind audited files. New FFI goes in (or behind) one of '
            '$auditedFfiFiles, or a new file added here deliberately. '
            'Offenders: $offenders');
  });

  test('L2: no dev-only packages imported from lib/', () {
    const devOnly = ['package:analyzer/', 'package:flutter_test/'];
    final offenders = [
      for (final f in corpus.files)
        for (final imp in f.facts.imports)
          if (devOnly.any(imp.startsWith)) '${f.path} imports $imp',
    ];
    expect(offenders, isEmpty,
        reason: 'dev_dependencies must not leak into the shipped app:\n'
            '${offenders.join('\n')}');
  });

  test('L3: no raw control bytes in source', () {
    // The NUL-in-string-literal incident: invisible in diffs, turns the file
    // binary for grep. Raw C0 control bytes (except \t \n \r) never belong in
    // source — escape them (`\x00`) so they are visible and diffable.
    const allowed = {0x09, 0x0A, 0x0D};
    final offenders = [
      for (final f in corpus.files)
        for (var i = 0; i < f.bytes.length; i++)
          if (f.bytes[i] < 0x20 && !allowed.contains(f.bytes[i]))
            '${f.path}: raw byte 0x${f.bytes[i].toRadixString(16).padLeft(2, '0')} at offset $i',
    ];
    expect(offenders, isEmpty,
        reason: 'Raw control bytes in source (write them escaped instead):\n'
            '${offenders.join('\n')}');
  });

  test('L4: %09 stays confined to git.dart', () {
    // %09 is valid in for-each-ref format strings (branch/tag) but NOT in
    // pretty-format (log/reflog), where git emits the three chars verbatim
    // and every downstream split(\'\\t\') silently yields garbage — the
    // reflog bug. git.dart documents the distinction at its use sites; any
    // other file using %09 is one confusion away from re-shipping it.
    final offenders = [
      for (final f in corpus.files)
        if (f.path != 'lib/backend/git.dart' &&
            f.facts.stringLiterals.any((s) => s.contains('%09')))
          f.path,
    ];
    expect(offenders, isEmpty,
        reason: 'Only git.dart may use %09 (and only in for-each-ref '
            'formats — see the listReflog comment). Offenders: $offenders');
  });

  test('L5: codex --sandbox is always pinned to read-only', () {
    // The codex sandbox incident: codex exec must pin --sandbox read-only on
    // EVERY call. Structurally: every \'--sandbox\' list element is
    // immediately followed by \'read-only\', and ai.dart has at least one.
    final ai = byPath['lib/backend/ai.dart'];
    expect(ai, isNotNull, reason: 'lib/backend/ai.dart moved — update law L5');
    expect(ai!.facts.sandboxFlags, greaterThanOrEqualTo(1),
        reason: 'The codex exec argv no longer pins --sandbox at all — this '
            'is the exact incident regression. Restore the '
            "'--sandbox', 'read-only' pair (NEVER remove it).");
    final offenders = [
      for (final f in corpus.files)
        if (f.facts.sandboxAdjacencyViolations > 0)
          '${f.path}: ${f.facts.sandboxAdjacencyViolations}',
    ];
    expect(offenders, isEmpty,
        reason: "Every '--sandbox' argv element must be immediately followed "
            "by 'read-only': $offenders");
  });

  test('L11: staging-namespace literal confined to the ref-type algebra', () {
    // 'refs/manifold-remote' (the staging root) may only be SPELLED in
    // manifold_ref_types.dart — everywhere else it must come off
    // MetadataRemote.stagingPrefix / stage() / unstage(), so the
    // live↔staged conversion can never be re-derived by ad-hoc string
    // surgery (the bug class the typed algebra closed).
    final offenders = [
      for (final f in corpus.files)
        if (f.path != 'lib/backend/manifold_ref_types.dart' &&
            f.facts.stringLiterals.any((s) => s.contains('refs/manifold-remote')))
          f.path,
    ];
    expect(offenders, isEmpty,
        reason: 'Staging refs are built via MetadataRemote, never spelled: '
            '$offenders');
  });

  test('L12: the zero oid is spelled once', () {
    // The 40-zero CAS sentinel lives as Oid.zero; a re-spelled literal is
    // one typo away from a 39-zero string that git rejects at runtime.
    final zeros = '0' * 40;
    final offenders = [
      for (final f in corpus.files)
        if (f.path != 'lib/backend/manifold_ref_types.dart' &&
            f.facts.stringLiterals.any((s) => s.contains(zeros)))
          f.path,
    ];
    expect(offenders, isEmpty,
        reason: 'Use Oid.zero (manifold_ref_types.dart), never a literal: '
            '$offenders');
  });

  test('L13: manifold outcome APIs carry @useResult', () {
    // Every PUBLIC method returning a GitResult in the manifold trio must
    // be @useResult — dropping one silently swallows the error path
    // (unused_result is a hard analyzer error, so annotated = enforced).
    // A new outcome-bearing method added without the annotation fails
    // here; the sweep can never silently decay.
    const domain = [
      'lib/backend/manifold_refs.dart',
      'lib/backend/desk_pr_store.dart',
      'lib/backend/desk_issue_store.dart',
    ];
    final offenders = <String>[];
    for (final path in domain) {
      final f = byPath[path];
      expect(f, isNotNull, reason: '$path moved — update law L13');
      for (final decl in f!.unit.declarations) {
        if (decl is! ClassDeclaration) continue;
        // analyzer 10 deprecates .members toward a ClassBody API that does
        // not expose the member list yet — keep the working accessor.
        // ignore: deprecated_member_use
        for (final member in decl.members) {
          if (member is! MethodDeclaration) continue;
          final name = member.name.lexeme;
          if (name.startsWith('_')) continue;
          final ret = member.returnType?.toSource() ?? '';
          if (!ret.contains('GitResult')) continue;
          final annotated =
              member.metadata.any((a) => a.name.name == 'useResult');
          if (!annotated) offenders.add('$path: $name');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Public GitResult APIs missing @useResult:\n'
            '${offenders.join('\n')}');
  });

  test('L14: an LruCache of disposables must release on eviction', () {
    // A cache of TextPainter/Image/Picture/Paragraph that omits onEvict
    // leaks the native resources of every value it evicts, overwrites, or
    // clears (the diff-row painter-cache leak, fixed 2026-07-10). The only
    // safe form is `onEvict: (v) => v.dispose()`. Zero violations today.
    final offenders = [
      for (final f in corpus.files)
        for (final vType in f.facts.lruDisposableNoEvict)
          '${f.path}: LruCache<_, $vType> without onEvict',
    ];
    expect(offenders, isEmpty,
        reason: 'LruCache of a native-resource disposable must pass '
            'onEvict: (v) => v.dispose():\n${offenders.join('\n')}');
  });

  test('L6 (ratchet): Process spawn surface only shrinks', () {
    _expectRatchet(
      law: 'L6 process-spawn',
      constName: '_processSpawnBaseline',
      baseline: _processSpawnBaseline,
      actual: {
        for (final f in corpus.files)
          if (f.facts.processSpawns > 0) f.path: f.facts.processSpawns,
      },
      onNewSite: 'New Process.run/start sites belong behind the existing '
          'seams (git.dart runner / process_utils.dart) so they inherit '
          'fault injection, the barrier scheduler, and telemetry for free.',
    );
  });

  test('L7 (ratchet): raw truncating writes only shrink', () {
    _expectRatchet(
      law: 'L7 raw-write',
      constName: '_rawWriteBaseline',
      baseline: _rawWriteBaseline,
      actual: {
        for (final f in corpus.files)
          if (f.facts.rawWrites > 0 && f.path != 'lib/backend/atomic_write.dart')
            f.path: f.facts.rawWrites,
      },
      onNewSite: 'A truncating writeAsString/writeAsBytes on durable state is '
          'the torn-snapshot bug class (B20). Use writeFileAtomic / '
          'writeFileAtomicString (backend/atomic_write.dart) unless the file '
          'is genuinely disposable.',
    );
  });

  test('L8 (ratchet): engine code stays wall-clock free', () {
    const enginePrefixes = [
      'logos_', 'spectral_', 'engram_', 'gyat', 'lrg_', 'resonance_',
    ];
    bool isEngine(String path) {
      if (!path.startsWith('lib/backend/')) return false;
      final base = path.substring(path.lastIndexOf('/') + 1);
      return enginePrefixes.any(base.startsWith);
    }

    _expectRatchet(
      law: 'L8 engine-wallclock',
      constName: '_engineWallClockBaseline',
      baseline: _engineWallClockBaseline,
      actual: {
        for (final f in corpus.files)
          if (isEngine(f.path) && f.facts.wallClock > 0)
            f.path: f.facts.wallClock,
      },
      onNewSite: 'DateTime.now()/unseeded Random() inside the deterministic '
          'engine breaks replayability and the differential oracles — inject '
          'a clock/seed from the caller instead (timestamps at store/telemetry '
          'seams are fine; they live outside these files).',
    );
  });

  test('L9 (ratchet): refs/manifold blast radius stays enumerable', () {
    // `refs/manifold` NOT followed by `-`: tracks the live metadata
    // namespace only, excluding the sibling namespaces that merely share
    // the prefix (refs/manifold-remote/ = staging, law L11;
    // refs/manifold-surgery-backup/ = history-surgery backups).
    final live = RegExp('refs/manifold(?!-)');
    final actual = <String>{
      for (final f in corpus.files)
        if (f.facts.stringLiterals.any(live.hasMatch)) f.path,
    };
    final added = actual.difference(_manifoldRefFiles).toList()..sort();
    final removed = _manifoldRefFiles.difference(actual).toList()..sort();
    if (added.isEmpty && removed.isEmpty) return;
    fail([
      'LAW L9: the set of files touching the refs/manifold namespace changed.',
      if (added.isNotEmpty)
        'NEW files: $added — the staging-namespace laws apply (never fetch '
            'remote refs onto refs/manifold/*; sync via the staging namespace). '
            'If this is deliberate, add the file to _manifoldRefFiles.',
      if (removed.isNotEmpty)
        'No longer touching it (ratchet down — remove from set): $removed',
      '',
      'Updated literal:',
      _setLiteral('_manifoldRefFiles', actual),
    ].join('\n'));
  });

  test('L10 (meta): every persisting backend file is torn-write covered', () {
    // Coverage-of-kind: the torn-write corpus must grow with the store
    // surface. Any lib/backend file that persists (raw write, openWrite sink,
    // or writeFileAtomic) is either imported by the torn-write suite or
    // carries an explicit exemption with a reason.
    final tornTest = LawCorpus.parseOne(
      File('test/fuzz/torn_write_crash_consistency_test.dart'),
    );
    final covered = <String>{
      for (final imp in tornTest.facts.imports)
        if (imp.startsWith('package:git_desktop/'))
          imp.replaceFirst('package:git_desktop/', 'lib/'),
    };
    final offenders = <String>[];
    for (final f in corpus.files) {
      if (!f.path.startsWith('lib/backend/')) continue;
      final persists = f.facts.rawWrites > 0 ||
          f.facts.openWrites > 0 ||
          f.facts.callsWriteFileAtomic;
      if (!persists) continue;
      if (f.path == 'lib/backend/atomic_write.dart') continue; // the seam
      if (covered.contains(f.path)) continue;
      if (_tornWriteExemptions.containsKey(f.path)) continue;
      offenders.add(f.path);
    }
    offenders.sort();
    expect(offenders, isEmpty,
        reason: 'These lib/backend files persist state but are neither '
            'imported by torn_write_crash_consistency_test.dart nor exempted '
            'with a reason in _tornWriteExemptions:\n${offenders.join('\n')}\n'
            'A new store joins the crash corpus, or documents why not.');
  });
}

// ── plumbing ───────────────────────────────────────────────────────────────

void _expectRatchet({
  required String law,
  required String constName,
  required Map<String, int> baseline,
  required Map<String, int> actual,
  required String onNewSite,
}) {
  final newSites = <String>[];
  final progress = <String>[];
  for (final e in actual.entries) {
    final base = baseline[e.key] ?? 0;
    if (e.value > base) newSites.add('${e.key}: $base -> ${e.value}');
    if (e.value < base) progress.add('${e.key}: $base -> ${e.value}');
  }
  for (final e in baseline.entries) {
    if (!actual.containsKey(e.key)) progress.add('${e.key}: ${e.value} -> 0');
  }
  if (newSites.isEmpty && progress.isEmpty) return;
  fail([
    'LAW $law ratchet drift.',
    if (newSites.isNotEmpty) ...[
      '',
      'NEW sites (count rose above baseline):',
      ...newSites.map((s) => '  $s'),
      onNewSite,
      'If a new site is genuinely correct, paste the updated baseline below.',
    ],
    if (progress.isNotEmpty) ...[
      '',
      'Progress (ratchet DOWN — paste the updated baseline so it sticks):',
      ...progress.map((s) => '  $s'),
    ],
    '',
    'Updated literal for $constName:',
    _mapLiteral(constName, actual),
  ].join('\n'));
}

String _mapLiteral(String name, Map<String, int> m) {
  final keys = m.keys.toList()..sort();
  final b = StringBuffer('const $name = <String, int>{\n');
  for (final k in keys) {
    b.writeln("  '$k': ${m[k]},");
  }
  b.write('};');
  return b.toString();
}

String _setLiteral(String name, Set<String> s) {
  final keys = s.toList()..sort();
  final b = StringBuffer('const $name = <String>{\n');
  for (final k in keys) {
    b.writeln("  '$k',");
  }
  b.write('};');
  return b.toString();
}
