// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

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
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/law_corpus.dart';

// ── Ratchet baselines ──────────────────────────────────────────────────────
// Regenerate any of these by running the suite: the failure message prints
// the exact literal to paste.

/// Git calls that materialize unbounded output (diff/show/blame with no
/// bounding flag) as a String, per file — the ingestion vector
/// [_contentReadBaseline] cannot see (no file is read; the patch arrives on
/// stdout). Like L6's spawn ratchet this enumerates the SURFACE: it cannot
/// prove a site is admission-gated, it forces a new one to be argued for.
///
/// KNOWN REACH, so nobody over-trusts this: argv is read through file-local
/// const spreads (`[..._kDiffCmd, hash]`) — its first version missed those
/// and undercounted git.dart 7→1. Argv it still cannot resolve (a variable, a
/// computed list, a const imported from another file) is invisible, and only
/// String-capturing runners count: the spool transports stream via
/// `Process.start` and are correctly absent.
///
/// Status of the recorded sites, so the argument starts from fact:
///   • branches_page (2) — the branch-name dream; GATED via admitGitDiffText
///     (the calls still name `diff`, so they still count here).
///   • changes_page — absent: its dream + correlatedness probes are gated,
///     and its multi-diff transport spools above 64MB.
///   • ai.dart (4) — commit-message / review context gather. GATED via
///     admitGitDiffText; sized from the porcelain status, NOT the caller's
///     scope list (an empty scope means "whole tree", which would have
///     declared zero bytes for the largest possible diff).
///   • diff_logos_facade (1) — `show rev:path` per visible file in a
///     historical diff, fired by background analysis. GATED via
///     admitFileText at the blob's MEASURED size (`cat-file -s`).
///   • ipc/pipe_commands (4) — the CLI/git-hook bridge's diff probes
///     (`diff`/`dream`). GATED via admitGitDiffText, scoped to the repo's
///     dirty set from `getRepositoryStatus` (the count doesn't move: this
///     law reads argv literals, not the wrapper around them).
///   • workspace_shell (2) — plumbing/legacy.
///   • git.dart (7) — the String-returning transport helpers
///     (getFileDiff/getFileDiffAtRevision/getSelectionDiff/getRangeDiff/
///     getDeskDumpDiff/stashShow/_selectionDiffBase). This is the raw API,
///     not a policy layer: its CALLERS gate (changes_page spools above 64MB;
///     the AI/dream paths admit). A new caller of these owes the same.
const _unboundedGitBaseline = <String, int>{
  'lib/app/workspace_shell.dart': 2,
  'lib/backend/ai.dart': 4,
  'lib/backend/diff_logos_facade.dart': 1,
  'lib/backend/git.dart': 7,
  'lib/backend/ipc/pipe_commands.dart': 4,
  'lib/features/branches/branches_page.dart': 2,
};

/// Whole-content read sites (readAsString/readAsBytes, sync variants) per
/// file — the unbudgeted-ingestion surface (the marble repo-switch system
/// OOM's bug class). Sites here predate the ratchet; each NEW site must be
/// admission-routed, worker-isolated, or bounded before joining. Config /
/// telemetry stores read app-owned small files and are inherently bounded;
/// the repo-content readers are the ones the admission contract governs.
const _contentReadBaseline = <String, int>{
  'lib/backend/ai.dart': 12,
  'lib/backend/ai_api_keys_store.dart': 1,
  'lib/backend/ai_audit_store.dart': 1,
  'lib/backend/ai_settings_store.dart': 5,
  'lib/backend/blob_loader.dart': 1,
  'lib/backend/command_telemetry_store.dart': 1,
  'lib/backend/diff_logos_facade.dart': 1,
  'lib/backend/engram_file_index_cache.dart': 1,
  'lib/backend/file_coupling.dart': 1,
  'lib/backend/git.dart': 5,
  'lib/backend/ipc/pipe_commands.dart': 3,
  'lib/backend/ipc/pipe_server.dart': 1,
  'lib/backend/local_telemetry_store.dart': 1,
  'lib/backend/logos_flow.dart': 1,
  'lib/backend/logos_git_calibration.dart': 1,
  'lib/backend/repo_blob_walk.dart': 2,
  'lib/backend/review_ratchet_store.dart': 1,
  'lib/backend/settings_store.dart': 1,
  'lib/backend/shadow_coupling_cache.dart': 1,
  'lib/backend/spectral_persistence.dart': 2,
  'lib/features/branches/branches_page.dart': 3,
  'lib/features/changes/changes_page.dart': 3,
  'lib/features/changes/conflict_resolution.dart': 1,
  'lib/features/changes/merge_conflict_flow.dart': 4,
  'lib/features/palette/palette_state.dart': 1,
};

/// Process.run/start/runSync call sites per file. New spawn sites belong
/// behind the existing seams (backend/git.dart's runner, process_utils) so
/// they inherit fault injection, chaos scheduling, and telemetry for free.
const _processSpawnBaseline = <String, int>{
  'lib/app/desk_issue_state.dart': 1,
  // desk_pr_state.dart ratcheted 1 -> 0 (2026-07-27): _mainRepoOf's raw
  // `git rev-parse --git-common-dir` moved behind git.dart's runner. It
  // runs on every refresh AND every desk-PR write, so it belongs inside
  // the subprocess budget and the read-coalescing rather than beside it.
  'lib/backend/ai.dart': 4,
  'lib/backend/ai_api_keys_store.dart': 2,
  'lib/backend/aperture_sweep.dart': 4,
  // desk_pr_diff.dart ratcheted 3 -> 0 (2026-07-13): its raw Process.run
  // sites moved behind git.dart's gated runner, gaining the diff-family
  // config pins, index.lock retry, and the per-repo index-write lock.
  // gh.dart 4 -> 5 (2026-07-14): spoolForgeCliStdout adds a Process.start
  // that STREAMS `gh pr diff`/`glab mr diff` stdout to a disk spool — the
  // machine-scale transport fix. It cannot ride git.dart's runner (that seam
  // is for git argv/pins/index-lock semantics); runForgeCli IS the forge
  // seam, and the streaming variant lives beside it in the same file.
  'lib/backend/gh.dart': 5,
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
  'lib/backend/gh.dart':
      'spoolForgeCliStdout streams CLI stdout into a fresh systemTemp spool '
      '— a disposable transport cache, never state anything loads back. A '
      'torn stream is discarded by the nonzero-exit/error cleanup, and a '
      'crash mid-write leaves only an orphaned temp file',
  'lib/backend/gitea_api.dart':
      '_getRawToSpool streams an HTTP `.diff` response into a fresh '
      'systemTemp spool — same disposable-transport-cache shape as '
      'gh.dart\'s spoolForgeCliStdout, with non-200/exception cleanup',
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
        if (f.syntaxErrors.isNotEmpty)
          '${f.path}\n  ${f.syntaxErrors.join('\n  ')}',
    ];
    expect(
      broken,
      isEmpty,
      reason:
          'Files the law corpus could not parse — every other law '
          'silently undercounts on these:\n${broken.join('\n')}',
    );
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
    expect(
      offenders,
      isEmpty,
      reason:
          'dart:ffi is the one memory-unsafe edge in the app; it stays '
          'behind audited files. New FFI goes in (or behind) one of '
          '$auditedFfiFiles, or a new file added here deliberately. '
          'Offenders: $offenders',
    );
  });

  test('L2: no dev-only packages imported from lib/', () {
    const devOnly = ['package:analyzer/', 'package:flutter_test/'];
    final offenders = [
      for (final f in corpus.files)
        for (final imp in f.facts.imports)
          if (devOnly.any(imp.startsWith)) '${f.path} imports $imp',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'dev_dependencies must not leak into the shipped app:\n'
          '${offenders.join('\n')}',
    );
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
    expect(
      offenders,
      isEmpty,
      reason:
          'Raw control bytes in source (write them escaped instead):\n'
          '${offenders.join('\n')}',
    );
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
    expect(
      offenders,
      isEmpty,
      reason:
          'Only git.dart may use %09 (and only in for-each-ref '
          'formats — see the listReflog comment). Offenders: $offenders',
    );
  });

  test('L5: codex --sandbox is always pinned to read-only', () {
    // The codex sandbox incident: codex exec must pin --sandbox read-only on
    // EVERY call. Structurally: every \'--sandbox\' list element is
    // immediately followed by \'read-only\', and ai.dart has at least one.
    final ai = byPath['lib/backend/ai.dart'];
    expect(ai, isNotNull, reason: 'lib/backend/ai.dart moved — update law L5');
    expect(
      ai!.facts.sandboxFlags,
      greaterThanOrEqualTo(1),
      reason:
          'The codex exec argv no longer pins --sandbox at all — this '
          'is the exact incident regression. Restore the '
          "'--sandbox', 'read-only' pair (NEVER remove it).",
    );
    final offenders = [
      for (final f in corpus.files)
        if (f.facts.sandboxAdjacencyViolations > 0)
          '${f.path}: ${f.facts.sandboxAdjacencyViolations}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          "Every '--sandbox' argv element must be immediately followed "
          "by 'read-only': $offenders",
    );
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
            f.facts.stringLiterals.any(
              (s) => s.contains('refs/manifold-remote'),
            ))
          f.path,
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Staging refs are built via MetadataRemote, never spelled: '
          '$offenders',
    );
  });

  test('L15: spool-document ownership is always named', () {
    // DiffDocument.lazyFromSpool is the raw-path engine entry whose optional
    // ownedTempDir made split spool/doc lifecycles expressible — the temp-dir
    // leak / premature-delete bug class. Feature code must name the mode
    // instead: adoptSpool (doc is sole owner, deletes on dispose AND on a
    // failed build) or viewSpool (caller-owned spool with other readers).
    // Only diff_document.dart itself — where the wrappers delegate — may
    // invoke the raw entry inside lib/. Tests keep direct engine access.
    final offenders = [
      for (final f in corpus.files)
        if (f.path != 'lib/features/diff/diff_document.dart' &&
            f.facts.lazyFromSpoolCalls > 0)
          '${f.path}: ${f.facts.lazyFromSpoolCalls}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Build spool docs via DiffDocument.adoptSpool or '
          'DiffDocument.viewSpool — never the raw lazyFromSpool entry: '
          '$offenders',
    );
  });

  test('L16: async review-cache installs are epoch-guarded', () {
    // The review caches are keyed by deskId, and deskIds are small
    // PER-REPO sequential counters — repo A's desk 1 and repo B's desk 1
    // are different reviews under the same key. So a load that resolves
    // AFTER a repo switch must not install: it would render one repo's
    // review conversation inside another's pane. `mounted` cannot catch
    // it (same widget, still mounted), so currency is explicit:
    // `_reviewCurrent(epoch)`, bumped wherever the caches are dropped.
    //
    // Found by the manifold review, and this is what keeps it found: a
    // NEW async path that installs into one of these maps without the
    // guard fails here rather than shipping a cross-repo leak.
    //
    // Scope note, so nobody over-trusts it: it flags INSTALLS (an
    // assignment landing data) that sit textually after the method's
    // first `await`. Clears and removes are excluded — dropping data
    // from a cache the wrong repo already emptied is harmless — and a
    // write hidden behind a helper call is invisible to it.
    const caches = {
      '_reviewData',
      '_reviewLensDiffs',
      '_reviewRowSummaries',
      '_reviewComposeAt',
    };
    final file = corpus.files.firstWhere(
      (f) => f.path == 'lib/features/branches/branches_page.dart',
    );
    final offenders = <String>[];
    for (final decl in file.unit.declarations.whereType<ClassDeclaration>()) {
      // Same accessor L13 keeps: analyzer 10 deprecates .members toward a
      // ClassBody API that does not expose the member list yet.
      // ignore: deprecated_member_use
      for (final m in decl.members.whereType<MethodDeclaration>()) {
        final body = m.body;
        if (body is! BlockFunctionBody) continue;
        final awaits = _AwaitOffsets()..visitBlock(body.block);
        if (awaits.first == null) continue;
        final installs = _CacheInstalls(caches)..visitBlock(body.block);
        final late = installs.offsets.where((o) => o > awaits.first!);
        if (late.isEmpty) continue;
        final src = body.toSource();
        if (src.contains('_reviewCurrent(')) continue;
        offenders.add('${m.name.lexeme} (${late.length} install(s))');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Capture `final epoch = _reviewEpoch;` before the await and '
          'return unless `_reviewCurrent(epoch)` — otherwise a stale '
          "repo's review lands in the open repo's pane: $offenders",
    );
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
    expect(
      offenders,
      isEmpty,
      reason:
          'Use Oid.zero (manifold_ref_types.dart), never a literal: '
          '$offenders',
    );
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
          final annotated = member.metadata.any(
            (a) => a.name.name == 'useResult',
          );
          if (!annotated) offenders.add('$path: $name');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Public GitResult APIs missing @useResult:\n'
          '${offenders.join('\n')}',
    );
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
    expect(
      offenders,
      isEmpty,
      reason:
          'LruCache of a native-resource disposable must pass '
          'onEvict: (v) => v.dispose():\n${offenders.join('\n')}',
    );
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
      onNewSite:
          'New Process.run/start sites belong behind the existing '
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
          if (f.facts.rawWrites > 0 &&
              f.path != 'lib/backend/atomic_write.dart')
            f.path: f.facts.rawWrites,
      },
      onNewSite:
          'A truncating writeAsString/writeAsBytes on durable state is '
          'the torn-snapshot bug class (B20). Use writeFileAtomic / '
          'writeFileAtomicString (backend/atomic_write.dart) unless the file '
          'is genuinely disposable.',
    );
  });

  test('L8 (ratchet): engine code stays wall-clock free', () {
    const enginePrefixes = [
      'logos_',
      'spectral_',
      'engram_',
      'gyat',
      'lrg_',
      'resonance_',
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
      onNewSite:
          'DateTime.now()/unseeded Random() inside the deterministic '
          'engine breaks replayability and the differential oracles — inject '
          'a clock/seed from the caller instead (timestamps at store/telemetry '
          'seams are fine; they live outside these files).',
    );
  });

  test('L12 (ratchet): whole-content file reads only shrink', () {
    // The unbudgeted-ingestion surface (the marble repo-switch system OOM):
    // every readAsString/readAsBytes over repo content is a site that can be
    // handed a multi-hundred-MB working-tree file. Each existing site either
    // carries a bound, runs inside a worker isolate, or routes through
    // AnalysisAdmission — a NEW site must too, and this ratchet is what asks.
    _expectRatchet(
      law: 'L12 content-read',
      constName: '_contentReadBaseline',
      baseline: _contentReadBaseline,
      actual: {
        for (final f in corpus.files)
          if (f.facts.contentReads > 0) f.path: f.facts.contentReads,
      },
      onNewSite:
          'A whole-content read over repo/working-tree files is the '
          'repo-switch OOM bug class. Route it through '
          'AnalysisAdmission.instance.run with a stat-declared size and a '
          'declined-path degradation (backend/analysis_admission.dart), read '
          'inside the worker isolate, or bound the read — then update the '
          'baseline.',
    );
  });

  test('L13 (ratchet): unbounded git-stdout reads only shrink', () {
    // The ingestion vector L12 cannot see: no file is read, yet
    // `runGit(repo, ['diff', ...])` returns a whole working tree's patch as
    // a String. Hand-gating call sites is what let this class survive — the
    // commit-composer dream was gated while its unscoped twin in the branch
    // composer was not, and stayed a live OOM path. New sites belong behind
    // `admitGitDiffText` (backend/admitted_git.dart) or a spool transport.
    _expectRatchet(
      law: 'L13 unbounded-git',
      constName: '_unboundedGitBaseline',
      baseline: _unboundedGitBaseline,
      actual: {
        for (final f in corpus.files)
          if (f.facts.unboundedGitReads > 0) f.path: f.facts.unboundedGitReads,
      },
      onNewSite:
          'A git diff/show/blame whose output scales with repo CONTENT must '
          'not become a String unbudgeted. Route it through '
          'admitGitDiffText (backend/admitted_git.dart) with the paths being '
          'diffed and a declined-path degradation, or stream it to a spool '
          '(spoolSelectionDiff / spoolCommitDiff / spoolForgeCliStdout). '
          'Bounded summaries (--name-only/--numstat/--stat) are free.',
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
    fail(
      [
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
      ].join('\n'),
    );
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
      final persists =
          f.facts.rawWrites > 0 ||
          f.facts.openWrites > 0 ||
          f.facts.callsWriteFileAtomic;
      if (!persists) continue;
      if (f.path == 'lib/backend/atomic_write.dart') continue; // the seam
      if (covered.contains(f.path)) continue;
      if (_tornWriteExemptions.containsKey(f.path)) continue;
      offenders.add(f.path);
    }
    offenders.sort();
    expect(
      offenders,
      isEmpty,
      reason:
          'These lib/backend files persist state but are neither '
          'imported by torn_write_crash_consistency_test.dart nor exempted '
          'with a reason in _tornWriteExemptions:\n${offenders.join('\n')}\n'
          'A new store joins the crash corpus, or documents why not.',
    );
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
  fail(
    [
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
    ].join('\n'),
  );
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

/// Offset of the first `await` in a body — the line past which a result
/// belongs to a different moment than the call that started it.
class _AwaitOffsets extends RecursiveAstVisitor<void> {
  int? first;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    final o = node.offset;
    if (first == null || o < first!) first = o;
    super.visitAwaitExpression(node);
  }
}

/// Assignments that INSTALL into one of the named caches — `m[k] = v` or
/// `m = v`. Reads, clears and removes are deliberately not installs.
class _CacheInstalls extends RecursiveAstVisitor<void> {
  _CacheInstalls(this.names);

  final Set<String> names;
  final List<int> offsets = [];

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    final lhs = node.leftHandSide;
    String? target;
    if (lhs is IndexExpression) {
      final t = lhs.target;
      if (t is SimpleIdentifier) target = t.name;
    } else if (lhs is SimpleIdentifier) {
      target = lhs.name;
    }
    if (target != null && names.contains(target)) offsets.add(node.offset);
    super.visitAssignmentExpression(node);
  }
}
