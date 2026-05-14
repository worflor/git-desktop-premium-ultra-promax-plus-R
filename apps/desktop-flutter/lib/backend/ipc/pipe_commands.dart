import 'dart:async';
import 'dart:io' show pid;

import '../file_coupling.dart';
import '../git.dart';
import '../logos_dream.dart';
import '../logos_git.dart';
import '../logos_git_probe.dart';
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
};

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

Future<LogosGit> _awaitEngine(String repo, ManifoldBridgeContext ctx) async {
  var engine = ctx.logosGitState.engineFor(repo);
  if (engine != null) return engine;
  unawaited(ctx.logosGitState.loadForRepo(repo));
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    engine = ctx.logosGitState.engineFor(repo);
    if (engine != null) return engine;
  }
  throw StateError('Logos engine did not load within 15s for $repo.');
}

FileCouplingMatrix _coupling(String repo, ManifoldBridgeContext ctx,
    [LogosGit? engine]) {
  final m = ctx.fileCouplingState.matrixFor(repo) ??
      engine?.stats.coupling ??
      ctx.logosGitState.engineFor(repo)?.stats.coupling;
  if (m != null) return m;
  // Kick off a load for next time.
  unawaited(ctx.fileCouplingState.loadForRepo(repo));
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
      'ping': 'Health check. Returns engine readiness.',
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
    },
    'notes':
        'All file params accept: --files, --file, --path, --paths, '
            '--seeds, --changed. Comma-separated or JSON array. '
            'Engine commands wait up to 15s for warmup. '
            'All commands are read-only.',
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
  if (!result.ok) return {'error': result.error};
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
    if (!r.ok) return {'error': r.error};
    return {'file': file, 'diff': r.data};
  }
  final unstaged = await runGitProbe(
      repo, ['diff', '--no-color', '--patience', '--ignore-cr-at-eol']);
  final staged = await runGitProbe(repo,
      ['diff', '--cached', '--no-color', '--patience', '--ignore-cr-at-eol']);
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
  final coupling = _coupling(repo, ctx, engine);

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
  final coupling = _coupling(repo, ctx, engine);

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
    matrix = _coupling(repo, ctx);
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
  final coupling = _coupling(repo, ctx, engine);

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
  final coupling = _coupling(repo, ctx, engine);
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
  final coupling = _coupling(repo, ctx);

  // Gather the coupling neighborhood.
  final neighborhood = <String>{...files};
  for (final f in files) {
    for (final entry in coupling.jaccardEntriesOf(f)) {
      if (entry.value > 0.2) neighborhood.add(entry.key);
    }
  }

  // Run git log touching any file in the neighborhood.
  final r = await runGitProbe(repo, [
    'log',
    '--format=%H|%ae|%s|%aI',
    '-$limit',
    '--',
    ...neighborhood.take(30),
  ]);
  if (r.exitCode != 0) return {'commits': []};
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
    coupling = _coupling(repo, ctx);
  } catch (_) {
    try {
      final engine = await _awaitEngine(repo, ctx);
      coupling = engine.stats.coupling;
    } catch (_) {
      return {'tests': []};
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
            .contains(p)) continue;
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
  final r = await runGitProbe(
      repo, ['log', '--follow', '--format=%ae', '-50', '--', file]);
  if (r.exitCode != 0) return {'file': file, 'experts': []};
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
  if (keywords.isEmpty) return {'query': query, 'results': []};

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
  final subjects = await runGitProbe(repo, ['log', '--format=%s', '-100']);
  final subjectList = subjects.exitCode == 0
      ? subjects.stdout
          .toString()
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList()
      : <String>[];

  final unstaged = await runGitProbe(
      repo, ['diff', '--no-color', '--patience', '-U3']);
  final staged = await runGitProbe(
      repo, ['diff', '--cached', '--no-color', '--patience', '-U3']);
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
    return {'sources': [], 'ripple': []};
  }
  final coupling = _coupling(repo, ctx, engine);
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
