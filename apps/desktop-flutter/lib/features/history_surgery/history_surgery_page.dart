import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/logos_git_state.dart';
import '../../backend/history_surgery.dart';
import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import 'surgery_state.dart';

// ---------------------------------------------------------------------------
// Loader — fetches engine, creates state, pushes to main page
// ---------------------------------------------------------------------------

class HistorySurgeryLoader extends StatefulWidget {
  final String repoPath;
  final bool dryRun;
  const HistorySurgeryLoader({
    super.key,
    required this.repoPath,
    this.dryRun = false,
  });

  @override
  State<HistorySurgeryLoader> createState() => _HistorySurgeryLoaderState();
}

class _HistorySurgeryLoaderState extends State<HistorySurgeryLoader> {
  SurgeryState? _state;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state != null) return;
    final engine = context.read<LogosGitState>().engineFor(widget.repoPath);
    _state = SurgeryState(
      repoPath: widget.repoPath,
      engine: engine,
      dryRun: widget.dryRun,
    );
  }

  @override
  void dispose() {
    _state?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _state;
    if (s == null) return const SizedBox.shrink();
    return ChangeNotifierProvider.value(
      value: s,
      child: const _HistorySurgeryPage(),
    );
  }
}

// ---------------------------------------------------------------------------
// Main page — scaffold + phase switcher
// ---------------------------------------------------------------------------

class _HistorySurgeryPage extends StatelessWidget {
  const _HistorySurgeryPage();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<SurgeryState>();
    final geo = context.surfaceShader.geometry;

    return Scaffold(
      backgroundColor: t.bg0,
      body: Focus(
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (state.phase == SurgeryPhase.select) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
            if (state.phase.index <= SurgeryPhase.confirm.index) {
              state.goBack();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Column(
          children: [
            _SurgeryChrome(state: state, tokens: t, geo: geo),
            Expanded(
              child: AnimatedSwitcher(
                duration: context.motion(AppMotion.fade),
                switchInCurve: AppMotion.fadeCurve,
                switchOutCurve: AppMotion.fadeCurve,
                child: _buildPhase(state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhase(SurgeryState state) {
    switch (state.phase) {
      case SurgeryPhase.select:
        return _SelectPhase(key: const ValueKey('select'));
      case SurgeryPhase.understand:
        return _UnderstandPhase(key: const ValueKey('understand'));
      case SurgeryPhase.confirm:
        return _ConfirmPhase(key: const ValueKey('confirm'));
      case SurgeryPhase.execute:
        return _ExecutePhase(key: const ValueKey('execute'));
      case SurgeryPhase.verify:
        return _VerifyPhase(key: const ValueKey('verify'));
    }
  }
}

// ---------------------------------------------------------------------------
// Chrome — title bar with phase dots
// ---------------------------------------------------------------------------

class _SurgeryChrome extends StatelessWidget {
  final SurgeryState state;
  final AppTokens tokens;
  final SurfaceMaterialGeometry geo;
  const _SurgeryChrome({
    required this.state,
    required this.tokens,
    required this.geo,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          Text(
            'History Surgery',
            style: TextStyle(
              color: t.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: AppFonts.mono,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'alpha',
            style: TextStyle(
              color: t.textFaint,
              fontSize: 9,
              fontFamily: AppFonts.mono,
            ),
          ),
          if (state.dryRun) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: t.stateModified.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(geo.badgeRadius),
                border: Border.all(
                    color: t.stateModified.withValues(alpha: 0.3)),
              ),
              child: Text(
                'DRY RUN',
                style: TextStyle(
                  color: t.stateModified,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ),
          ],
          const SizedBox(width: 16),
          for (final phase in SurgeryPhase.values) ...[
            _PhaseDot(
              active: phase == state.phase,
              completed: phase.index < state.phase.index,
              tokens: t,
            ),
            if (phase != SurgeryPhase.verify) const SizedBox(width: 6),
          ],
          const Spacer(),
          if (state.phase != SurgeryPhase.execute)
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Icon(
                  Icons.close,
                  size: 16,
                  color: t.textMuted,
                ),
              ),
            )
          else
            Icon(Icons.close, size: 16,
                color: t.chromeBorder.withValues(alpha: 0.15)),
        ],
      ),
    );
  }
}

class _PhaseDot extends StatelessWidget {
  final bool active;
  final bool completed;
  final AppTokens tokens;
  const _PhaseDot({
    required this.active,
    required this.completed,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: active ? 10 : 6,
      height: active ? 10 : 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: completed
            ? tokens.accentBright.withValues(alpha: 0.6)
            : active
                ? tokens.accentBright
                : tokens.chromeBorder.withValues(alpha: 0.3),
        border: active
            ? Border.all(color: tokens.accentBright.withValues(alpha: 0.4), width: 2)
            : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 1: Select files to purge
// ---------------------------------------------------------------------------

class _DirNode {
  String name;
  String fullPath;
  final Map<String, _DirNode> children = {};
  final List<String> files = [];
  bool expanded = false;
  _DirNode({this.name = '', this.fullPath = ''});
}

_DirNode _buildTree(List<String> paths) {
  final root = _DirNode();
  for (final path in paths) {
    final parts = path.split('/');
    var node = root;
    for (var i = 0; i < parts.length - 1; i++) {
      final dir = parts[i];
      final dirPath = parts.sublist(0, i + 1).join('/');
      node = node.children.putIfAbsent(
          dir, () => _DirNode(name: dir, fullPath: dirPath));
    }
    node.files.add(path);
  }
  return root;
}

class _SelectPhase extends StatefulWidget {
  const _SelectPhase({super.key});
  @override
  State<_SelectPhase> createState() => _SelectPhaseState();
}

class _SelectPhaseState extends State<_SelectPhase> {
  List<String> _allFiles = [];
  _DirNode? _tree;
  String _filter = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFileList();
  }

  Future<void> _loadFileList() async {
    final state = context.read<SurgeryState>();
    final r = await Process.run(
      'git', ['ls-tree', '-r', 'HEAD', '--name-only'],
      workingDirectory: state.repoPath,
    );
    if (!mounted) return;
    final files = r.stdout.toString().trim().split('\n')
        .where((s) => s.isNotEmpty)
        .toList()
      ..sort();
    setState(() {
      _allFiles = files;
      _tree = _buildTree(files);
      _loading = false;
    });
  }

  List<String> get _filteredFiles {
    if (_filter.isEmpty) return _allFiles;
    final lower = _filter.toLowerCase();
    return _allFiles.where((f) => f.toLowerCase().contains(lower)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<SurgeryState>();
    final geo = context.surfaceShader.geometry;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Select files to remove from history',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 11,
                  fontFamily: AppFonts.mono,
                ),
              ),
              const Spacer(),
              if (state.selectedPaths.isNotEmpty)
                Text(
                  '${state.selectedPaths.length} selected',
                  style: TextStyle(
                    color: t.stateDeleted.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.mono,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 28,
            child: TextField(
              style: TextStyle(
                color: t.textNormal, fontSize: 11, fontFamily: AppFonts.mono,
              ),
              decoration: InputDecoration(
                hintText: 'search...',
                hintStyle: TextStyle(color: t.textFaint, fontSize: 11),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 6),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Icon(Icons.search, size: 13, color: t.textFaint),
                ),
                prefixIconConstraints: const BoxConstraints(
                    minWidth: 24, minHeight: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(geo.badgeRadius),
                  borderSide: BorderSide(
                      color: t.chromeBorder.withValues(alpha: 0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(geo.badgeRadius),
                  borderSide: BorderSide(
                      color: t.chromeBorder.withValues(alpha: 0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(geo.badgeRadius),
                  borderSide: BorderSide(
                      color: t.accentBright.withValues(alpha: 0.5)),
                ),
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: _loading
                      ? Center(child: Text('reading tree...',
                          style: TextStyle(color: t.textFaint, fontSize: 11,
                              fontFamily: AppFonts.mono)))
                      : _filter.isNotEmpty
                          ? _FilteredList(
                              files: _filteredFiles,
                              state: state,
                              tokens: t,
                            )
                          : _tree != null
                              ? _TreeView(
                                  root: _tree!,
                                  state: state,
                                  tokens: t,
                                  onToggle: () => setState(() {}),
                                )
                              : const SizedBox.shrink(),
                ),
                if (state.selectedPaths.isNotEmpty) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 3,
                    child: _PurgePanel(state: state, tokens: t, geo: geo),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: _ActionBtn(
              label: state.selectedPaths.isEmpty
                  ? 'select files to continue'
                  : 'continue →',
              onTap: state.canAdvance() ? () => state.advance() : null,
              accent: state.canAdvance(),
              tokens: t,
              geo: geo,
            ),
          ),
        ],
      ),
    );
  }
}

class _TreeView extends StatelessWidget {
  final _DirNode root;
  final SurgeryState state;
  final AppTokens tokens;
  final VoidCallback onToggle;
  const _TreeView({
    required this.root,
    required this.state,
    required this.tokens,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        for (final file in root.files)
          _FileRow(path: file, state: state, tokens: tokens, depth: 0),
        for (final dir in root.children.values.toList()
          ..sort((a, b) => a.name.compareTo(b.name)))
          _DirSubtree(
            node: dir, state: state, tokens: tokens,
            depth: 0, onToggle: onToggle,
          ),
      ],
    );
  }
}

class _DirSubtree extends StatelessWidget {
  final _DirNode node;
  final SurgeryState state;
  final AppTokens tokens;
  final int depth;
  final VoidCallback onToggle;
  const _DirSubtree({
    required this.node,
    required this.state,
    required this.tokens,
    required this.depth,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            node.expanded = !node.expanded;
            onToggle();
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: EdgeInsets.only(
                left: 8.0 + depth * 14.0, top: 3, bottom: 3, right: 8),
              child: Row(
                children: [
                  Icon(
                    node.expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.chevron_right,
                    size: 13,
                    color: t.textFaint,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${node.name}/',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppFonts.mono,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (node.expanded) ...[
          for (final file in node.files)
            _FileRow(
              path: file, state: state, tokens: t, depth: depth + 1,
            ),
          for (final child in node.children.values.toList()
            ..sort((a, b) => a.name.compareTo(b.name)))
            _DirSubtree(
              node: child, state: state, tokens: t,
              depth: depth + 1, onToggle: onToggle,
            ),
        ],
      ],
    );
  }
}

class _FileRow extends StatefulWidget {
  final String path;
  final SurgeryState state;
  final AppTokens tokens;
  final int depth;
  const _FileRow({
    required this.path,
    required this.state,
    required this.tokens,
    required this.depth,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final selected = widget.state.selectedPaths.contains(widget.path);
    final name = widget.path.split('/').last;
    return GestureDetector(
      onTap: () {
        if (selected) {
          widget.state.removePath(widget.path);
        } else {
          widget.state.addPath(widget.path);
        }
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Container(
          padding: EdgeInsets.only(
            left: 22.0 + widget.depth * 14.0, top: 3, bottom: 3, right: 8),
          color: selected
              ? t.stateDeleted.withValues(alpha: 0.06)
              : _hovered
                  ? t.itemHoverBg.withValues(alpha: 0.5)
                  : Colors.transparent,
          child: Text(
            name,
            style: TextStyle(
              color: selected ? t.stateDeleted : t.textNormal,
              fontSize: 11,
              fontFamily: AppFonts.mono,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _FilteredList extends StatelessWidget {
  final List<String> files;
  final SurgeryState state;
  final AppTokens tokens;
  const _FilteredList({
    required this.files,
    required this.state,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: files.length,
      itemBuilder: (_, i) => _FileRow(
        path: files[i], state: state, tokens: tokens, depth: 0,
      ),
    );
  }
}

class _PurgePanel extends StatelessWidget {
  final SurgeryState state;
  final AppTokens tokens;
  final SurfaceMaterialGeometry geo;
  const _PurgePanel({
    required this.state,
    required this.tokens,
    required this.geo,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.bg0.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(geo.cardRadius),
        border: Border.all(
            color: t.stateDeleted.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.delete_outline, size: 12,
                  color: t.stateDeleted.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
              Text(
                '${state.selectedPaths.length} to purge',
                style: TextStyle(
                  color: t.stateDeleted.withValues(alpha: 0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                for (final path in state.selectedPaths)
                  _PurgeItem(
                    path: path,
                    renames: state.renameChains[path] ?? {},
                    tokens: t,
                    onRemove: () => state.removePath(path),
                  ),
              ],
            ),
          ),
          if (state.impact != null) ...[
            Container(
              height: 1,
              color: t.chromeBorder.withValues(alpha: 0.10),
              margin: const EdgeInsets.symmetric(vertical: 8),
            ),
            if (state.impact != null)
              _InlineImpact(impact: state.impact!, tokens: t),
          ],
          if (state.analyzing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('analyzing...',
                style: TextStyle(color: t.textFaint, fontSize: 9,
                    fontFamily: AppFonts.mono, fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }
}

class _InlineImpact extends StatelessWidget {
  final SurgeryImpact impact;
  final AppTokens tokens;
  const _InlineImpact({required this.impact, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final ratio = impact.affectedRatio;
    final riskColor = ratio < 0.1 ? t.stateAdded
        : ratio < 0.3 ? t.stateModified
        : t.stateDeleted;

    final risk = ratio < 0.1 ? 'low risk'
        : ratio < 0.3 ? 'moderate risk'
        : 'high risk';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(risk, style: TextStyle(
            color: riskColor,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: AppFonts.mono,
          )),
        ),
        _ImpactRow('commits', '${impact.affectedCommits}/${impact.totalCommits}', t,
            color: riskColor),
        if (impact.affectedBranches.isNotEmpty)
          _ImpactRow('branches', impact.affectedBranches.length.toString(), t),
        if (impact.affectedWorktrees.isNotEmpty)
          _ImpactRow('worktrees', impact.affectedWorktrees.length.toString(), t,
              color: t.stateModified),
        if (impact.couplingNeighbors.isEmpty)
          _ImpactRow('coupling', 'island', t, color: t.textFaint)
        else
          _ImpactRow('coupling',
              '${impact.couplingNeighbors.length} neighbors', t),
      ],
    );
  }
}

class _ImpactRow extends StatelessWidget {
  final String label;
  final String value;
  final AppTokens tokens;
  final Color? color;
  const _ImpactRow(this.label, this.value, this.tokens, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(
            color: tokens.textFaint, fontSize: 9, fontFamily: AppFonts.mono,
          )),
          Text(value, style: TextStyle(
            color: color ?? tokens.textMuted, fontSize: 9,
            fontFamily: AppFonts.mono, fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}

class _PurgeItem extends StatefulWidget {
  final String path;
  final Set<String> renames;
  final AppTokens tokens;
  final VoidCallback onRemove;
  const _PurgeItem({
    required this.path,
    required this.renames,
    required this.tokens,
    required this.onRemove,
  });

  @override
  State<_PurgeItem> createState() => _PurgeItemState();
}

class _PurgeItemState extends State<_PurgeItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final name = widget.path.split('/').last;
    final dir = widget.path.contains('/')
        ? widget.path.substring(0, widget.path.lastIndexOf('/'))
        : '';
    final otherPaths = widget.renames.where((r) => r != widget.path).toList();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: t.textNormal,
                      fontSize: 11,
                      fontFamily: AppFonts.mono,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (dir.isNotEmpty)
                    Text(
                      dir,
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 9,
                        fontFamily: AppFonts.mono,
                      ),
                    ),
                  for (final rp in otherPaths)
                    Text(
                      '← $rp',
                      style: TextStyle(
                        color: t.stateModified.withValues(alpha: 0.5),
                        fontSize: 9,
                        fontFamily: AppFonts.mono,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            if (_hovered)
              GestureDetector(
                onTap: widget.onRemove,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(Icons.close, size: 11,
                      color: t.textFaint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 2: Understand — what will happen and how it works
// ---------------------------------------------------------------------------

class _UnderstandPhase extends StatelessWidget {
  const _UnderstandPhase({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<SurgeryState>();
    final geo = context.surfaceShader.geometry;
    final impact = state.impact;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How this works',
            style: TextStyle(
              color: t.textStrong,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: AppFonts.mono,
            ),
          ),
          const SizedBox(height: 16),
          _ExplainBlock(
            num: '1',
            title: 'Backup',
            body: 'Every branch and tag ref is copied to a backup namespace '
                'before anything changes. If something goes wrong, one click '
                'restores the original state.',
            tokens: t,
          ),
          _ExplainBlock(
            num: '2',
            title: 'Rewrite',
            body: 'Each commit is walked from root to tip. For every commit '
                'that contains the target files, a new commit is created with '
                'those files removed from the tree. Parent chains are '
                'remapped to preserve topology. '
                '${impact != null ? '${impact.affectedCommits} of ${impact.totalCommits} commits will be rewritten.' : ''}',
            tokens: t,
          ),
          _ExplainBlock(
            num: '3',
            title: 'Update refs',
            body: 'Branch and tag pointers are moved to the new commit SHAs. '
                'The old objects still exist until garbage collection. '
                '${impact != null && impact.affectedWorktrees.isNotEmpty
                    ? 'Your ${impact.affectedWorktrees.length} worktree(s) will need re-checkout.'
                    : 'No worktrees are affected.'}',
            tokens: t,
          ),
          _ExplainBlock(
            num: '4',
            title: 'Force-push',
            body: 'After verifying the purge, you choose which branches to '
                'force-push. Uses --force-with-lease so it fails safely if '
                'someone else pushed in the meantime.',
            tokens: t,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surface0.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(geo.cardRadius),
              border: Border.all(
                  color: t.chromeBorder.withValues(alpha: 0.12)),
            ),
            child: Text(
              'Unlike filter-repo or BFG, this runs entirely through git '
              'plumbing commands (cat-file, mktree, commit-tree, update-ref). '
              'No external dependencies. Rename tracking follows one chain '
              'per file — if a file was copied and both copies renamed '
              'independently, verify the purge result after execution.',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: AppFonts.mono,
                height: 1.5,
              ),
            ),
          ),
          const Spacer(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _ActionBtn(
                label: '← Back',
                onTap: () => state.goBack(),
                tokens: t,
                geo: geo,
              ),
              _ActionBtn(
                label: 'I understand, continue →',
                onTap: () => state.advance(),
                accent: true,
                tokens: t,
                geo: geo,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExplainBlock extends StatelessWidget {
  final String num;
  final String title;
  final String body;
  final AppTokens tokens;
  const _ExplainBlock({
    required this.num,
    required this.title,
    required this.body,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            child: Text(
              num,
              style: TextStyle(
                color: t.accentBright.withValues(alpha: 0.5),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFonts.mono,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: AppFonts.mono,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 3: Confirmation Gate
// ---------------------------------------------------------------------------

class _ConfirmPhase extends StatelessWidget {
  const _ConfirmPhase({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<SurgeryState>();
    final impact = state.impact;
    if (impact == null) {
      return const SizedBox.shrink();
    }
    final geo = context.surfaceShader.geometry;

    final items = <String>[
      '${impact.affectedCommits} commits will be rewritten',
      'Force-push will be required for remote branches',
    ];
    if (impact.affectedWorktrees.isNotEmpty) {
      items.add('${impact.affectedWorktrees.length} worktrees will need re-checkout');
    }
    if (impact.affectedStashIndices.isNotEmpty) {
      items.add('${impact.affectedStashIndices.length} stashes may become invalid');
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 32,
                color: t.stateDeleted.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              'This operation rewrites git history',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'It cannot be automatically undone after force-pushing.',
              style: TextStyle(color: t.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 20),
            for (var i = 0; i < items.length; i++)
              GestureDetector(
                onTap: () => state.toggleCheckbox(i),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                                geo.badgeRadius),
                            border: Border.all(
                              color: i < state.checkboxes.length &&
                                      state.checkboxes[i]
                                  ? t.accentBright
                                  : t.chromeBorder,
                            ),
                            color: i < state.checkboxes.length &&
                                    state.checkboxes[i]
                                ? t.accentBright.withValues(alpha: 0.15)
                                : Colors.transparent,
                          ),
                          child: i < state.checkboxes.length &&
                                  state.checkboxes[i]
                              ? Icon(Icons.check, size: 10,
                                  color: t.accentBright)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          items[i],
                          style: TextStyle(
                            color: t.textNormal,
                            fontSize: 11,
                            fontFamily: AppFonts.mono,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 20),
            SizedBox(
              width: 200,
              child: TextField(
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12,
                  fontFamily: AppFonts.mono,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  hintText: 'type PURGE',
                  hintStyle: TextStyle(
                    color: t.textFaint.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontFamily: AppFonts.mono,
                    letterSpacing: 2,
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(geo.badgeRadius),
                    borderSide: BorderSide(color: t.chromeBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(geo.badgeRadius),
                    borderSide: BorderSide(
                        color: t.stateDeleted.withValues(alpha: 0.3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(geo.badgeRadius),
                    borderSide: BorderSide(color: t.stateDeleted),
                  ),
                ),
                onChanged: (v) => state.setConfirmationText(v),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ActionBtn(
                  label: 'Go Back',
                  onTap: () => state.goBack(),
                  tokens: t,
                  geo: geo,
                ),
                const SizedBox(width: 12),
                _ActionBtn(
                  label: 'Begin Surgery',
                  onTap: state.confirmationComplete
                      ? () => state.advance()
                      : null,
                  danger: true,
                  tokens: t,
                  geo: geo,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 4: Execution Monitor
// ---------------------------------------------------------------------------

class _ExecutePhase extends StatelessWidget {
  const _ExecutePhase({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<SurgeryState>();
    final progress = state.progress;

    final ratio = progress != null && progress.total > 0
        ? progress.processed / progress.total
        : 0.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              progress?.phase ?? 'Preparing...',
              style: TextStyle(
                color: t.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio.clamp(0, 1).toDouble(),
                backgroundColor: t.chromeBorder.withValues(alpha: 0.15),
                color: t.stateDeleted.withValues(alpha: 0.7),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 8),
            if (progress != null)
              Text(
                '${progress.processed} / ${progress.total}'
                '${progress.currentHash != null ? '  ${progress.currentHash}' : ''}',
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 10,
                  fontFamily: AppFonts.mono,
                ),
              ),
            if (state.executeError != null) ...[
              const SizedBox(height: 12),
              Text(
                state.executeError!,
                style: TextStyle(color: t.stateDeleted, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Phase 5: Post-Rewrite Report
// ---------------------------------------------------------------------------

class _VerifyPhase extends StatefulWidget {
  const _VerifyPhase({super.key});
  @override
  State<_VerifyPhase> createState() => _VerifyPhaseState();
}

class _VerifyPhaseState extends State<_VerifyPhase> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SurgeryState>().verifyPurge();
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<SurgeryState>();
    final result = state.result;
    final geo = context.surfaceShader.geometry;

    if (result == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                size: 20,
                color: result.success ? t.stateAdded : t.stateDeleted,
              ),
              const SizedBox(width: 8),
              Text(
                result.success ? 'Surgery Complete' : 'Surgery Failed',
                style: TextStyle(
                  color: result.success ? t.stateAdded : t.stateDeleted,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ],
          ),
          if (result.error != null) ...[
            const SizedBox(height: 8),
            Text(result.error!, style: TextStyle(
              color: t.stateDeleted, fontSize: 11, fontFamily: AppFonts.mono,
            )),
          ],
          const SizedBox(height: 16),
          _ReportLine('Commits rewritten', '${result.commitsRewritten}', t),
          _ReportLine('Refs updated', '${result.refsUpdated}', t),
          _ReportLine('Old HEAD', result.oldHead.length > 7
              ? result.oldHead.substring(0, 7) : result.oldHead, t),
          _ReportLine('New HEAD', result.newHead.length > 7
              ? result.newHead.substring(0, 7) : result.newHead, t),
          if (state.purgeVerified != null)
            _ReportLine('Purge verified',
                state.purgeVerified! ? 'clean' : 'TRACES REMAIN', t,
                color: state.purgeVerified! ? t.stateAdded : t.stateDeleted),
          const SizedBox(height: 16),
          if (result.displacedWorktrees.isNotEmpty) ...[
            Text('Displaced Worktrees', style: TextStyle(
              color: t.textMuted, fontSize: 10, fontWeight: FontWeight.w700,
              fontFamily: AppFonts.mono,
            )),
            const SizedBox(height: 4),
            for (final wt in result.displacedWorktrees)
              Text('  $wt', style: TextStyle(
                color: t.textFaint, fontSize: 10, fontFamily: AppFonts.mono,
              )),
            const SizedBox(height: 12),
          ],
          if (!state.rolledBack) ...[
            Wrap(
              spacing: 8,
              children: [
                _ForcePushGate(state: state, tokens: t, geo: geo),
                _ActionBtn(
                  label: 'Undo Surgery',
                  onTap: () => state.rollback(),
                  tokens: t,
                  geo: geo,
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (state.rolledBack)
            Text('Rolled back to backup refs.', style: TextStyle(
              color: t.stateModified, fontSize: 11, fontFamily: AppFonts.mono,
            )),
          const SizedBox(height: 16),
          _ActionBtn(
            label: 'Done',
            onTap: () => Navigator.of(context).pop(),
            accent: true,
            tokens: t,
            geo: geo,
          ),
        ],
      ),
    );
  }
}

class _ReportLine extends StatelessWidget {
  final String label;
  final String value;
  final AppTokens tokens;
  final Color? color;
  const _ReportLine(this.label, this.value, this.tokens, {this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(
              color: tokens.textFaint, fontSize: 10, fontFamily: AppFonts.mono,
            )),
          ),
          Text(value, style: TextStyle(
            color: color ?? tokens.textNormal, fontSize: 10,
            fontFamily: AppFonts.mono, fontWeight: FontWeight.w600,
          )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared button
// ---------------------------------------------------------------------------

class _ForcePushGate extends StatefulWidget {
  final SurgeryState state;
  final AppTokens tokens;
  final SurfaceMaterialGeometry geo;
  const _ForcePushGate({
    required this.state,
    required this.tokens,
    required this.geo,
  });
  @override
  State<_ForcePushGate> createState() => _ForcePushGateState();
}

class _ForcePushGateState extends State<_ForcePushGate> {
  bool _armed = false;
  bool _pushing = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final geo = widget.geo;
    final state = widget.state;

    if (_pushing) {
      return Text('pushing...', style: TextStyle(
        color: t.stateDeleted.withValues(alpha: 0.6),
        fontSize: 10, fontFamily: AppFonts.mono,
      ));
    }

    if (!_armed) {
      return _ActionBtn(
        label: 'Force Push All',
        onTap: () => setState(() => _armed = true),
        danger: true,
        tokens: t,
        geo: geo,
      );
    }

    final branches = state.impact?.affectedBranches ?? [];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${branches.length} branch${branches.length == 1 ? '' : 'es'} → ',
          style: TextStyle(
            color: t.stateDeleted.withValues(alpha: 0.5),
            fontSize: 9, fontFamily: AppFonts.mono,
          ),
        ),
        _ActionBtn(
          label: 'confirm push',
          onTap: () async {
            setState(() => _pushing = true);
            for (final b in branches) {
              await state.forcePush(b);
              if (state.pushError != null) break;
            }
            if (mounted) setState(() => _pushing = false);
          },
          danger: true,
          tokens: t,
          geo: geo,
        ),
        const SizedBox(width: 6),
        GestureDetector(
          onTap: () => setState(() => _armed = false),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text('cancel', style: TextStyle(
              color: t.textFaint, fontSize: 9, fontFamily: AppFonts.mono,
            )),
          ),
        ),
      ],
    );
  }
}

class _ActionBtn extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool accent;
  final bool danger;
  final AppTokens tokens;
  final SurfaceMaterialGeometry geo;
  const _ActionBtn({
    required this.label,
    this.onTap,
    this.accent = false,
    this.danger = false,
    required this.tokens,
    required this.geo,
  });

  @override
  State<_ActionBtn> createState() => _ActionBtnState();
}

class _ActionBtnState extends State<_ActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final geo = widget.geo;
    final enabled = widget.onTap != null;
    final tint = widget.danger ? t.stateDeleted
        : widget.accent ? t.accentBright
        : t.textMuted;

    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedContainer(
          duration: context.motion(AppMotion.snap),
          curve: AppMotion.snapCurve,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: !enabled
                ? Colors.transparent
                : _hovered
                    ? tint.withValues(alpha: 0.12)
                    : tint.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(geo.pillRadius),
            border: Border.all(
              color: !enabled
                  ? t.chromeBorder.withValues(alpha: 0.12)
                  : _hovered
                      ? tint.withValues(alpha: 0.45)
                      : tint.withValues(alpha: 0.22),
              width: 0.8,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: enabled ? tint : t.textFaint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: AppFonts.mono,
            ),
          ),
        ),
      ),
    );
  }
}
