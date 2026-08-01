// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:async';
import 'dart:io' show File, Process, pid;
import 'dart:isolate';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

import '../admitted_git.dart';
import '../ai.dart';
import '../analysis_admission.dart';
import '../dead_code_strainer.dart';
import '../dtos.dart';
import '../file_coupling.dart';
import '../git.dart';
import '../logos_dream.dart';
import '../logos_git.dart';
import '../logos_git_probe.dart';
import '../review_target.dart';
import '../shake_ledger.dart';
import '../shake_plan.dart';
import 'bridge_context.dart';

typedef CommandHandler = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
);

final Map<String, CommandHandler> commands = {
  'help': _help,
  'ping': _ping,
  'status': _status,
  'repos': _repos,
  'diff': _diff,
  'blast-radius': _blastRadius,
  'context': _contextCmd,
  'coherence': _coherence,
  'suggest': _suggest,
  'profile': _profile,
  'explain': _explain,
  'test-map': _testMap,
  'architecture': _architecture,
  'who-knows': _whoKnows,
  'recent': _recent,
  'search': _search,
  'dream': _dream,
  'impact': _impact,
  'review': _review,
  'review-evidence': _reviewEvidence,
  'muse': _muse,
  'deadcode': _deadCode,
  'index': _index,
  'shake': _shake,
  'state': _state,
  'commit-message': _commitMessage,
};

// ── What the app is configured to do ─────────────────────────────

/// The settings an agent needs in order to know what it is about to get.
///
/// Every AI command answers with this alongside its result, and `state`
/// returns it alone. That is the point: an agent driving Manifold should not
/// have to infer which model ran, which strands the muse was carrying, or
/// whether double-check was on — it should be told, in the same breath as the
/// answer those settings produced.
///
/// Reports what is CONFIGURED, and never forces provider discovery to find
/// out. `modelSelections` already holds the user's chosen model per category,
/// so the question "what will run" is answered from local state; a `state`
/// call that spun up a network probe would be a poor thing to put in front of
/// every other command.
Map<String, dynamic> settingsSnapshot(ManifoldBridgeContext ctx) {
  final ai = ctx.aiSettingsState;
  final prefs = ctx.preferencesState;

  Map<String, dynamic> slot(String categoryId) {
    final model = ai.modelSelections[categoryId] ?? '';
    final effort = ai.resolveEffort(categoryId, model);
    return {
      'category': categoryId,
      'categoryLabel': ai.labelForCategory(categoryId, categoryId),
      'model': model,
      if (effort.effort != null) 'effort': effort.effort,
      'fast': effort.fast,
    };
  }

  return {
    'ai': {
      // False means no provider discovery has run yet in this session, NOT
      // that AI is unavailable — the first command that needs it will warm it.
      'categoriesLoaded': ai.runtimeModelCategories.isNotEmpty,
      'readOnly': prefs.aiReadOnlyDefault,
      'guardrailStage': prefs.guardrailStage,
      'hidden': prefs.hideAiFeatures,
    },
    'commitMessage': {
      ...slot(ai.commitMessageModelCategoryId),
      'customPrompt': ai.commitMessagePrompt.trim().isNotEmpty,
      if (ai.commitMessagePromptPath.isNotEmpty)
        'promptPath': ai.commitMessagePromptPath,
      'structure': prefs.commitStructure.name,
      'voice': prefs.commitVoice.name,
      'coverage': prefs.commitCoverage.name,
    },
    'review': {
      ...slot(ai.reviewCommitModelCategoryId),
      'doubleCheck': ai.reviewCommitDoubleCheckEnabled,
      'customPrompt': ai.reviewCommitPrompt.trim().isNotEmpty,
      if (ai.reviewCommitPromptPath.isNotEmpty)
        'promptPath': ai.reviewCommitPromptPath,
    },
    // The sweep is a review of settled code, so it runs on the review slot.
    // Said explicitly rather than left to be inferred.
    'shake': {
      ...slot(ai.reviewCommitModelCategoryId),
      'sharesReviewSettings': true,
    },
    'muse': {
      'brainstorm': slot(ai.museBrainstormModelCategoryId),
      'synthesis': slot(ai.museSynthesisModelCategoryId),
      'strands': [
        for (final e in ai.museQuiver)
          {'kind': museStrandLabel(e.kind), 'count': e.count},
      ],
      'strandOrder': [
        for (final k in ai.museStrandOrder) museStrandLabel(k),
      ],
      'customPrompt': ai.musePrompt.trim().isNotEmpty,
      if (ai.musePromptPath.isNotEmpty) 'promptPath': ai.musePromptPath,
    },
  };
}

/// Every strand the muse knows, for a caller that wants to choose.
List<String> get allStrandNames =>
    [for (final k in kMuseStrandDisplayOrder) museStrandLabel(k)];

/// Parse `--strands spark,fever` into a quiver.
///
/// Returns null when the flag was absent, which is the signal to use the
/// user's configured quiver. THROWS on an unrecognised name rather than
/// dropping it: a caller who asks for a strand that does not exist has a typo
/// or a stale idea of the vocabulary, and silently running a smaller muse
/// would look exactly like success.
List<MuseQuiverEntry>? parseStrandOverride(Object? raw) {
  if (raw == null) return null;
  final text = raw is String ? raw : '$raw';
  if (text.trim().isEmpty) return null;

  final entries = <MuseQuiverEntry>[];
  final seen = <MuseStrandKind>{};
  for (final piece in text.split(',')) {
    final token = piece.trim();
    if (token.isEmpty) continue;
    // `spark:3` asks for three of that strand; a bare name means one.
    final colon = token.indexOf(':');
    final name = colon < 0 ? token : token.substring(0, colon);
    final countText = colon < 0 ? '' : token.substring(colon + 1);
    final kind = parseMuseStrand(name);
    if (kind == null) {
      throw ArgumentError(
        'Unknown muse strand "$name". Known strands: '
        '${allStrandNames.join(', ')}.',
      );
    }
    final count = int.tryParse(countText) ?? 1;
    if (count < 1) {
      throw ArgumentError('Strand "$name" needs a count of at least 1.');
    }
    if (!seen.add(kind)) {
      throw ArgumentError('Strand "$name" was named twice.');
    }
    entries.add(MuseQuiverEntry(kind: kind, count: count));
  }
  if (entries.isEmpty) return null;
  return entries;
}

Future<Map<String, dynamic>> _state(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  return {
    ...settingsSnapshot(ctx),
    'strandVocabulary': allStrandNames,
    'activeRepo': ctx.repoState.activePath,
  };
}

// ── Helpers ──────────────────────────────────────────────────────

String _requireRepo(Map<String, dynamic> params, ManifoldBridgeContext ctx) {
  final explicit = params['repo'] as String?;
  if (explicit != null && explicit.isNotEmpty) return explicit;
  final active = ctx.repoState.activePath;
  if (active == null) {
    throw StateError('No active repository. Pass --repo <path>.');
  }
  return active;
}

final Map<String, String> _commonRootCache = {};

Future<String> _resolveCommonRoot(String repo) async {
  final cached = _commonRootCache[repo];
  if (cached != null) return cached;
  try {
    final result = await Process.run(
      'git',
      ['rev-parse', '--path-format=absolute', '--git-common-dir'],
      workingDirectory: repo,
    );
    if (result.exitCode == 0) {
      final gitCommonDir = (result.stdout as String).trim();
      if (gitCommonDir.isNotEmpty) {
        final root = p.dirname(gitCommonDir);
        if (root.isNotEmpty) {
          _commonRootCache[repo] = root;
          return root;
        }
      }
    }
  } catch (_) {}
  _commonRootCache[repo] = repo;
  return repo;
}

Future<LogosGit> _awaitEngine(String repo, ManifoldBridgeContext ctx) async {
  final root = await _resolveCommonRoot(repo);
  // Freshness-aware on EVERY call: routes through the state's
  // loadForRepo, whose resolver probes HEAD (one TTL-deduped rev-parse)
  // and rebuilds only when history moved — exactly what the UI's manual
  // refresh does, now automatic per CLI call. The old probe-then-return
  // pinned every later call to whatever engine the FIRST call warmed,
  // which is why subsequent review/muse runs saw stale context.
  final engine = await ctx.logosGitState
      .freshEngineFor(root, timeout: const Duration(seconds: 15));
  if (engine != null) return engine;
  final err = ctx.logosGitState.errorFor(root);
  throw StateError(err == null
      ? 'Logos engine did not load within 15s for $repo.'
      : 'Logos engine failed for $repo: $err');
}

final RegExp _pubspecName =
    RegExp(r'''^name:\s*['"]?([A-Za-z_][A-Za-z0-9_]*)''', multiLine: true);

/// Reachability-based dead-code map for a repo: files no live surface imports.
/// Reads tracked Dart sources, derives each Dart package's name from its
/// pubspec, and runs [DeadCodeStrainer] per package (a file is assigned to the
/// package with the longest matching directory prefix, so nested packages don't
/// bleed together). Engine-independent — pure import-closure over the tree.
Future<Map<String, dynamic>> _deadCode(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final ls = await runGit(repo, ['ls-files']);
  if (ls.exitCode != 0) {
    // Throw, don't return {'error': …}: the server only lifts a *thrown* error
    // to the JSON-RPC top level the CLI checks; a returned error map hides under
    // `result` and would render as a cheerful "nothing dead".
    throw StateError('git ls-files failed: ${(ls.stderr as String).trim()}');
  }
  final tracked = (ls.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  // package dir -> name, from each pubspec.yaml.
  final packageDirs = <String, String>{};
  for (final f in tracked.where((f) => f.endsWith('pubspec.yaml'))) {
    try {
      final text = await File(p.join(repo, f)).readAsString();
      final m = _pubspecName.firstMatch(text);
      if (m != null) {
        final dir = f.contains('/') ? f.substring(0, f.lastIndexOf('/')) : '';
        packageDirs[dir] = m.group(1)!;
      }
    } catch (_) {}
  }
  if (packageDirs.isEmpty) {
    return {
      'repo': repo,
      'note': 'no Dart packages (pubspec.yaml) found',
      'fullyDead': const <Map<String, dynamic>>[],
      'testZombies': const <Map<String, dynamic>>[],
    };
  }

  // Assign each Dart file to the package with the longest matching prefix.
  final byPackage = <String, List<DeadCodeInput>>{};
  for (final f in tracked.where((f) => f.endsWith('.dart'))) {
    String? bestDir;
    var bestLen = -1;
    for (final dir in packageDirs.keys) {
      final prefix = dir.isEmpty ? '' : '$dir/';
      if (f.startsWith(prefix) && prefix.length > bestLen) {
        bestDir = dir;
        bestLen = prefix.length;
      }
    }
    if (bestDir == null) continue;
    String content;
    try {
      content = await File(p.join(repo, f)).readAsString();
    } catch (_) {
      continue;
    }
    (byPackage[bestDir] ??= <DeadCodeInput>[]).add(DeadCodeInput(f, content));
  }

  final fullyDead = <Map<String, dynamic>>[];
  final zombies = <Map<String, dynamic>>[];
  final joints = <Map<String, dynamic>>[];
  final packages = <Map<String, dynamic>>[];
  for (final entry in byPackage.entries) {
    final name = packageDirs[entry.key]!;
    final inputs = entry.value;
    // Off-load the CPU pass (graph build + reachability + dominator tree) to a
    // worker isolate: this handler runs on the GUI isolate that serves IPC, and
    // the codebase has frozen before on synchronous work there.
    final report = await Isolate.run(
        () => DeadCodeStrainer(packageName: name).analyze(inputs));
    fullyDead.addAll(report.fullyDead.map((r) => r.toJson()));
    zombies.addAll(report.testZombies.map((r) => r.toJson()));
    joints.addAll(report.joints.map((r) => r.toJson()));
    packages.add({
      'package': name,
      'dir': entry.key,
      'libFiles': report.totalLibFiles,
      'alive': report.aliveLibFiles,
      'dead': report.deadCount,
      'joints': report.joints.length,
      'hasAppEntry': report.hasAppEntry,
    });
  }
  fullyDead.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
  zombies.sort((a, b) => (a['path'] as String).compareTo(b['path'] as String));
  joints.sort((a, b) => (b['load'] as int).compareTo(a['load'] as int));
  return {
    'repo': repo,
    'packages': packages,
    'fullyDead': fullyDead,
    'testZombies': zombies,
    'joints': joints,
  };
}

/// Validate a repository, report what Manifold can see in it, and (unless
/// `--check`) register it so it shows up as a project.
///
/// One command for adding, checking and validating, because they are the same
/// question asked with different intentions: "can Manifold work with this, and
/// what does it know about it?". Registering is the only side effect, and it
/// is the one the flag turns off.
///
/// Nothing here requires the repo to have been added first — the engine
/// resolver is keyed by path, not by membership in the project list. That is
/// what makes every other command usable ephemerally, and this one is how you
/// check that before spending an AI call.
Future<Map<String, dynamic>> _index(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final checkOnly = params['check'] == 'true' || params['check'] == true;

  final opened = await openRepository(repo);
  if (!opened.ok) {
    throw StateError('$repo is not a usable git repository: '
        '${opened.error ?? 'unknown error'}');
  }
  // Normalized once, here, and used for everything after: `_resolveCommonRoot`
  // derives its answer from git's output, which on Windows comes back with
  // forward slashes while the rest of the app stores native separators.
  final root = p.normalize(await _resolveCommonRoot(repo));

  _progress('probe');
  Future<String> probe(List<String> args) async {
    final r = await runGit(root, args);
    return r.exitCode == 0 ? (r.stdout as String).trim() : '';
  }

  final branch = await probe(['rev-parse', '--abbrev-ref', 'HEAD']);
  final head = await probe(['rev-parse', 'HEAD']);
  final shallow = (await probe(['rev-parse', '--is-shallow-repository'])) == 'true';
  final bare = (await probe(['rev-parse', '--is-bare-repository'])) == 'true';
  final commitCount = int.tryParse(await probe(['rev-list', '--count', 'HEAD'])) ?? 0;
  final trackedRaw = await probe(['ls-files']);
  final trackedFiles =
      trackedRaw.isEmpty ? 0 : trackedRaw.split('\n').where((l) => l.trim().isNotEmpty).length;

  final known = ctx.repoState.knowsRecent(root);
  var registered = known;
  if (!checkOnly && !known) {
    registered = await ctx.repoState.rememberRecent(root);
  }

  // Warm the engine so the FIRST real command is not the one that pays for
  // the cold build. Bounded: an unreachable or enormous repo reports what it
  // managed rather than hanging the CLI.
  _progress('index', 'building engine');
  final engineSw = Stopwatch()..start();
  LogosGit? engine;
  String? engineError;
  try {
    engine = await ctx.logosGitState
        .freshEngineFor(root, timeout: const Duration(seconds: 60));
    if (engine == null) engineError = ctx.logosGitState.errorFor(root);
  } catch (e) {
    engineError = '$e';
  }
  final engineMs = engineSw.elapsedMilliseconds;

  final couplingWarm = await _awaitCoupling(root, ctx);
  final axis = engine?.stats.commitAxis;

  return {
    'repo': root,
    'valid': true,
    'registered': registered,
    'alreadyKnown': known,
    'checkOnly': checkOnly,
    'branch': branch,
    'head': head.isEmpty ? null : head,
    'commits': commitCount,
    'trackedFiles': trackedFiles,
    'bare': bare,
    // Surfaced because it is the one repository property that makes reviewing
    // history impossible: a shallow clone has no parent for its oldest
    // commits, so there is nothing to diff them against.
    'shallow': shallow,
    'engine': {
      'ready': engine != null,
      'ms': engineMs,
      'error': engineError,
      'graphFiles': engine?.nodePaths.length ?? 0,
      'commitsOnAxis': axis?.length ?? 0,
      'reviewableFrom': axis == null || axis.isEmpty ? null : axis.hashes.first,
    },
    'coupling': {
      'ready': couplingWarm.data != null,
      'ms': couplingWarm.ms,
    },
  };
}

/// Audit the repository itself, region by region, resuming where the last run
/// stopped.
///
/// The whole-codebase counterpart to `review`. `review` asks whether a CHANGE
/// is right; this asks what is wrong with the code that is already there —
/// which is a different question, and the only one that can reach code
/// nothing has edited in years.
///
/// A run is bounded (`--regions`, default 1) and the sweep is not: what a run
/// does not reach stays pending in the ledger with its place in the order, so
/// repeated runs converge on having examined everything. `--plan` shows the
/// order and the honest coverage without spending a single model call.
Future<Map<String, dynamic>> _shake(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final root = p.normalize(await _resolveCommonRoot(repo));
  final planOnly = params['plan'] == 'true' || params['plan'] == true;
  final reset = params['reset'] == 'true' || params['reset'] == true;
  final budget = _int(params['regions']) ?? 1;

  if (reset) await ShakeLedgerStore.forget(root);

  _progress('plan', 'reading the tree');
  final ledger = await ShakeLedgerStore.load(root);
  // Best-effort: a cold engine costs the spectral partition and the churn
  // ordering, never the coverage. Directory locality still reaches every
  // file, which is the guarantee that matters.
  final engine = await ctx.logosGitState
      .freshEngineFor(root, timeout: const Duration(seconds: 60));

  final planned = await planShake(
    repositoryPath: root,
    ledger: ledger,
    engine: engine,
  );
  if (!planned.ok) throw StateError(planned.error!);
  final plan = planned.data!;

  Map<String, dynamic> planJson() => {
        'repo': root,
        'complete': plan.isComplete,
        'domainFiles': plan.domainFiles,
        'examinedFiles': plan.freshFiles,
        'pendingFiles': plan.pendingFiles,
        'pendingRegions': plan.pending.length,
        'commonPrefix': plan.commonPrefix,
        'engineReady': engine != null,
        'excluded': {
          for (final e in plan.excluded.entries)
            e.key.name: {
              'count': e.value.length,
              'sample': e.value.take(5).toList(),
            },
        },
        'regions': [
          for (final r in plan.pending.take(40))
            {
              'label': r.label,
              'files': r.files.length,
              'bytes': r.bytes,
              'unexamined': r.unexamined,
              'neverHumanReviewed': r.neverHumanReviewed,
            },
        ],
      };

  if (planOnly) return {...planJson(), 'planOnly': true};
  if (plan.isComplete) {
    return {...planJson(), 'audited': const <Map<String, dynamic>>[]};
  }

  final categories = await _ensureCategories(ctx);
  final ai = ctx.aiSettingsState;
  final prefs = ctx.preferencesState;
  final model = _pickModel(
    categories, ctx,
    preferredCategoryId: ai.reviewCommitModelCategoryId,
    modelOverride: params['model'] as String?,
  );
  final couplingWarm = await _awaitCoupling(root, ctx);
  final stamp = DateTime.now().toUtc().toIso8601String();

  final audited = <Map<String, dynamic>>[];
  for (final region in plan.pending.take(budget)) {
    _progress('shake', region.label);
    final result = await _boundedAi(
      'shake',
      reviewCommit(
        repositoryPath: root,
        modelValue: model.modelValue,
        modelCategoryLabel: model.categoryLabel,
        scopeLabel: region.label,
        reasoningEffort: model.effort,
        fastMode: model.fast,
        supportsReasoning: model.supportsReasoning,
        target: region.toTarget(),
        customPrompt: ai.reviewCommitPrompt,
        guardrailStage: prefs.guardrailStage,
        doubleCheckEnabled: ai.reviewCommitDoubleCheckEnabled,
        readOnly: true,
        couplingMatrix: couplingWarm.data,
      ),
      calls: ai.reviewCommitDoubleCheckEnabled ? 2 : 1,
    );
    if (!result.ok || result.data == null) {
      // A region that could not be audited must NOT be marked examined —
      // that would retire it from the sweep having looked at nothing.
      audited.add({
        'region': region.label,
        'error': result.error ?? 'audit failed',
      });
      continue;
    }
    final d = result.data!;
    for (final f in region.files) {
      ledger.mark(f.path, f.blobOid, stamp, findings: d.findings.length);
    }
    audited.add({
      'region': region.label,
      'files': region.files.length,
      'score': d.score,
      'verdict': d.verdict,
      'summary': d.summary,
      'findings': [
        for (final f in d.findings)
          {
            'title': f.title,
            'severity': f.severity,
            'file': f.filePath,
            'evidence': f.evidence,
            'why': f.whyItMatters,
          },
      ],
      'observations': [
        for (final o in d.observations) {'title': o.title, 'file': o.filePath},
      ],
    });
  }

  // Against the whole live domain, not just what was pending: pruning by
  // the pending set would retire the very files this run just examined.
  ledger.prune(plan.livePaths);
  await ShakeLedgerStore.save(root, ledger);

  // Re-planned AFTER the run so the counts reported are the ones a reader
  // would get by asking again — a report of what is left must not describe
  // the world before the work.
  final after = await planShake(
    repositoryPath: root,
    ledger: ledger,
    engine: engine,
  );
  final remaining = after.ok ? after.data! : plan;

  return {
    'repo': root,
    'complete': remaining.isComplete,
    'domainFiles': remaining.domainFiles,
    'examinedFiles': remaining.freshFiles,
    'pendingFiles': remaining.pendingFiles,
    'pendingRegions': remaining.pending.length,
    'engineReady': engine != null,
    'excluded': {
      for (final e in remaining.excluded.entries)
        e.key.name: {
          'count': e.value.length,
          'sample': e.value.take(5).toList(),
        },
    },
    'audited': audited,
    'settings': settingsSnapshot(ctx),
  };
}

class _WarmResult<T> {
  final T? data;
  final int ms;
  final bool timedOut;
  const _WarmResult(this.data, this.ms, {this.timedOut = false});
}

const Symbol progressKey = #manifoldProgress;

void _progress(String phase, [String detail = '']) {
  final fn = Zone.current[progressKey]
      as void Function(String, String)?;
  fn?.call(phase, detail);
}

Future<_WarmResult<FileCouplingMatrix>> _awaitCoupling(
  String repo,
  ManifoldBridgeContext ctx,
) async {
  final sw = Stopwatch()..start();
  // Freshness-aware, same rationale as [_awaitEngine]: loadForRepo's
  // HEAD check makes this free when history is unmoved and a recompute
  // when it isn't, so every CLI call enriches against current history.
  final m = await ctx.fileCouplingState.freshValueFor(repo);
  return _WarmResult(m, sw.elapsedMilliseconds, timedOut: m == null);
}

Future<FileCouplingMatrix> _coupling(String repo, ManifoldBridgeContext ctx,
    [LogosGit? engine]) async {
  final root = await _resolveCommonRoot(repo);
  final m = await ctx.fileCouplingState.freshValueFor(root) ??
      engine?.stats.coupling ??
      ctx.logosGitState.engineFor(root)?.stats.coupling;
  if (m != null) return m;
  throw StateError('No coupling data for $repo. Loading now, retry shortly.');
}

/// Walks coupling neighbours of [seeds], returning up to [limit] ranked
/// by strongest co-change score. Shared by blast-radius and context.
List<MapEntry<String, double>> _couplingNeighbors(
  List<String> seeds,
  FileCouplingMatrix coupling, {
  int limit = 20,
}) {
  final seedSet = seeds.toSet();
  final scores = <String, double>{};
  for (final seed in seeds) {
    for (final entry in coupling.jaccardEntriesOf(seed)) {
      if (seedSet.contains(entry.key)) continue;
      final prev = scores[entry.key] ?? 0.0;
      if (entry.value > prev) scores[entry.key] = entry.value;
    }
  }
  return (scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .take(limit)
      .toList();
}

List<String> _resolveFiles(Map<String, dynamic> params) {
  for (final key in const [
    'files', 'file', 'paths', 'path', 'seeds', 'changed',
  ]) {
    final raw = params[key];
    if (raw == null) continue;
    if (raw is List) {
      return [for (final item in raw) '$item'.trim()]
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.isNotEmpty) {
      return raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
  }
  throw ArgumentError('Missing file paths. Pass --files <paths>.');
}

double _r(double v) => (v * 10000).roundToDouble() / 10000;

int? _int(dynamic v) {
  if (v is int) return v;
  if (v is String) return int.tryParse(v);
  if (v is num) return v.toInt();
  return null;
}

// ── Commands ─────────────────────────────────────────────────────

Future<Map<String, dynamic>> _help(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  return {
    'version': '1',
    'commands': {
      'help': 'This schema: every command, its params, and the shared notes.',
      'ping': 'Health check. Returns engine readiness.',
      'state':
          'What the app is configured to do: model and effort per AI command, '
              'muse strand loadout, prompts, commit format. Spends nothing and '
              'forces no provider discovery. Every AI command echoes the same '
              'block under `settings`.',
      'status': 'Branch, ahead/behind, dirty files.',
      'repos': 'List known repos with engine status.',
      'diff': 'Diff text. Params: file (optional).',
      'blast-radius':
          'Co-change neighbors of given files. Params: files, limit.',
      'context':
          'Optimal reading list by coupling. Params: files, budget (chars).',
      'coherence': 'How cohesive is a file set (0-1). Params: files.',
      'suggest': 'Files you probably forgot. Params: files.',
      'profile':
          'Volatility, integrity, centrality for one file. Params: file.',
      'explain':
          'One-line natural-language characterization of a file. Params: file.',
      'test-map': 'Tests coupled to source files. Params: files.',
      'architecture':
          'Subsystem map by directory with coupling density.',
      'who-knows': 'Expert authors for a file. Params: file.',
      'recent':
          'Recent commits near a file and its coupling neighbors. '
          'Params: files, limit.',
      'search':
          'Find files by path-token matching. Params: query.',
      'dream': 'Logos commit phrase for current diff.',
      'impact': 'Predicted ripple of a diff. Params: diff.',
      'index':
          'Validate a repo, report what the engine sees in it, and register '
              'it as a project. Params: repo (optional), check (skip '
              'registering). Works on repos that were never added.',
      'review':
          'AI code review. Reviews the working tree by default; --commit '
              '<rev>, --range <A..B> (endpoints) or <A...B> (from the merge '
              'base), or --last for the newest commit. Params: files '
              '(optional, scopes the diff), model (optional).',
      'review-evidence':
          'The exact gather and prompt a review would send, stopping before '
              'the model. No model call. Same subject/scope params as review, '
              'plus diff (path to a frozen patch to replay).',
      'shake':
          'Audit the CODEBASE region by region — files as they exist at HEAD, '
              'including code history never touched. Resumable: a per-repo '
              'ledger makes repeated runs converge. Params: plan (order and '
              'coverage, no model call), regions (how many this run, default '
              '1), reset (forget the ledger), model (optional).',
      'commit-message':
          'Write the commit message for the current change, in the format the '
              'user configured. Working tree only. Params: files (optional), '
              'existing (a draft to improve), why (intent the diff cannot '
              'show — subject matter, never formatting), model (optional).',
      'muse':
          'AI brainstorm on current changes. Params: files (optional), '
              'strands (carry exactly these instead of the configured '
              'loadout, e.g. `vertigo,ghost` or `spark:3`), model (optional).',
      'deadcode':
          'Files no live surface imports (fully-dead + test-zombies) plus '
          'load-bearing joints (delete → N files orphaned).',
    },
    'notes':
        'All file params accept: --files, --file, --path, --paths, '
            '--seeds, --changed. Comma-separated or JSON array. '
            'Engine commands wait up to 15s for warmup (index and shake, '
            '60s). Review targets a revision with commit, range, or last — '
            'mutually exclusive. All commands are read-only.',
  };
}

Future<Map<String, dynamic>> _ping(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = ctx.repoState.activePath;
  return {
    'ok': true,
    'pid': pid,
    'repo': repo,
    'engineReady': repo != null && ctx.logosGitState.engineFor(repo) != null,
    'engineLoading': repo != null && ctx.logosGitState.isLoading(repo),
    'couplingReady':
        repo != null && ctx.fileCouplingState.matrixFor(repo) != null,
  };
}

Future<Map<String, dynamic>> _status(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final result = await getRepositoryStatus(repo);
  if (!result.ok) {
    throw StateError(result.error ?? 'Failed to read repository status.');
  }
  final s = result.data!;
  return {
    'repo': repo,
    'branch': s.branch,
    'upstream': s.upstream,
    'ahead': s.ahead,
    'behind': s.behind,
    'fileCount': s.files.length,
    'files': [
      for (final f in s.files)
        {
          'path': f.path,
          'staged': f.stagedCode,
          'unstaged': f.unstagedCode,
        },
    ],
  };
}

Future<Map<String, dynamic>> _repos(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final active = ctx.repoState.activePath;
  return {
    'active': active,
    'repos': [
      for (final p in ctx.repoState.recentPaths)
        {
          'path': p,
          'active': p == active,
          'engineReady': ctx.logosGitState.engineFor(p) != null,
        },
    ],
  };
}

Future<Map<String, dynamic>> _diff(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final file = params['file'] as String? ?? params['path'] as String?;
  if (file != null) {
    final r = await getFileDiff(repo, file);
    if (!r.ok) throw StateError(r.error ?? 'Failed to diff $file.');
    return {'file': file, 'diff': r.data};
  }
  // Unscoped whole-tree diff: the paths it can ever print are exactly the
  // repo's dirty set, so that set (not a guess) is what gets admitted.
  final statusResult = await getRepositoryStatus(repo);
  final statusFiles = statusResult.data?.files ?? const <RepositoryStatusFile>[];
  final unstagedPaths = [
    for (final f in statusFiles) if (f.hasUnstagedChange) f.path,
  ];
  final stagedPaths = [
    for (final f in statusFiles) if (f.hasStagedChange) f.path,
  ];

  final unstagedAdmitted = await admitGitDiffText(
    repo,
    unstagedPaths,
    () => runGit(
        repo, ['diff', '--no-color', '--patience', '--ignore-cr-at-eol']),
  );
  final stagedAdmitted = await admitGitDiffText(
    repo,
    stagedPaths,
    () => runGit(repo, [
      'diff',
      '--cached',
      '--no-color',
      '--patience',
      '--ignore-cr-at-eol',
    ]),
  );
  if (unstagedAdmitted.decision != AdmissionDecision.ran ||
      stagedAdmitted.decision != AdmissionDecision.ran) {
    throw StateError('Change-set too large to diff. Narrow with --file <path>.');
  }
  final unstaged = unstagedAdmitted.value!;
  final staged = stagedAdmitted.value!;
  return {
    'unstaged': unstaged.exitCode == 0 ? unstaged.stdout.toString() : '',
    'staged': staged.exitCode == 0 ? staged.stdout.toString() : '',
  };
}

Future<Map<String, dynamic>> _blastRadius(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final files = _resolveFiles(params);
  final limit = _int(params['limit']) ?? 20;
  final coupling = await _coupling(repo, ctx, engine);

  final neighbors = _couplingNeighbors(files, coupling, limit: limit);
  return {
    'seeds': files,
    'results': [
      for (final e in neighbors)
        {
          'path': e.key,
          'coupling': _r(e.value),
          'volatility': _r(engine.stats.volatility[e.key] ?? 0),
          'integrity': _r(engine.integrityByPath[e.key] ?? 0.85),
        },
    ],
  };
}

Future<Map<String, dynamic>> _contextCmd(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final seeds = _resolveFiles(params);
  final budget = _int(params['budget']) ?? 50000;
  final coupling = await _coupling(repo, ctx, engine);

  final neighbors = _couplingNeighbors(seeds, coupling, limit: 50);
  var totalChars = 0;
  final admitted = <Map<String, dynamic>>[];
  for (final e in neighbors) {
    final est = (e.value * 8000).round().clamp(500, 15000);
    if (totalChars + est > budget && admitted.isNotEmpty) break;
    totalChars += est;
    admitted.add({
      'path': e.key,
      'coupling': _r(e.value),
      'estimatedChars': est,
    });
  }
  return {
    'seeds': seeds,
    'budget': budget,
    'totalEstimatedChars': totalChars,
    'admitted': admitted,
  };
}

Future<Map<String, dynamic>> _coherence(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final files = _resolveFiles(params);
  final score = engine.coherence(files);
  final label = score > 0.6
      ? 'tight'
      : score > 0.35
          ? 'moderate'
          : 'mixed';
  return {'files': files, 'coherence': _r(score), 'assessment': label};
}

Future<Map<String, dynamic>> _suggest(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final changed = _resolveFiles(params);
  FileCouplingMatrix matrix;
  try {
    matrix = await _coupling(repo, ctx);
  } catch (_) {
    final engine = await _awaitEngine(repo, ctx);
    matrix = engine.stats.coupling;
  }
  final nudges = suggestMissingPeers(
    selected: changed,
    allChanged: changed,
    matrix: matrix,
  );
  return {
    'suggestions': [
      for (final n in nudges)
        {'path': n.path, 'score': _r(n.score), 'anchor': n.anchor},
    ],
  };
}

Future<Map<String, dynamic>> _profile(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final file = params['file'] as String? ?? params['path'] as String?;
  if (file == null || file.isEmpty) {
    throw ArgumentError('file required. Usage: profile --file <path>');
  }
  final stats = engine.stats;
  final coupling = await _coupling(repo, ctx, engine);

  double centrality = 0;
  for (final entry in coupling.jaccardEntriesOf(file)) {
    centrality += entry.value;
  }
  return {
    'file': file,
    'volatility': _r(stats.volatility[file] ?? 0),
    'volZ': stats.volStddev > 0
        ? _r(((stats.volatility[file] ?? 0) - stats.volMean) / stats.volStddev)
        : 0,
    'integrity': _r(engine.integrityByPath[file] ?? 0.85),
    'touchCount': stats.touches[file] ?? 0,
    'centrality': _r(centrality),
    'ritualness': _r(stats.ritualnessByPath[file] ?? 0),
    'inGraph': engine.pathToId.containsKey(file),
  };
}

Future<Map<String, dynamic>> _explain(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final file = params['file'] as String? ?? params['path'] as String?;
  if (file == null || file.isEmpty) {
    throw ArgumentError('file required. Usage: explain --file <path>');
  }
  final stats = engine.stats;
  final coupling = await _coupling(repo, ctx, engine);
  final vol = stats.volatility[file] ?? 0.0;
  final volZ = stats.volStddev > 0
      ? ((vol - stats.volMean) / stats.volStddev)
      : 0.0;
  final integ = engine.integrityByPath[file] ?? 0.85;
  final touches = stats.touches[file] ?? 0;
  double centrality = 0;
  for (final e in coupling.jaccardEntriesOf(file)) {
    centrality += e.value;
  }
  final inGraph = engine.pathToId.containsKey(file);

  final parts = <String>[];
  if (!inGraph) {
    parts.add('not tracked by the engine');
  } else {
    // Centrality
    if (centrality > 10) {
      parts.add('high-centrality hub (${centrality.toStringAsFixed(0)} coupling mass)');
    } else if (centrality > 3) {
      parts.add('moderate centrality (${centrality.toStringAsFixed(1)})');
    } else {
      parts.add('isolated (centrality ${centrality.toStringAsFixed(1)})');
    }
    // Volatility
    if (volZ > 2) {
      parts.add('very high churn (z=${volZ.toStringAsFixed(1)})');
    } else if (volZ > 0.5) {
      parts.add('above-average churn');
    } else if (volZ < -0.5) {
      parts.add('rarely changes');
    }
    // Integrity
    if (integ < 0.5) {
      parts.add('likely generated or ritual');
    } else if (integ < 0.75) {
      parts.add('mixed integrity');
    }
    // Touches
    parts.add('$touches meaningful commits');
  }
  return {'file': file, 'summary': parts.join(', ')};
}

Future<Map<String, dynamic>> _recent(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final files = _resolveFiles(params);
  final limit = _int(params['limit']) ?? 10;
  final coupling = await _coupling(repo, ctx);

  // Gather the coupling neighborhood.
  final neighborhood = <String>{...files};
  for (final f in files) {
    for (final entry in coupling.jaccardEntriesOf(f)) {
      if (entry.value > 0.2) neighborhood.add(entry.key);
    }
  }

  // Run git log touching any file in the neighborhood.
  final r = await runGit(repo, [
    'log',
    '--format=%H|%ae|%s|%aI',
    '-$limit',
    '--',
    ...neighborhood.take(30),
  ]);
  if (r.exitCode != 0) return {'commits': <Map<String, dynamic>>[]};
  final commits = <Map<String, dynamic>>[];
  for (final line in r.stdout.toString().split('\n')) {
    final parts = line.split('|');
    if (parts.length < 4) continue;
    commits.add({
      'hash': parts[0].substring(0, 7),
      'author': parts[1],
      'subject': parts.sublist(2, parts.length - 1).join('|'),
      'date': parts.last,
    });
  }
  return {'near': files, 'commits': commits};
}

Future<Map<String, dynamic>> _testMap(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final files = _resolveFiles(params);
  FileCouplingMatrix coupling;
  try {
    coupling = await _coupling(repo, ctx);
  } catch (_) {
    try {
      final engine = await _awaitEngine(repo, ctx);
      coupling = engine.stats.coupling;
    } catch (_) {
      return {'tests': <Map<String, dynamic>>[]};
    }
  }

  final tests = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final file in files) {
    for (final entry in coupling.jaccardEntriesOf(file)) {
      final p = entry.key;
      if (!seen.add(p)) continue;
      if (!_isTest(p)) continue;
      tests.add({'path': p, 'coupling': _r(entry.value), 'anchor': file});
    }
  }
  tests.sort(
      (a, b) => (b['coupling'] as double).compareTo(a['coupling'] as double));
  return {'tests': tests.take(15).toList()};
}

bool _isTest(String path) {
  final l = path.toLowerCase();
  return l.contains('_test.') ||
      l.contains('.test.') ||
      l.contains('/test/') ||
      l.contains('/tests/') ||
      l.contains('spec');
}

Future<Map<String, dynamic>> _architecture(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final stats = engine.stats;
  final coupling = engine.stats.coupling;

  // Group files by their second-level directory prefix (e.g.,
  // "lib/backend", "lib/features/changes", "test/backend").
  // This gives meaningful subsystem boundaries regardless of
  // coupling density.
  final groups = <String, List<String>>{};
  for (final path in engine.nodePaths) {
    final parts = path.replaceAll('\\', '/').split('/');
    String key;
    if (parts.length <= 2) {
      key = parts.first;
    } else {
      // Find the meaningful prefix — skip generic top-level dirs
      // like "apps/desktop-flutter/lib" to get to the subsystem.
      var depth = 0;
      for (final p in parts) {
        depth++;
        if (const {'lib', 'src', 'apps', 'packages', 'test', 'tests'}
            .contains(p)) {
          continue;
        }
        break;
      }
      key = parts.take(depth).join('/');
    }
    (groups[key] ??= []).add(path);
  }

  // For each group, compute internal coupling density and volatility.
  final result = <Map<String, dynamic>>[];
  for (final entry in groups.entries) {
    if (entry.value.length < 2) continue;
    final files = entry.value;
    double couplingSum = 0;
    int pairs = 0;
    double volSum = 0;
    for (final f in files) {
      volSum += stats.volatility[f] ?? 0;
      for (final entry2 in coupling.jaccardEntriesOf(f)) {
        if (files.contains(entry2.key)) {
          couplingSum += entry2.value;
          pairs++;
        }
      }
    }
    final density = pairs > 0 ? couplingSum / pairs : 0.0;
    final avgVol = volSum / files.length;
    result.add({
      'label': entry.key,
      'fileCount': files.length,
      'density': _r(density),
      'avgVolatility': _r(avgVol),
      'sample': files.take(8).toList(),
    });
  }
  result.sort(
      (a, b) => (b['fileCount'] as int).compareTo(a['fileCount'] as int));
  return {
    'totalFiles': engine.nodePaths.length,
    'subsystems': result,
  };
}

Future<Map<String, dynamic>> _whoKnows(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final file = params['file'] as String? ?? params['path'] as String?;
  if (file == null || file.isEmpty) {
    throw ArgumentError('file required. Usage: who-knows --file <path>');
  }
  final r = await runGit(
      repo, ['log', '--follow', '--format=%ae', '-50', '--', file]);
  if (r.exitCode != 0) return {'file': file, 'experts': <Map<String, dynamic>>[]};
  final counts = <String, int>{};
  for (final line in r.stdout.toString().split('\n')) {
    final email = line.trim();
    if (email.isEmpty) continue;
    counts[email] = (counts[email] ?? 0) + 1;
  }
  final total = counts.values.fold<int>(0, (a, b) => a + b);
  final ranked = counts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return {
    'file': file,
    'experts': [
      for (final e in ranked.take(5))
        {'email': e.key, 'commits': e.value, 'share': _r(e.value / total)},
    ],
  };
}

Future<Map<String, dynamic>> _search(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final query = params['query'] as String?;
  if (query == null || query.isEmpty) {
    throw ArgumentError('query required. Usage: search --query "text"');
  }
  final limit = _int(params['limit']) ?? 15;

  // Tokenize query into lowercase keywords.
  final keywords = query
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 2)
      .toSet();
  if (keywords.isEmpty) return {'query': query, 'results': <Map<String, dynamic>>[]};

  // TF-IDF style: score each file by how many query tokens appear
  // in its path segments, weighted inversely by how common each
  // token is across all paths.
  final tokenDf = <String, int>{};
  for (final path in engine.nodePaths) {
    for (final t in _pathTokens(path)) {
      tokenDf[t] = (tokenDf[t] ?? 0) + 1;
    }
  }
  final n = engine.nodePaths.length;
  final scored = <MapEntry<String, double>>[];
  for (final path in engine.nodePaths) {
    final segments = _pathTokens(path);
    var score = 0.0;
    for (final kw in keywords) {
      if (segments.contains(kw)) {
        final df = tokenDf[kw] ?? 1;
        score += 1.0 / (1 + df / n);
      }
    }
    if (score > 0) scored.add(MapEntry(path, score));
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  return {
    'query': query,
    'results': [
      for (final e in scored.take(limit))
        {'path': e.key, 'relevance': _r(e.value)},
    ],
  };
}

Future<Map<String, dynamic>> _dream(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final subjects = await runGit(repo, ['log', '--format=%s', '-100']);
  final subjectList = subjects.exitCode == 0
      ? subjects.stdout
          .toString()
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList()
      : <String>[];

  // Unscoped whole-tree diff, same as `_diff`: admit against the repo's
  // actual dirty set rather than an unbounded guess.
  final statusResult = await getRepositoryStatus(repo);
  final statusFiles = statusResult.data?.files ?? const <RepositoryStatusFile>[];
  final unstagedPaths = [
    for (final f in statusFiles) if (f.hasUnstagedChange) f.path,
  ];
  final stagedPaths = [
    for (final f in statusFiles) if (f.hasStagedChange) f.path,
  ];

  final unstagedAdmitted = await admitGitDiffText(
    repo,
    unstagedPaths,
    () => runGit(repo, ['diff', '--no-color', '--patience', '-U3']),
  );
  final stagedAdmitted = await admitGitDiffText(
    repo,
    stagedPaths,
    () => runGit(
        repo, ['diff', '--cached', '--no-color', '--patience', '-U3']),
  );
  if (unstagedAdmitted.decision != AdmissionDecision.ran ||
      stagedAdmitted.decision != AdmissionDecision.ran) {
    return {'phrase': null, 'reason': 'change-set too large to analyze'};
  }
  final unstaged = unstagedAdmitted.value!;
  final staged = stagedAdmitted.value!;
  final diffText = [
    if (staged.exitCode == 0) staged.stdout.toString(),
    if (unstaged.exitCode == 0) unstaged.stdout.toString(),
  ].where((d) => d.trim().isNotEmpty).join('\n');
  if (diffText.isEmpty) return {'phrase': null, 'reason': 'no changes'};

  final phrase = await dreamFromDiff(
    repoPath: repo,
    diffText: diffText,
    engine: engine,
    recentSubjects: subjectList,
  );
  return {'phrase': phrase};
}

Future<Map<String, dynamic>> _impact(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);
  final engine = await _awaitEngine(repo, ctx);
  final diffText = params['diff'] as String?;
  if (diffText == null || diffText.isEmpty) {
    throw ArgumentError('diff text required.');
  }
  final limit = _int(params['limit']) ?? 20;

  final probe = await buildDiffProbe(
      repoPath: repo, diffText: diffText, engine: engine);
  if (probe.sourceWeights.isEmpty) {
    return {'sources': <Map<String, dynamic>>[], 'ripple': <Map<String, dynamic>>[]};
  }
  final coupling = await _coupling(repo, ctx, engine);
  final scores = engine.diffuseWeighted(
    probe.sourceWeights,
    t: 1.0,
    topK: limit,
    coherenceGate: 0.2,
  );
  return {
    'sources': [
      for (final e in probe.sourceWeights.entries)
        {'path': e.key, 'weight': _r(e.value)},
    ],
    'ripple': [
      for (final s in scores)
        {
          'path': s.path,
          'phi': _r(s.phi),
          'coupling': _r(_meanCouplingTo(
              s.path, probe.sourceWeights.keys.toList(), coupling)),
        },
    ],
  };
}

Set<String> _pathTokens(String path) {
  return path
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9]+'))
      .where((t) => t.length >= 2)
      .toSet();
}

double _meanCouplingTo(
    String path, List<String> targets, FileCouplingMatrix matrix) {
  if (targets.isEmpty) return 0;
  var sum = 0.0;
  for (final t in targets) {
    sum += combinedCouplingScore(path, t, matrix);
  }
  return sum / targets.length;
}

// ── AI commands ─────────────────────────────────────────────────

typedef _ResolvedModel = ({
  String modelValue,
  String categoryLabel,
  String categoryId,
  String? effort,
  bool fast,
  bool supportsReasoning,
});

Future<List<AiModelCategoryData>> _ensureCategories(
    ManifoldBridgeContext ctx) async {
  final ai = ctx.aiSettingsState;
  if (ai.runtimeModelCategories.isEmpty) {
    final ok = await ai.refreshModelCategories(forceRefresh: true);
    if (!ok) {
      throw StateError(
          ai.runtimeModelCategoriesError ??
          'No AI models available. Configure an API key in settings.');
    }
  }
  final categories = ai.runtimeModelCategories;
  if (categories.isEmpty) {
    throw StateError('No AI models available. Configure an API key in settings.');
  }
  return categories;
}

_ResolvedModel _pickModel(
  List<AiModelCategoryData> categories,
  ManifoldBridgeContext ctx, {
  required String preferredCategoryId,
  String? modelOverride,
}) {
  final ai = ctx.aiSettingsState;
  final category = categories
          .where((c) => c.id == preferredCategoryId && c.models.isNotEmpty)
          .firstOrNull ??
      categories.where((c) => c.models.isNotEmpty).firstOrNull;
  if (category == null || category.models.isEmpty) {
    throw StateError('No models in any category.');
  }

  final model = modelOverride != null
      ? (category.models.where((m) => m.value == modelOverride).firstOrNull ??
          category.models.first)
      : (category.models
              .where((m) =>
                  m.value == ai.modelSelections[category.id])
              .firstOrNull ??
          category.models.first);

  final eff = ai.resolveEffort(category.id, model.value);
  return (
    modelValue: model.value,
    categoryLabel: ai.labelForCategory(category.id, category.label),
    categoryId: category.id,
    effort: eff.effort,
    fast: eff.fast,
    supportsReasoning: model.supportsReasoning,
  );
}

typedef _ScopeResult = (
  List<String> paths,
  String label,
  ReviewTarget target,
  List<RepositoryStatusFile> statusFiles,
);

/// The review subject named by `--commit` / `--range`, or null for the
/// working tree.
///
/// `--last` is the shorthand for "the commit I just made", which is the whole
/// reason this exists: reviewing work that has already landed, from a
/// terminal, without touching the app.
///
/// Conflicting flags are REFUSED rather than ranked. A precedence rule would
/// let `--last --commit abc` succeed and print an ordinary-looking review of
/// something the caller did not ask for, and nothing downstream could tell —
/// which is worse than any error. There is no ordering here to get wrong
/// because there is no ordering.
///
/// Visible for testing because this is the CLI's contract, and a review of
/// the wrong revision looks exactly like a review of the right one.
@visibleForTesting
ReviewTarget? historyTargetFrom(Map<String, dynamic> params) {
  final last = params['last'] == 'true' || params['last'] == true;
  final commit = (params['commit'] as String?)?.trim() ?? '';
  final range = (params['range'] as String?)?.trim() ?? '';

  final named = <String>[
    if (last) '--last',
    if (commit.isNotEmpty) '--commit',
    if (range.isNotEmpty) '--range',
  ];
  if (named.length > 1) {
    throw ArgumentError(
      '${named.join(' and ')} name different revisions. Pass exactly one.',
    );
  }

  if (last) return const CommitTarget('HEAD');
  return parseReviewTargetSpec(commit: commit, range: range);
}

Future<_ScopeResult> _resolveScope(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final repo = _requireRepo(params, ctx);

  // A history target needs no working-tree status at all: what changed is a
  // property of the commits, and the resolver reads it from them. Asking
  // `git status` here would describe the developer's current mess, not the
  // subject. Paths, when given, SCOPE the revision diff rather than select
  // dirty files.
  final history = historyTargetFrom(params);
  if (history != null) {
    final scoped = _resolveFilesOptional(params) ?? const <String>[];
    return (
      scoped,
      // Provisional: the resolver replaces this with what it actually found
      // ("commit a1b2c3d - subject") once the diff is derived.
      switch (history) {
        CommitTarget(:final revspec) => 'commit $revspec',
        RangeTarget(:final base, :final tip, :final mergeBase) =>
          '$base${mergeBase ? '...' : '..'}$tip',
        _ => 'revision',
      },
      history,
      const <RepositoryStatusFile>[],
    );
  }

  final statusResult = await getRepositoryStatus(repo);
  final statusFiles = statusResult.data?.files ?? [];

  final explicit = _resolveFilesOptional(params);
  if (explicit != null) {
    final explicitStatus = statusFiles.where(
      (f) => explicit.contains(f.path),
    );
    return (
      explicit,
      '${explicit.length} file${explicit.length == 1 ? '' : 's'}',
      WorkingTreeTarget(
        includeStaged:
            explicitStatus.isEmpty || explicitStatus.any((f) => f.hasStagedChange),
        includeUnstaged: explicitStatus.isEmpty ||
            explicitStatus.any((f) => f.hasUnstagedChange),
      ),
      statusFiles,
    );
  }
  if (!statusResult.ok || statusResult.data == null) {
    throw StateError(
      'Failed to read repository status for $repo: '
      '${statusResult.error ?? "unknown error"}',
    );
  }
  final paths = statusFiles.map((f) => f.path).toList();
  if (paths.isEmpty) {
    throw StateError('No dirty files to review in $repo');
  }
  return (
    paths,
    paths.length == statusFiles.length
        ? 'all included files'
        : '${paths.length} file${paths.length == 1 ? '' : 's'}',
    WorkingTreeTarget(
      includeStaged: statusFiles.any((f) => f.hasStagedChange),
      includeUnstaged: statusFiles.any((f) => f.hasUnstagedChange),
    ),
    statusFiles,
  );
}

/// Hard ceiling on one AI provider call from the bridge. A hung
/// provider must become a LOUD, prompt error — observed 2026-07-22: a
/// wedged review sat silent for 6006s and finally surfaced as an empty
/// result the CLI rendered as "No findings."
///
/// Per-provider-call budget, deliberately ABOVE ai.dart's
/// `_providerRuntimeTimeout` (20m): the provider runner owns the real
/// timeout — it kills its subprocess tree and records diagnostics — and
/// the bridge must never win that race with a generic message that
/// masks the runner's specific one. The ceiling SCALES with the flow's
/// sequential provider calls (double-check review = draft + verify,
/// muse = brainstorm + synthesis): a flat ceiling starved legitimate
/// multi-call runs (caught by the manifold review). It backstops only
/// hangs OUTSIDE the runner; it does not cancel underlying work.
const Duration _kAiCallBudget = Duration(minutes: 22);

Future<T> _boundedAi<T>(String what, Future<T> call, {int calls = 1}) {
  final ceiling = _kAiCallBudget * calls;
  return call.timeout(
    ceiling,
    onTimeout: () => throw StateError(
        '$what timed out after ${ceiling.inMinutes} minutes '
        '($calls provider call${calls == 1 ? '' : 's'} budgeted) — the AI '
        'provider is likely hung. Retry; if it persists, restart '
        'Manifold.'),
  );
}

Future<Map<String, dynamic>> _review(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final totalSw = Stopwatch()..start();
  final repo = _requireRepo(params, ctx);
  final cacheRoot = await _resolveCommonRoot(repo);
  final categories = await _ensureCategories(ctx);
  final ai = ctx.aiSettingsState;
  final prefs = ctx.preferencesState;
  final model = _pickModel(
    categories, ctx,
    preferredCategoryId: ai.reviewCommitModelCategoryId,
    modelOverride: params['model'] as String?,
  );

  _progress('scope');
  final scopeSw = Stopwatch()..start();
  final (scopeFiles, scopeLabel, target, statusFiles) =
      await _resolveScope(params, ctx);
  final scopeMs = scopeSw.elapsedMilliseconds;
  _progress('scope',
      target is WorkingTreeTarget ? '${scopeFiles.length} files' : scopeLabel);

  _progress('warmup');
  final couplingWarm = await _awaitCoupling(cacheRoot, ctx);
  final cSym = couplingWarm.data != null ? '✓' : '–';
  _progress('warmup', 'coupling $cSym');

  final shortModel = model.modelValue.split('/').last;
  _progress('ai', shortModel);
  final aiSw = Stopwatch()..start();
  final result = await _boundedAi(
    'review',
    reviewCommit(
    repositoryPath: repo,
    modelValue: model.modelValue,
    modelCategoryLabel: model.categoryLabel,
    scopeLabel: scopeLabel,
    reasoningEffort: model.effort,
    fastMode: model.fast,
    supportsReasoning: model.supportsReasoning,
    target: target,
    scopedPaths: scopeFiles,
    customPrompt: ai.reviewCommitPrompt,
    guardrailStage: prefs.guardrailStage,
    doubleCheckEnabled: ai.reviewCommitDoubleCheckEnabled,
    readOnly: true,
    couplingMatrix: couplingWarm.data,
  ),
    calls: ai.reviewCommitDoubleCheckEnabled ? 2 : 1,
  );
  final aiMs = aiSw.elapsedMilliseconds;
  totalSw.stop();

  if (!result.ok || result.data == null) {
    // Throw, don't return {'error': …}: a returned error map hides under
    // `result`, which the CLI reads as success (exit 0).
    throw StateError(result.error ?? 'Review failed.');
  }
  final d = result.data!;
  return {
    'repo': repo,
    'verdict': d.verdict,
    'score': d.score,
    'summary': d.summary,
    'model': '${d.providerId}/${d.modelId}',
    'scope': d.scopeLabel,
    'guardrailStage': d.guardrailStage,
    'doubleCheck': d.twoStepEnabled,
    'enrichment': {
      'coupling': couplingWarm.data != null,
      'couplingMs': couplingWarm.ms,
      'couplingTimedOut': couplingWarm.timedOut,
    },
    // For history, the file list comes from the REVISION — the working
    // tree's status describes today's uncommitted work and would report
    // "0/0 files" for a perfectly good commit review.
    'files': target is WorkingTreeTarget
        ? {
            'reviewed': scopeFiles.length,
            'total': statusFiles.length,
            'paths': [
              for (final p in scopeFiles)
                {
                  'path': p,
                  'staged': statusFiles
                      .where((f) => f.path == p)
                      .firstOrNull
                      ?.hasStagedChange ?? false,
                  'unstaged': statusFiles
                      .where((f) => f.path == p)
                      .firstOrNull
                      ?.hasUnstagedChange ?? true,
                },
            ],
          }
        : {
            'reviewed': d.reviewedPaths.length,
            'total': d.reviewedPaths.length,
            'paths': [
              for (final p in d.reviewedPaths) {'path': p},
            ],
          },
    'timing': {
      'totalMs': totalSw.elapsedMilliseconds,
      'scopeMs': scopeMs,
      'warmupMs': couplingWarm.ms,
      'aiMs': aiMs,
    },
    'promptChars': d.promptCharacters,
    'diffChars': d.diffCharacters,
    'inputTokens': d.inputTokens,
    'outputTokens': d.outputTokens,
    'reasoningReport': d.reasoningReport.isNotEmpty ? d.reasoningReport : null,
    'findings': [
      for (final f in d.findings)
        {
          'title': f.title,
          'severity': f.severity,
          'file': f.filePath,
          'hunk': f.hunkLabel,
          'evidence': f.evidence,
          'why': f.whyItMatters,
        },
    ],
    'observations': [
      for (final o in d.observations)
        {
          'title': o.title,
          'detail': o.detail,
          'file': o.filePath,
        },
    ],
    'settings': settingsSnapshot(ctx),
  };
}

/// Write the commit message for the current change.
///
/// The plainest thing in the CLI on purpose: an agent that has just finished
/// editing asks for the message and gets it. It uses the user's OWN settings
/// — their model slot, their custom prompt, their chosen structure, voice and
/// coverage — because a message generated to somebody else's taste is a
/// message they have to rewrite.
///
/// Returns the message as one string. `--json` yields it alongside the
/// settings that produced it, so a caller can tell whether it got what the
/// user configured or a fallback.
Future<Map<String, dynamic>> _commitMessage(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final totalSw = Stopwatch()..start();
  final repo = _requireRepo(params, ctx);
  final cacheRoot = await _resolveCommonRoot(repo);
  final categories = await _ensureCategories(ctx);
  final ai = ctx.aiSettingsState;
  final prefs = ctx.preferencesState;
  final model = _pickModel(
    categories, ctx,
    preferredCategoryId: ai.commitMessageModelCategoryId,
    modelOverride: params['model'] as String?,
  );

  _progress('scope');
  final (scopeFiles, scopeLabel, target, statusFiles) =
      await _resolveScope(params, ctx);
  // A commit message describes work about to be committed. There is no such
  // thing as a message for a commit that already exists — that message was
  // written when it was made.
  if (target is! WorkingTreeTarget) {
    throw StateError(
        'A commit message describes work not yet committed. Drop --commit / '
        '--range; to read an existing commit\'s message use `git log`.');
  }
  _progress('scope', '${scopeFiles.length} files');

  _progress('warmup');
  final couplingWarm = await _awaitCoupling(cacheRoot, ctx);

  _progress('ai', model.modelValue.split('/').last);
  final result = await _boundedAi(
    'commit-message',
    generateCommitMessage(
      repositoryPath: repo,
      modelValue: model.modelValue,
      modelCategoryLabel: model.categoryLabel,
      scopeLabel: scopeLabel,
      reasoningEffort: model.effort,
      fastMode: model.fast,
      supportsReasoning: model.supportsReasoning,
      includeStaged: target.includeStaged,
      includeUnstaged: target.includeUnstaged,
      scopedPaths: scopeFiles,
      customPrompt: ai.commitMessagePrompt,
      existingMessage: params['existing'] as String? ?? '',
      // `--why`: the intent behind the change, which no diff carries. Named
      // for the question rather than for "steering" on purpose — a flag that
      // invites instructions gets instructions, and the user's format is not
      // the caller's to change.
      authorContext: params['why'] as String? ?? '',
      readOnly: true,
      structure: prefs.commitStructure,
      voice: prefs.commitVoice,
      coverage: prefs.commitCoverage,
      couplingMatrix: couplingWarm.data,
    ),
  );
  totalSw.stop();

  if (!result.ok || result.data == null) {
    throw StateError(result.error ?? 'Commit message generation failed.');
  }
  final d = result.data!;
  return {
    'repo': repo,
    'message': d.message,
    'model': '${d.providerId}/${d.modelId}',
    'scope': d.scopeLabel,
    'files': {
      'reviewed': scopeFiles.length,
      'total': statusFiles.length,
    },
    'promptChars': d.promptCharacters,
    'diffChars': d.diffCharacters,
    'inputTokens': d.inputTokens,
    'outputTokens': d.outputTokens,
    'timing': {'totalMs': totalSw.elapsedMilliseconds},
    'settings': settingsSnapshot(ctx),
  };
}

/// Review-evidence dry-run. Runs the IDENTICAL gather + prompt assembly a
/// real `review` runs ([gatherReviewEvidence]), but stops before the model
/// and returns the structured evidence + per-phase/per-producer telemetry +
/// the full assembled prompt. The faithful "see what the app feeds the LLM"
/// path — no model cost, no alternate gather.
Future<Map<String, dynamic>> _reviewEvidence(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final totalSw = Stopwatch()..start();
  final repo = _requireRepo(params, ctx);
  final cacheRoot = await _resolveCommonRoot(repo);

  // The CHEAP, LOCAL checks first. Configuring an AI provider is neither, and
  // doing it first meant a mistyped `--diff` path reported "No models in any
  // category" — an error about the wrong thing entirely, sending the reader
  // to look at their model settings over a typo. Validate what the caller
  // typed before demanding the machinery to act on it.
  final diffPathEarly = params['diff'] as String?;
  if (diffPathEarly != null &&
      diffPathEarly.isNotEmpty &&
      !await File(diffPathEarly).exists()) {
    throw StateError('No frozen diff at $diffPathEarly.');
  }

  final categories = await _ensureCategories(ctx);
  final ai = ctx.aiSettingsState;
  final prefs = ctx.preferencesState;
  final model = _pickModel(
    categories, ctx,
    preferredCategoryId: ai.reviewCommitModelCategoryId,
    modelOverride: params['model'] as String?,
  );

  // Frozen-diff replay (`--diff <path>`) for clean A/B across rebuilds: the
  // same bytes measured again as the engine changes under them.
  //
  // Resolved FIRST, and short-circuiting the working-tree scope entirely. A
  // supplied patch IS the whole review subject, so asking `git status` what
  // is dirty answers a question nobody posed — and `_resolveScope` throws on
  // a clean checkout, which made the documented A/B replay impossible to run
  // from exactly the clean tree it is meant to be run from.
  _progress('scope');
  final diffPath = params['diff'] as String?;
  PreparedDiffTarget? frozen;
  if (diffPath != null && diffPath.isNotEmpty) {
    final f = File(diffPath);
    if (!await f.exists()) {
      throw StateError('No frozen diff at $diffPath.');
    }
    frozen = PreparedDiffTarget(
      diffText: await f.readAsString(),
      label: 'frozen diff ${p.basename(diffPath)}',
      branchName: 'ab-frozen',
    );
  }

  final List<String> scopeFiles;
  final String scopeLabel;
  final ReviewTarget evidenceTarget;
  final List<RepositoryStatusFile> statusFiles;
  if (frozen != null) {
    scopeFiles = const [];
    scopeLabel = frozen.label;
    evidenceTarget = frozen;
    statusFiles = const [];
  } else {
    (scopeFiles, scopeLabel, evidenceTarget, statusFiles) =
        await _resolveScope(params, ctx);
  }
  _progress(
      'scope',
      evidenceTarget is WorkingTreeTarget
          ? '${scopeFiles.length} files'
          : scopeLabel);

  _progress('warmup');
  final couplingWarm = await _awaitCoupling(cacheRoot, ctx);
  _progress('warmup', 'coupling ${couplingWarm.data != null ? '✓' : '–'}');

  _progress('gather');
  final result = await gatherReviewEvidence(
    repositoryPath: repo,
    modelCategoryLabel: model.categoryLabel,
    requestedScopeLabel: scopeLabel,
    target: evidenceTarget,
    scopedPaths: scopeFiles,
    customPrompt: ai.reviewCommitPrompt,
    guardrailStage: prefs.guardrailStage,
    couplingMatrix: couplingWarm.data,
  );
  totalSw.stop();

  if (!result.ok || result.data == null) {
    throw StateError(result.error ?? 'Evidence gather failed.');
  }
  final d = result.data!;
  return {
    'repo': repo,
    'files': {
      'reviewed': scopeFiles.length,
      'total': statusFiles.length,
    },
    'enrichment': {
      'coupling': couplingWarm.data != null,
      'couplingMs': couplingWarm.ms,
    },
    'wallMs': totalSw.elapsedMilliseconds,
    ...d.toJson(),
  };
}

Future<Map<String, dynamic>> _muse(
  Map<String, dynamic> params,
  ManifoldBridgeContext ctx,
) async {
  final totalSw = Stopwatch()..start();
  final repo = _requireRepo(params, ctx);
  final cacheRoot = await _resolveCommonRoot(repo);
  final categories = await _ensureCategories(ctx);
  final ai = ctx.aiSettingsState;
  final prefs = ctx.preferencesState;

  final brainstormModel = _pickModel(
    categories, ctx,
    preferredCategoryId: ai.museBrainstormModelCategoryId,
    modelOverride: params['model'] as String?,
  );
  final synthesisModel = _pickModel(
    categories, ctx,
    preferredCategoryId: ai.museSynthesisModelCategoryId,
    modelOverride: params['model'] as String?,
  );

  _progress('scope');
  final scopeSw = Stopwatch()..start();
  // Parsed BEFORE any model work: an unknown strand name is the caller's
  // typo, and finding out after a provider spin-up wastes their time.
  final strandOverride = parseStrandOverride(params['strands']);

  final (scopeFiles, scopeLabel, rawMuseTarget, statusFiles) =
      await _resolveScope(params, ctx);
  // Muse brainstorms about work in progress. Pointing it at a commit would
  // silently hand it the working tree instead, so it refuses rather than
  // answering a question it was not asked.
  if (rawMuseTarget is! WorkingTreeTarget) {
    throw StateError(
        'muse works on the current change, not on history. Drop --commit / '
        '--range, or use `manifold review` for a revision.');
  }
  final museTarget = rawMuseTarget;
  final scopeMs = scopeSw.elapsedMilliseconds;
  _progress('scope', '${scopeFiles.length} files');

  _progress('warmup');
  final couplingWarm = await _awaitCoupling(cacheRoot, ctx);
  final cSym = couplingWarm.data != null ? '✓' : '–';
  _progress('warmup', 'coupling $cSym');

  final shortModel = brainstormModel.modelValue.split('/').last;
  _progress('brainstorm', shortModel);
  final aiSw = Stopwatch()..start();
  final result = await _boundedAi(
    'muse',
    runMuse(
    repositoryPath: repo,
    brainstormModelValue: brainstormModel.modelValue,
    synthesisModelValue: synthesisModel.modelValue,
    scopeLabel: scopeLabel,
    brainstormReasoningEffort: brainstormModel.effort,
    brainstormFastMode: brainstormModel.fast,
    brainstormSupportsReasoning: brainstormModel.supportsReasoning,
    synthesisReasoningEffort: synthesisModel.effort,
    synthesisFastMode: synthesisModel.fast,
    synthesisSupportsReasoning: synthesisModel.supportsReasoning,
    includeStaged: museTarget.includeStaged,
    includeUnstaged: museTarget.includeUnstaged,
    scopedPaths: scopeFiles,
    // The user's own loadout unless the caller named strands. This was
    // passed as nothing at all before, so `manifold muse` silently ran the
    // default four regardless of what the settings said — the CLI answering
    // a different question than the app for the same repository.
    quiver: strandOverride ?? ai.museQuiver,
    customPrompt: ai.musePrompt,
    guardrailStage: prefs.guardrailStage,
    readOnly: true,
    couplingMatrix: couplingWarm.data,
  ),
    calls: 2,
  );
  final aiMs = aiSw.elapsedMilliseconds;
  totalSw.stop();

  if (!result.ok || result.data == null) {
    throw StateError(result.error ?? 'Muse failed.');
  }
  final d = result.data!;
  return {
    'repo': repo,
    'brainstormModel': '${d.providerId}/${d.modelId}',
    'synthesisModel': '${synthesisModel.categoryLabel}/${synthesisModel.modelValue}',
    'scope': d.scopeLabel,
    'enrichment': {
      'coupling': couplingWarm.data != null,
      'couplingMs': couplingWarm.ms,
      'couplingTimedOut': couplingWarm.timedOut,
    },
    'files': {
      'reviewed': scopeFiles.length,
      'total': statusFiles.length,
      'paths': [
        for (final p in scopeFiles)
          {
            'path': p,
            'staged': statusFiles
                .where((f) => f.path == p)
                .firstOrNull
                ?.hasStagedChange ?? false,
            'unstaged': statusFiles
                .where((f) => f.path == p)
                .firstOrNull
                ?.hasUnstagedChange ?? true,
          },
      ],
    },
    'tokens': {
      'brainstormIn': d.brainstormInputTokens,
      'brainstormOut': d.brainstormOutputTokens,
      'synthesisIn': d.synthesisInputTokens,
      'synthesisOut': d.synthesisOutputTokens,
      'totalIn': d.totalInputTokens,
      'totalOut': d.totalOutputTokens,
    },
    'timing': {
      'totalMs': totalSw.elapsedMilliseconds,
      'scopeMs': scopeMs,
      'warmupMs': couplingWarm.ms,
      'aiMs': aiMs,
    },
    'proposals': [
      for (final p in d.proposals)
        {
          'tier': p.tier.name,
          'title': p.title,
          'vision': p.vision,
          'foothold': p.foothold,
          'citations': p.citations,
        },
    ],
    if (d.brainstormIdeas.isNotEmpty)
      'brainstormIdeas': [
        for (final idea in d.brainstormIdeas)
          {
            'index': idea.index,
            'text': idea.text,
          },
      ],
    if (d.parseWarnings.isNotEmpty)
      'warnings': d.parseWarnings,
    'settings': settingsSnapshot(ctx),
    // What the muse actually carried this run, which is NOT the configured
    // loadout when the caller named strands.
    'strandsUsed': [
      for (final e in (strandOverride ?? ai.museQuiver))
        {'kind': museStrandLabel(e.kind), 'count': e.count},
    ],
    'strandsOverridden': strandOverride != null,
  };
}

List<String>? _resolveFilesOptional(Map<String, dynamic> params) {
  for (final key in const [
    'files', 'file', 'paths', 'path', 'seeds', 'changed',
  ]) {
    final raw = params[key];
    if (raw == null) continue;
    if (raw is List) {
      final result = [for (final item in raw) '$item'.trim()]
          .where((s) => s.isNotEmpty)
          .toList();
      if (result.isNotEmpty) return result;
    }
    if (raw is String && raw.isNotEmpty) {
      final result = raw
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (result.isNotEmpty) return result;
    }
  }
  return null;
}
