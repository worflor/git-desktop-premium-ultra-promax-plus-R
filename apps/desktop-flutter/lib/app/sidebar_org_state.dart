import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

sealed class SidebarNode {
  const SidebarNode();
}

class SidebarGroup extends SidebarNode {
  final String id;
  String? label;
  String? headRepoPath;
  int? colorSlot;
  bool collapsed;
  final List<SidebarNode> children;

  SidebarGroup({
    required this.id,
    this.label,
    this.headRepoPath,
    this.colorSlot,
    this.collapsed = false,
    List<SidebarNode>? children,
  }) : children = children ?? [];

  int get descendantCount {
    var count = 0;
    for (final c in children) {
      count++;
      if (c is SidebarGroup) count += c.descendantCount;
    }
    return count;
  }
}

class SidebarRepo extends SidebarNode {
  final String path;
  const SidebarRepo(this.path);
}

class SidebarOrgState extends ChangeNotifier {
  List<SidebarNode> _roots = [];
  Future<void> _saveQueue = Future.value();

  List<SidebarNode> get roots => _roots;

  Set<String> get organizedPaths {
    final result = <String>{};
    void walk(List<SidebarNode> nodes) {
      for (final n in nodes) {
        switch (n) {
          case SidebarRepo(:final path):
            result.add(path);
          case SidebarGroup(:final headRepoPath, :final children):
            if (headRepoPath != null) result.add(headRepoPath);
            walk(children);
        }
      }
    }

    walk(_roots);
    return result;
  }

  bool get isEmpty => _roots.isEmpty;

  // ── Queries ───────────────────────────────────────────────────

  SidebarGroup? findGroup(String id, [List<SidebarNode>? nodes]) {
    for (final n in nodes ?? _roots) {
      if (n is SidebarGroup) {
        if (n.id == id) return n;
        final found = findGroup(id, n.children);
        if (found != null) return found;
      }
    }
    return null;
  }

  (List<SidebarNode>, int)? _locate(
    bool Function(SidebarNode) test, [
    List<SidebarNode>? nodes,
  ]) {
    final list = nodes ?? _roots;
    for (var i = 0; i < list.length; i++) {
      if (test(list[i])) return (list, i);
      if (list[i] is SidebarGroup) {
        final found = _locate(test, (list[i] as SidebarGroup).children);
        if (found != null) return found;
      }
    }
    return null;
  }

  SidebarNode? _remove(
    bool Function(SidebarNode) test, [
    List<SidebarNode>? nodes,
  ]) {
    final list = nodes ?? _roots;
    for (var i = 0; i < list.length; i++) {
      if (test(list[i])) return list.removeAt(i);
      if (list[i] is SidebarGroup) {
        final found = _remove(test, (list[i] as SidebarGroup).children);
        if (found != null) return found;
      }
    }
    return null;
  }

  int? inheritedColor(String path) {
    int? walk(List<SidebarNode> nodes, int? parentColor) {
      for (final n in nodes) {
        if (n is SidebarRepo && n.path == path) return parentColor;
        if (n is SidebarGroup) {
          if (n.headRepoPath == path) return n.colorSlot ?? parentColor;
          final found = walk(n.children, n.colorSlot ?? parentColor);
          if (found != null) return found;
        }
      }
      return null;
    }

    return walk(_roots, null);
  }

  SidebarNode? _removeByPath(String path) {
    final asRepo = _remove((n) => n is SidebarRepo && n.path == path);
    if (asRepo != null) return asRepo;
    final loc = _locate((n) => n is SidebarGroup && n.headRepoPath == path);
    if (loc == null) return null;
    final (parentList, index) = loc;
    final group = parentList.removeAt(index) as SidebarGroup;
    parentList.insertAll(index, group.children);
    return group;
  }

  // ── Mutations ─────────────────────────────────────────────────

  void anchorRepo(String path) {
    if (organizedPaths.contains(path)) return;
    _roots.add(SidebarRepo(path));
    _save();
    notifyListeners();
  }

  void unanchorRepo(String path) {
    var found = _remove((n) => n is SidebarRepo && n.path == path);
    if (found == null) {
      final loc = _locate((n) => n is SidebarGroup && n.headRepoPath == path);
      if (loc != null) {
        final (parentList, index) = loc;
        final group = parentList.removeAt(index) as SidebarGroup;
        parentList.insertAll(index, group.children);
        found = group;
      }
    }
    if (found != null) {
      _pruneEmpty();
      _save();
      notifyListeners();
    }
  }

  void makeGroupHead(String repoPath) {
    _removeByPath(repoPath);
    _roots.add(SidebarGroup(
      id: _newId(),
      headRepoPath: repoPath,
    ));
    _save();
    notifyListeners();
  }

  void addToGroup(String repoPath, String groupId, {int? index}) {
    if (organizedPaths.contains(repoPath)) {
      _removeByPath(repoPath);
    }
    final group = findGroup(groupId);
    if (group == null) return;
    group.children
        .insert(index ?? group.children.length, SidebarRepo(repoPath));
    _save();
    notifyListeners();
  }

  void nestUnder(String sourcePath, String targetPath) {
    if (sourcePath == targetPath) return;
    _removeByPath(sourcePath);

    final groupLoc =
        _locate((n) => n is SidebarGroup && n.headRepoPath == targetPath);
    if (groupLoc != null) {
      (groupLoc.$1[groupLoc.$2] as SidebarGroup)
          .children
          .insert(0, SidebarRepo(sourcePath));
      _pruneEmpty();
      _save();
      notifyListeners();
      return;
    }

    final repoLoc = _locate((n) => n is SidebarRepo && n.path == targetPath);
    if (repoLoc != null) {
      final (parentList, index) = repoLoc;
      parentList[index] = SidebarGroup(
        id: _newId(),
        headRepoPath: targetPath,
        children: [SidebarRepo(sourcePath)],
      );
      _pruneEmpty();
      _save();
      notifyListeners();
      return;
    }

    _roots.add(SidebarGroup(
      id: _newId(),
      headRepoPath: targetPath,
      children: [SidebarRepo(sourcePath)],
    ));
    _save();
    notifyListeners();
  }

  void moveToTopLevel(String repoPath, {int? index}) {
    _removeByPath(repoPath);
    _roots.insert(index ?? _roots.length, SidebarRepo(repoPath));
    _pruneEmpty();
    _save();
    notifyListeners();
  }

  void insertBefore(String sourcePath, String targetPath) {
    _removeByPath(sourcePath);
    final loc = _locate((n) => n is SidebarRepo && n.path == targetPath);
    if (loc != null) {
      final (list, index) = loc;
      list.insert(index, SidebarRepo(sourcePath));
    } else {
      _roots.add(SidebarRepo(sourcePath));
    }
    _pruneEmpty();
    _save();
    notifyListeners();
  }

  void insertBeforeGroup(String sourcePath, String groupId) {
    _removeByPath(sourcePath);
    final loc = _locate((n) => n is SidebarGroup && n.id == groupId);
    if (loc != null) {
      final (list, index) = loc;
      list.insert(index, SidebarRepo(sourcePath));
    } else {
      _roots.add(SidebarRepo(sourcePath));
    }
    _pruneEmpty();
    _save();
    notifyListeners();
  }

  void insertIntoGroup(String sourcePath, String groupId) {
    _removeByPath(sourcePath);
    final group = findGroup(groupId);
    if (group == null) return;
    group.children.insert(0, SidebarRepo(sourcePath));
    _pruneEmpty();
    _save();
    notifyListeners();
  }

  void createGroupFromDrop(String headPath, String childPath) {
    _removeByPath(headPath);
    _removeByPath(childPath);
    final group = SidebarGroup(
      id: _newId(),
      headRepoPath: headPath,
      children: [SidebarRepo(childPath)],
    );
    _roots.add(group);
    _save();
    notifyListeners();
  }

  void createEmptyGroup({String? label, int? index}) {
    final group = SidebarGroup(id: _newId(), label: label);
    _roots.insert(index ?? _roots.length, group);
    _save();
    notifyListeners();
  }

  void toggleCollapsed(String groupId) {
    final group = findGroup(groupId);
    if (group == null) return;
    group.collapsed = !group.collapsed;
    _save();
    notifyListeners();
  }

  void setGroupColor(String groupId, int? slot) {
    final group = findGroup(groupId);
    if (group == null) return;
    group.colorSlot = slot;
    _save();
    notifyListeners();
  }

  void cycleGroupColor(String groupId) {
    final group = findGroup(groupId);
    if (group == null) return;
    final current = group.colorSlot;
    group.colorSlot = current == null ? 0 : (current + 1) % _tintSlots;
    _save();
    notifyListeners();
  }

  void clearGroupColor(String groupId) {
    setGroupColor(groupId, null);
  }

  void setGroupLabel(String groupId, String? label) {
    final group = findGroup(groupId);
    if (group == null) return;
    group.label = label?.isEmpty == true ? null : label;
    _save();
    notifyListeners();
  }

  void dissolveGroup(String groupId) {
    final loc = _locate((n) => n is SidebarGroup && n.id == groupId);
    if (loc == null) return;
    final (parentList, index) = loc;
    final group = parentList[index] as SidebarGroup;
    parentList.removeAt(index);
    if (group.headRepoPath != null) {
      parentList.insert(index, SidebarRepo(group.headRepoPath!));
    }
    parentList.insertAll(
      index + (group.headRepoPath != null ? 1 : 0),
      group.children,
    );
    _save();
    notifyListeners();
  }

  void removeGroup(String groupId) {
    final loc = _locate((n) => n is SidebarGroup && n.id == groupId);
    if (loc == null) return;
    final (parentList, index) = loc;
    parentList.removeAt(index);
    _save();
    notifyListeners();
  }

  void reorder(String? parentGroupId, int oldIndex, int newIndex) {
    final list =
        parentGroupId == null ? _roots : findGroup(parentGroupId)?.children;
    if (list == null) return;
    if (oldIndex < 0 || oldIndex >= list.length) return;
    final adjusted = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (adjusted < 0 || adjusted >= list.length || adjusted == oldIndex) return;
    final item = list.removeAt(oldIndex);
    list.insert(adjusted, item);
    _save();
    notifyListeners();
  }

  void forgetRepo(String path) {
    _removeByPath(path);
    _pruneEmpty();
    _save();
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────

  void _pruneEmpty([List<SidebarNode>? nodes]) {
    final list = nodes ?? _roots;
    for (var i = list.length - 1; i >= 0; i--) {
      final n = list[i];
      if (n is! SidebarGroup) continue;
      _pruneEmpty(n.children);
      if (n.children.isNotEmpty) continue;
      if (n.headRepoPath != null) {
        list[i] = SidebarRepo(n.headRepoPath!);
      } else if (n.label == null) {
        list.removeAt(i);
      }
    }
  }

  static const _tintSlots = 5;
  static int _idSeq = 0;
  static String _newId() =>
      'g${DateTime.now().millisecondsSinceEpoch}_${_idSeq++}';

  // ── Persistence ───────────────────────────────────────────────

  static const _prefsKey = 'sidebar_org';

  Future<void> load() async {
    await _flushPendingSave();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final json = jsonDecode(raw);
        if (json is List) _roots = _nodesFromJson(json);
      } catch (e) {
        debugPrint('[SidebarOrg] parse error: $e');
      }
    }
    _pruneEmpty();
    notifyListeners();
  }

  void _save() {
    final json = jsonEncode(_nodesToJson(_roots));
    _saveQueue = _saveQueue.catchError((Object e) {
      debugPrint('[SidebarOrg] save queue error: $e');
    }).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, json);
    }).catchError((Object e) {
      debugPrint('[SidebarOrg] save error: $e');
    });
  }

  Future<void> _flushPendingSave() => _saveQueue;

  @visibleForTesting
  Future<void> flushPendingSaveForTesting() => _flushPendingSave();

  static SidebarNode? _nodeFromJson(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == 'repo') {
      final path = m['path'];
      if (path is! String || path.isEmpty) return null;
      return SidebarRepo(path);
    }
    if (type == 'group') {
      return SidebarGroup(
        id: m['id'] as String? ?? _newId(),
        label: m['label'] as String?,
        headRepoPath: m['headRepoPath'] as String?,
        colorSlot: m['colorSlot'] as int?,
        collapsed: m['collapsed'] as bool? ?? false,
        children:
            m['children'] is List ? _nodesFromJson(m['children'] as List) : [],
      );
    }
    return null;
  }

  static List<SidebarNode> _nodesFromJson(List<dynamic> json) {
    final result = <SidebarNode>[];
    for (final item in json) {
      if (item is Map<String, dynamic>) {
        final node = _nodeFromJson(item);
        if (node != null) result.add(node);
      }
    }
    return result;
  }

  static List<Map<String, dynamic>> _nodesToJson(List<SidebarNode> nodes) {
    return nodes.map((n) {
      if (n is SidebarRepo) {
        return <String, dynamic>{'type': 'repo', 'path': n.path};
      }
      final g = n as SidebarGroup;
      return <String, dynamic>{
        'type': 'group',
        'id': g.id,
        if (g.label != null) 'label': g.label,
        if (g.headRepoPath != null) 'headRepoPath': g.headRepoPath,
        if (g.colorSlot != null) 'colorSlot': g.colorSlot,
        if (g.collapsed) 'collapsed': true,
        if (g.children.isNotEmpty) 'children': _nodesToJson(g.children),
      };
    }).toList();
  }
}
