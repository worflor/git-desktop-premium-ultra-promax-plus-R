// dead_code_strainer.dart — reachability-based dead-code detection.
//
// The one dead-code signal that survived empirical validation (see the research
// dossier / memory `project_strainer_structure_vs_death`): a Dart file is dead
// when the import/export/part closure from the app's real entry points never
// reaches it. This makes a claim imports can actually back — unlike grammar-free
// "cold × isolated" heuristics, which scored 6/7 false positives against a hand
// audit because a *stable* file (unchanged for months but reachable from main)
// looks identical to an abandoned one under time signals alone.
//
// We split reachability into two entry sets so the verdict stays honest:
//   • APP entries  — lib/main.dart + anything under bin/  → the shipping app.
//   • TEST entries — test/** + *_test.dart                → the test suite.
// A lib file then falls into exactly one bucket:
//   • alive       — reached from an app entry.
//   • testZombie  — reached ONLY from a test (dead in the app; a leftover test
//                   keeps it compiling). e.g. a widget ported but never wired in.
//   • fullyDead   — reached from nothing at all.
//
// Dart imports are static (no runtime dispatch to miss) and `package:` URIs
// resolve exactly, so file-level reachability is reliable where symbol-level
// reachability is not. `part`/`part of` is handled: a part file is reached when
// its parent library is (you import the parent, never the part).
//
// Self-contained: only dart core, so it unit-tests without a package graph.

/// Everything before the last `/` (POSIX). `'a/b/c.dart' -> 'a/b'`, no slash -> ''.
String _posixDirname(String path) {
  final i = path.lastIndexOf('/');
  return i <= 0 ? '' : path.substring(0, i);
}

/// Collapse `.` and `..` segments (POSIX). Leading `..` are preserved for
/// relative paths; a rooted path never escapes above `/`.
String _posixNormalize(String path) {
  final rooted = path.startsWith('/');
  final out = <String>[];
  for (final seg in path.split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    if (seg == '..') {
      if (out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else if (!rooted) {
        out.add('..');
      }
    } else {
      out.add(seg);
    }
  }
  final joined = out.join('/');
  return rooted ? '/$joined' : joined;
}

/// Resolve [rel] against directory [dir] and normalise (POSIX).
String _posixJoin(String dir, String rel) =>
    _posixNormalize(dir.isEmpty ? rel : '$dir/$rel');

/// Structural load per file: how many OTHER files get orphaned from the app if
/// this file is deleted — the size of its dominated subtree in the dominator
/// tree of the import graph [adj] (importer → imported, `n` nodes) rooted at a
/// virtual node joined to every entry in [entries]. Returns a list of length
/// `n`; entries and unreachable files get load 0. Load-bearing joints are the
/// rare high-load files. (Cooper–Harvey–Kennedy iterative dominators; verified
/// against a brute-force "delete it, recount reachable" on real graphs.)
List<int> _dominatorLoad(int n, List<List<int>> adj, Set<int> entries) {
  final root = n;
  final succ = List<List<int>>.generate(
      n + 1, (i) => i == root ? entries.toList() : adj[i]);

  // Iterative postorder from the virtual root over the reachable subgraph.
  final postorder = <int>[];
  final visited = List.filled(n + 1, false);
  final cursor = List.filled(n + 1, 0);
  final stack = <int>[root];
  visited[root] = true;
  while (stack.isNotEmpty) {
    final u = stack.last;
    if (cursor[u] < succ[u].length) {
      final v = succ[u][cursor[u]++];
      if (!visited[v]) {
        visited[v] = true;
        stack.add(v);
      }
    } else {
      postorder.add(u);
      stack.removeLast();
    }
  }
  final order = postorder.reversed.toList(); // reverse postorder
  final rpo = List.filled(n + 1, -1);
  for (var i = 0; i < order.length; i++) {
    rpo[order[i]] = i;
  }
  final preds = List<List<int>>.generate(n + 1, (_) => <int>[]);
  for (var u = 0; u <= n; u++) {
    for (final v in succ[u]) {
      if (visited[v]) preds[v].add(u);
    }
  }

  final idom = List.filled(n + 1, -1);
  idom[root] = root;
  int intersect(int a, int b) {
    while (a != b) {
      while (rpo[a] > rpo[b]) {
        a = idom[a];
      }
      while (rpo[b] > rpo[a]) {
        b = idom[b];
      }
    }
    return a;
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final node in order) {
      if (node == root) continue;
      var newIdom = -1;
      for (final p in preds[node]) {
        if (idom[p] != -1) {
          newIdom = (newIdom == -1) ? p : intersect(p, newIdom);
        }
      }
      if (newIdom != -1 && idom[node] != newIdom) {
        idom[node] = newIdom;
        changed = true;
      }
    }
  }

  // Dominated subtree sizes via a postorder DFS of the dominator tree.
  final children = List<List<int>>.generate(n + 1, (_) => <int>[]);
  for (var node = 0; node < n; node++) {
    if (idom[node] != -1 && idom[node] != node) children[idom[node]].add(node);
  }
  final size = List.filled(n + 1, 1);
  final dcursor = List.filled(n + 1, 0);
  final dstack = <int>[root];
  while (dstack.isNotEmpty) {
    final u = dstack.last;
    if (dcursor[u] < children[u].length) {
      dstack.add(children[u][dcursor[u]++]);
    } else {
      dstack.removeLast();
      if (dstack.isNotEmpty) size[dstack.last] += size[u];
    }
  }
  return [
    for (var i = 0; i < n; i++)
      (idom[i] != -1 && !entries.contains(i)) ? size[i] - 1 : 0,
  ];
}

/// Which live surface, if any, can reach a file.
enum DeadCodeCategory {
  /// Reachable from an app entry point (main / bin). Shipping code.
  alive,

  /// Reachable only from a test — dead in the app, kept alive by a leftover
  /// test import.
  testZombie,

  /// Reachable from nothing at all. Fully dead.
  fullyDead,
}

/// A load-bearing joint: an alive file whose deletion would orphan [load] OTHER
/// files from the app. Computed from the dominator tree of the import graph —
/// [load] is the size of the file's dominated subtree. A handful of high-load
/// files are the architectural spine; most files have load 0 (leaves).
class LoadBearingRecord {
  const LoadBearingRecord({required this.path, required this.load});

  final String path;
  final int load;

  Map<String, dynamic> toJson() => {'path': path, 'load': load};
}

/// One source file handed to the strainer: its repo-relative POSIX path and raw
/// text. The analyzer does no I/O of its own so it stays deterministic + unit
/// testable; callers supply the bytes.
class DeadCodeInput {
  const DeadCodeInput(this.path, this.content);

  /// Repo-relative path, POSIX separators (e.g. `apps/desktop-flutter/lib/x.dart`).
  final String path;
  final String content;
}

/// A file that no live surface reaches, with the reason it was flagged.
class DeadFileRecord {
  const DeadFileRecord({
    required this.path,
    required this.category,
  });

  final String path;
  final DeadCodeCategory category;

  Map<String, dynamic> toJson() => {
        'path': path,
        'category': category.name,
      };
}

/// The strainer's verdict over a repository's Dart sources.
class DeadCodeReport {
  const DeadCodeReport({
    required this.fullyDead,
    required this.testZombies,
    required this.joints,
    required this.aliveLibFiles,
    required this.totalLibFiles,
    required this.appEntryCount,
    required this.testEntryCount,
    required this.hasAppEntry,
  });

  /// Lib files reached by nothing. Sorted by path.
  final List<DeadFileRecord> fullyDead;

  /// Lib files reached only by tests (dead in the app). Sorted by path.
  final List<DeadFileRecord> testZombies;

  /// Load-bearing joints: alive files whose deletion orphans other files.
  /// Sorted by load descending (the architectural spine first).
  final List<LoadBearingRecord> joints;

  final int aliveLibFiles;
  final int totalLibFiles;
  final int appEntryCount;
  final int testEntryCount;

  /// Whether any app entry (main/bin) was found. When false, reachability is
  /// undefined for this package and nothing is flagged — a pure library's public
  /// surface must not read as dead.
  final bool hasAppEntry;

  int get deadCount => fullyDead.length + testZombies.length;

  Map<String, dynamic> toJson() => {
        'totalLibFiles': totalLibFiles,
        'aliveLibFiles': aliveLibFiles,
        'appEntries': appEntryCount,
        'testEntries': testEntryCount,
        'hasAppEntry': hasAppEntry,
        'fullyDead': [for (final r in fullyDead) r.toJson()],
        'testZombies': [for (final r in testZombies) r.toJson()],
        'joints': [for (final r in joints) r.toJson()],
      };
}

/// Computes [DeadCodeReport] from a set of Dart source files by import-closure
/// reachability. Pure: construct once, call [analyze].
class DeadCodeStrainer {
  DeadCodeStrainer({required this.packageName});

  /// The pubspec package name, used to resolve `package:<name>/…` self-imports
  /// to lib-relative paths. Imports of *other* packages are external and ignored.
  final String packageName;

  /// An `import`/`export`/`part` directive, from the keyword to its terminating
  /// `;` (so a directive wrapped across several lines is captured whole; the
  /// negated class spans newlines). Comments/mid-line text won't match since
  /// `\s*` excludes `/`. We take the entire directive so *every* URI on it is
  /// seen — including the fallbacks of a conditional
  /// `import 'stub.dart' if (cond) 'real.dart'`, all of which must count as
  /// edges or the platform-specific file reads as dead.
  static final RegExp _directiveLine =
      RegExp(r'''^\s*(?:import|export|part)\b[^;]*;''', multiLine: true);

  /// A single- or double-quoted URI within a directive line.
  static final RegExp _quotedUri = RegExp(r'''['"]([^'"]+)['"]''');

  /// A `part of …` directive (quoted URI or legacy dotted name). Marks a file as
  /// a library part rather than an importer.
  static final RegExp _partOf = RegExp(r'''^\s*part\s+of\b''', multiLine: true);

  /// A `/* … */` block comment (across lines). Stripped before directive
  /// scanning so a commented-out `/* import 'x'; */` can't forge an edge.
  static final RegExp _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);

  DeadCodeReport analyze(List<DeadCodeInput> files) {
    // Normalise + index. We only reason about the files we were given; an import
    // that resolves outside the set (dart:, other packages, generated) is simply
    // an edge to nowhere, which is correct — it can't keep a file in our set alive.
    final paths = <String>{};
    final contentByPath = <String, String>{};
    for (final f in files) {
      final norm = _posixNormalize(f.path.replaceAll('\\', '/'));
      paths.add(norm);
      contentByPath[norm] = f.content;
    }

    // A file's lib-relative path (the segment after `lib/`), used for both
    // package-URI resolution and for deciding what counts as a "lib file".
    // Handles a root-package layout (`lib/x.dart`) as well as nested packages
    // (`apps/foo/lib/x.dart`).
    String? libRelOf(String path) {
      if (path.startsWith('lib/')) return path.substring('lib/'.length);
      final i = path.indexOf('/lib/');
      if (i < 0) return null;
      return path.substring(i + '/lib/'.length);
    }

    final byLibRel = <String, String>{};
    for (final path in paths) {
      final rel = libRelOf(path);
      if (rel != null) byLibRel[rel] = path;
    }

    final packagePrefix = 'package:$packageName/';

    // Resolve one directive target (as written in the URI) to a file in our set,
    // or null if it points outside it. `part of` is not an edge here — it names
    // the parent, and we add the parent→part edge from the parent's `part` line.
    String? resolve(String importer, String target) {
      if (target.startsWith('dart:')) return null;
      if (target.startsWith('package:')) {
        if (!target.startsWith(packagePrefix)) return null; // external package
        return byLibRel[target.substring(packagePrefix.length)];
      }
      // Relative to the importer's directory.
      final dir = _posixDirname(importer);
      final resolved = _posixJoin(dir, target);
      return paths.contains(resolved) ? resolved : null;
    }

    // Forward edges: importer → each file it pulls in (import/export/part).
    // Directed toward what a file depends on, so a closure from entries reaches
    // everything the entries transitively use.
    final edges = <String, Set<String>>{for (final path in paths) path: <String>{}};
    final isPartFile = <String>{};
    for (final path in paths) {
      // Strip block comments first: a commented-out `/* import 'x'; */` must not
      // forge an edge. (Line comments already can't — `^\s*` excludes `/`.)
      final content = (contentByPath[path] ?? '').replaceAll(_blockComment, '');
      // `part of …` makes this file a library part; it is reached through its
      // parent's `part` edge, so it never carries its own import edges.
      if (_partOf.hasMatch(content)) isPartFile.add(path);
      for (final line in _directiveLine.allMatches(content)) {
        final full = line.group(0)!;
        if (_partOf.hasMatch(full)) continue; // `part of 'x'` is not a forward edge
        for (final u in _quotedUri.allMatches(full)) {
          final dest = resolve(path, u.group(1)!);
          if (dest != null && dest != path) edges[path]!.add(dest);
        }
      }
    }

    List<String> closureFrom(Iterable<String> entries) {
      final seen = <String>{};
      final stack = <String>[];
      for (final e in entries) {
        if (paths.contains(e) && seen.add(e)) stack.add(e);
      }
      while (stack.isNotEmpty) {
        final node = stack.removeLast();
        for (final next in edges[node]!) {
          if (seen.add(next)) stack.add(next);
        }
      }
      return seen.toList();
    }

    bool isTestPath(String path) =>
        path.contains('/test/') ||
        path.endsWith('_test.dart') ||
        path.contains('/test_driver/') ||
        path.contains('/integration_test/');
    // Generous on entries by design: a false entry only marks *more* code alive
    // (a false negative), which is the safe direction for a review aid — far
    // better than condemning a flavored main's whole subtree. Matches
    // `main.dart`, flavored `main_*.dart` (e.g. `main_dev.dart`), and bin/.
    bool isAppEntry(String path) {
      final name = path.substring(path.lastIndexOf('/') + 1);
      return name == 'main.dart' ||
          (name.startsWith('main_') && name.endsWith('.dart')) ||
          // A package's executables live in a top-level bin/, never lib/bin/.
          (path.contains('/bin/') && !path.contains('/lib/'));
    }

    final appEntries = paths.where(isAppEntry).toList();
    final testEntries = paths.where(isTestPath).toList();
    final hasAppEntry = appEntries.isNotEmpty;
    final appReach = closureFrom(appEntries).toSet();
    final testReach = closureFrom(testEntries).toSet();

    // Classify lib files only (bin/test are entry surfaces, not products), and
    // never flag a `part` file — it has no import edge by design; its liveness
    // rides on its parent, already accounted for via the parent→part edge.
    //
    // Reachability is only meaningful when there is an app entry to reach FROM.
    // A pure library package (no main/bin) would otherwise flag its whole public
    // surface as dead, so we decline to classify it — silence beats a confident
    // false accusation. Such a file counts as alive here.
    final fullyDead = <DeadFileRecord>[];
    final zombies = <DeadFileRecord>[];
    final aliveLibPaths = <String>[];
    var aliveLib = 0;
    var totalLib = 0;
    for (final path in paths) {
      if (libRelOf(path) == null) continue; // not a lib file
      if (isTestPath(path) || isPartFile.contains(path)) continue;
      totalLib++;
      if (!hasAppEntry || appReach.contains(path)) {
        aliveLib++;
        if (hasAppEntry) aliveLibPaths.add(path);
      } else if (testReach.contains(path)) {
        zombies.add(DeadFileRecord(path: path, category: DeadCodeCategory.testZombie));
      } else {
        fullyDead.add(DeadFileRecord(path: path, category: DeadCodeCategory.fullyDead));
      }
    }
    fullyDead.sort((a, b) => a.path.compareTo(b.path));
    zombies.sort((a, b) => a.path.compareTo(b.path));

    // Load-bearing joints: for each alive file, how many OTHER files it singly
    // holds alive (dominator-tree subtree size). Binary reachability stays the
    // source of truth for dead/alive; this surfaces the architectural spine —
    // the rare files whose deletion cascades. (Most files hold 0, a handful
    // hold many.)
    final joints = <LoadBearingRecord>[];
    if (aliveLibPaths.isNotEmpty) {
      final nodeList = paths.toList();
      final indexOf = <String, int>{
        for (var i = 0; i < nodeList.length; i++) nodeList[i]: i,
      };
      final adj = [
        for (final node in nodeList)
          [for (final dst in edges[node]!) indexOf[dst]!],
      ];
      final load = _dominatorLoad(
          nodeList.length, adj, {for (final e in appEntries) indexOf[e]!});
      for (final path in aliveLibPaths) {
        final l = load[indexOf[path]!];
        if (l >= 2) joints.add(LoadBearingRecord(path: path, load: l));
      }
      joints.sort((a, b) => b.load.compareTo(a.load));
    }

    return DeadCodeReport(
      fullyDead: fullyDead,
      testZombies: zombies,
      joints: joints,
      aliveLibFiles: aliveLib,
      totalLibFiles: totalLib,
      appEntryCount: appEntries.length,
      testEntryCount: testEntries.length,
      hasAppEntry: hasAppEntry,
    );
  }
}
