import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/dtos.dart';
import '../../app/repository_state.dart';
import '../../components/icons/app_icons.dart';


String _pluralize(int n, String noun) => '$n $noun${n == 1 ? "" : "s"}';

class _ActionDescriptor {
  final String label;
  final String detail;
  final String buttonLabel;
  final bool disabled;
  const _ActionDescriptor({
    required this.label,
    required this.detail,
    required this.buttonLabel,
    this.disabled = false,
  });
}

_ActionDescriptor _describeAction(RepositoryStatus? status) {
  if (status == null) {
    return const _ActionDescriptor(
      label: 'Sync',
      detail: 'Open a repository to manage push and pull operations.',
      buttonLabel: 'Sync',
      disabled: true,
    );
  }

  final branch = status.branch;
  if (branch == 'HEAD' || branch.startsWith('(')) {
    return const _ActionDescriptor(
      label: 'Detached HEAD',
      detail: 'Check out a branch before pushing or pulling.',
      buttonLabel: 'Detached HEAD',
      disabled: true,
    );
  }

  if (status.upstream == null) {
    return _ActionDescriptor(
      label: 'Publish branch',
      detail: 'Push $branch and set its upstream tracking branch.',
      buttonLabel: 'Publish branch',
    );
  }

  if (status.ahead > 0 && status.behind > 0) {
    return _ActionDescriptor(
      label: 'Sync branch',
      detail:
          'Pull ${_pluralize(status.behind, "commit")} with rebase, then push ${_pluralize(status.ahead, "commit")}.',
      buttonLabel: 'Pull then push',
    );
  }

  if (status.ahead > 0) {
    return _ActionDescriptor(
      label: 'Push branch',
      detail:
          'Push ${_pluralize(status.ahead, "local commit")} to ${status.upstream}.',
      buttonLabel: 'Push commits',
    );
  }

  if (status.behind > 0) {
    return _ActionDescriptor(
      label: 'Pull updates',
      detail:
          'Pull ${_pluralize(status.behind, "remote commit")} from ${status.upstream}.',
      buttonLabel: 'Pull updates',
    );
  }

  return _ActionDescriptor(
    label: 'Check remote',
    detail: 'Fetch from ${status.upstream} and refresh upstream status.',
    buttonLabel: 'Check remote',
  );
}


class SyncPanel extends StatefulWidget {
  final VoidCallback onClose;
  const SyncPanel({super.key, required this.onClose});
  @override
  State<SyncPanel> createState() => _SyncPanelState();
}

class _SyncPanelState extends State<SyncPanel> {
  bool _syncRunning = false;
  bool _fetchRunning = false;
  String? _actionError;
  SyncData? _lastResult;
  String? _previousRepositoryPath;
  String? _statusRefreshQueuedFor;

  Future<void> _runSync(String repo, RepositoryStatus status) async {
    setState(() {
      _syncRunning = true;
      _actionError = null;
    });
    final r = await syncRemote(repo, status);
    if (!mounted) return;
    setState(() {
      _syncRunning = false;
      if (r.ok) {
        _lastResult = r.data;
      } else {
        _actionError = r.error;
      }
    });
    await context.read<RepositoryState>().refreshStatus();
  }

  Future<void> _runFetch(String repo) async {
    setState(() {
      _fetchRunning = true;
      _actionError = null;
    });
    final r = await fetchRemote(repo, prune: true);
    if (!mounted) return;
    setState(() {
      _fetchRunning = false;
      if (r.ok) {
        _lastResult = r.data;
      } else {
        _actionError = r.error;
      }
    });
    await context.read<RepositoryState>().refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Narrow the RepositoryState subscription to the four fields the
    // sync panel actually rebuilds against. `repo` below is the
    // `context.read` view used for mutating methods and passed into
    // helpers that expect the full instance — `read` doesn't
    // subscribe, so it doesn't reintroduce a whole-notifier rebuild.
    final repoSnapshot = context.select<
        RepositoryState,
        ({
          String? path,
          RepositoryStatus? status,
          bool loading,
          String? error,
        })>(
      (s) => (
        path: s.activePath,
        status: s.status,
        loading: s.statusLoading,
        error: s.statusError,
      ),
    );
    final repoPath = repoSnapshot.path;
    final status = repoSnapshot.status;
    final repo = context.read<RepositoryState>();
    final action = _describeAction(status);
    final busy = _syncRunning || _fetchRunning;

    _resetWhenRepositoryChanges(repoPath);
    _ensureStatusLoaded(repoPath, status, repo);

    String fetchStatusText;
    if (_fetchRunning) {
      fetchStatusText = 'Checking remote for new commits...';
    } else if (_lastResult?.operation == 'fetch') {
      fetchStatusText = 'Remote status refreshed';
    } else if (status != null) {
      final changed = status.files.length;
      fetchStatusText = changed == 0
          ? 'Clean working tree'
          : '${_pluralize(changed, "changed file")} ready to review';
    } else {
      fetchStatusText = '';
    }

    return MaterialSurface(
      tone: AppMaterialTone.panelStrong,
      borderAlpha: 0.22,
      elevated: true,
      innerHighlight: true,
      glaze: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.chromeAccent.withValues(alpha: 0.08),
              Colors.transparent,
            ],
            stops: const [0, 0.28],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
              decoration: BoxDecoration(
                border: Border(
                    bottom: BorderSide(
                        color: t.chromeBorder.withValues(alpha: 0.12))),
              ),
              child: Row(children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Remote',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0)),
                  const SizedBox(height: 2),
                  Text('Sync',
                      style: TextStyle(
                          color: t.textStrong,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ]),
                const Spacer(),
                _GhostBtn(label: 'Close', t: t, onTap: widget.onClose),
              ]),
            ),

            Flexible(
              fit: FlexFit.loose,
              child: _buildBody(
                t: t,
                repoPath: repoPath,
                repo: repo,
                status: status,
                action: action,
                busy: busy,
                fetchStatusText: fetchStatusText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody({
    required AppTokens t,
    required String? repoPath,
    required RepositoryState repo,
    required RepositoryStatus? status,
    required _ActionDescriptor action,
    required bool busy,
    required String fetchStatusText,
  }) {
    if (repoPath == null) {
      return const AppStatusView.noRepository(compact: true);
    }

    if (status == null && repo.statusLoading) {
      return const AppStatusView.loading(
        title: 'Loading remote status',
        message: 'Checking branch tracking information.',
        compact: true,
      );
    }

    if (status == null && repo.statusError != null) {
      return AppStatusView.error(
        title: 'Remote status unavailable',
        message: repo.statusError!,
        compact: true,
      );
    }

    if (status == null) {
      return const AppStatusView.loading(
        title: 'Loading remote status',
        message: 'Checking branch tracking information.',
        compact: true,
      );
    }

    return _SyncBody(
      t: t,
      status: status,
      action: action,
      busy: busy,
      syncRunning: _syncRunning,
      fetchRunning: _fetchRunning,
      fetchStatusText: fetchStatusText,
      actionError: _actionError,
      lastResult: _lastResult,
      onSync: () => _runSync(repoPath, status),
      onFetch: () => _runFetch(repoPath),
    );
  }

  void _resetWhenRepositoryChanges(String? repoPath) {
    if (_previousRepositoryPath == repoPath) return;
    _previousRepositoryPath = repoPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _syncRunning = false;
        _fetchRunning = false;
        _actionError = null;
        _lastResult = null;
      });
    });
  }

  void _ensureStatusLoaded(
    String? repoPath,
    RepositoryStatus? status,
    RepositoryState repo,
  ) {
    if (repoPath == null ||
        status != null ||
        repo.statusLoading ||
        repo.statusError != null ||
        _statusRefreshQueuedFor == repoPath) {
      return;
    }

    _statusRefreshQueuedFor = repoPath;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || context.read<RepositoryState>().activePath != repoPath) {
        return;
      }
      await context.read<RepositoryState>().refreshStatus();
      if (mounted && _statusRefreshQueuedFor == repoPath) {
        _statusRefreshQueuedFor = null;
      }
    });
  }
}


class _InlineSyncError extends StatelessWidget {
  final AppTokens t;
  final String title;
  final String body;

  const _InlineSyncError({
    required this.t,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.stateConflicted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.stateConflicted.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: t.stateConflicted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              color: t.stateConflicted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncBody extends StatelessWidget {
  final AppTokens t;
  final RepositoryStatus status;
  final _ActionDescriptor action;
  final bool busy;
  final bool syncRunning;
  final bool fetchRunning;
  final String fetchStatusText;
  final String? actionError;
  final SyncData? lastResult;
  final VoidCallback onSync;
  final VoidCallback onFetch;

  const _SyncBody({
    required this.t,
    required this.status,
    required this.action,
    required this.busy,
    required this.syncRunning,
    required this.fetchRunning,
    required this.fetchStatusText,
    required this.actionError,
    required this.lastResult,
    required this.onSync,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    final showLog = lastResult != null &&
        lastResult!.operation != 'fetch' &&
        lastResult!.output.isNotEmpty;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.all(16),
      children: [
        MaterialSurface(
          tone: AppMaterialTone.surface1,
          borderAlpha: 0.12,
          elevated: false,
          innerHighlight: true,
          glaze: true,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            children: [
              _HeroSection(t: t, status: status),
              const SizedBox(height: 14),
              _ActionBlock(
                t: t,
                action: action,
                fetchStatusText: fetchStatusText,
                busy: busy,
                syncRunning: syncRunning,
                fetchRunning: fetchRunning,
                onSync: onSync,
                onFetch: onFetch,
              ),
              const SizedBox(height: 10),
              _MetricsSection(t: t, status: status),
            ],
          ),
        ),

        // Error
        if (actionError != null) ...[
          const SizedBox(height: 12),
          _InlineSyncError(
            t: t,
            title: 'Sync failed',
            body: actionError!,
          ),
        ],

        // Activity log
        if (showLog) ...[
          const SizedBox(height: 12),
          _ActivityLog(t: t, result: lastResult!),
        ],
      ],
    );
  }
}


class _HeroSection extends StatelessWidget {
  final AppTokens t;
  final RepositoryStatus status;
  const _HeroSection({required this.t, required this.status});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Current branch',
          style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.06)),
      const SizedBox(height: 6),
      Row(children: [
        MaterialSurface(
          tone: AppMaterialTone.surface0,
          radius: 6,
          elevated: false,
          borderColor: t.itemActiveBorder,
          borderAlpha: 1,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(name: 'git-branch', size: 12, color: t.accentBright),
            const SizedBox(width: 5),
            Text(status.branch,
                style: TextStyle(
                    color: t.textStrong,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MaterialSurface(
            tone: AppMaterialTone.surface2,
            radius: 6,
            elevated: false,
            borderAlpha: 0.2,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              status.upstream ?? 'No upstream',
              style: TextStyle(
                  color: status.upstream != null ? t.textNormal : t.textMuted,
                  fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _SummaryPill(
            label: 'Ahead',
            value: '${status.ahead}',
            color: t.stateAdded,
            t: t),
        const SizedBox(width: 6),
        _SummaryPill(
            label: 'Behind',
            value: '${status.behind}',
            color: t.stateModified,
            t: t),
        const SizedBox(width: 6),
        _SummaryPill(
            label: 'Tree',
            value: '${status.files.length}',
            color: t.textMuted,
            t: t),
      ]),
    ]);
  }
}

class _SummaryPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final AppTokens t;
  const _SummaryPill(
      {required this.label,
      required this.value,
      required this.color,
      required this.t});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MaterialSurface(
        tone: AppMaterialTone.surface0,
        radius: 6,
        elevated: false,
        borderColor: color.withValues(alpha: 0.2),
        borderAlpha: 1,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          Text(label,
              style: TextStyle(
                  color: color.withValues(alpha: 0.7),
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.04)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}


class _ActionBlock extends StatelessWidget {
  final AppTokens t;
  final _ActionDescriptor action;
  final String fetchStatusText;
  final bool busy;
  final bool syncRunning;
  final bool fetchRunning;
  final VoidCallback onSync;
  final VoidCallback onFetch;

  const _ActionBlock({
    required this.t,
    required this.action,
    required this.fetchStatusText,
    required this.busy,
    required this.syncRunning,
    required this.fetchRunning,
    required this.onSync,
    required this.onFetch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(action.label,
                style: TextStyle(
                    color: t.textStrong,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(fetchStatusText,
                style: TextStyle(color: t.textMuted, fontSize: 11)),
          ]),
        ),
      ]),
      const SizedBox(height: 6),
      Text(action.detail, style: TextStyle(color: t.textNormal, fontSize: 12)),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: _PrimaryBtn(
            label: syncRunning ? 'Running sync...' : action.buttonLabel,
            t: t,
            enabled: !busy && !action.disabled,
            onTap: onSync,
          ),
        ),
        const SizedBox(width: 8),
        _GhostBtn(
          label: fetchRunning ? 'Fetching...' : 'Fetch only',
          t: t,
          enabled: !busy,
          onTap: onFetch,
          note: 'Utility',
        ),
      ]),
    ]);
  }
}


class _MetricsSection extends StatelessWidget {
  final AppTokens t;
  final RepositoryStatus status;
  const _MetricsSection({required this.t, required this.status});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricRow(
        symbol: 'push',
        label: 'Ahead',
        shortLabel: 'Push',
        value: status.ahead == 0
            ? 'Nothing to push'
            : _pluralize(status.ahead, 'commit'),
        tone: status.ahead > 0 ? t.stateAdded : null,
        t: t,
      ),
      _MetricRow(
        symbol: 'pull',
        label: 'Behind',
        shortLabel: 'Pull',
        value: status.behind == 0
            ? 'Already caught up'
            : _pluralize(status.behind, 'commit'),
        tone: status.behind > 0 ? t.stateModified : null,
        t: t,
      ),
      _MetricRow(
        symbol: 'tree',
        label: 'Working tree',
        shortLabel: 'Files',
        value: status.files.isEmpty
            ? 'Clean working tree'
            : _pluralize(status.files.length, 'changed file'),
        tone: null,
        t: t,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border(
            top: BorderSide(color: t.chromeBorderFaint)),
      ),
      padding: const EdgeInsets.only(top: 10),
      child: Column(
          children: metrics.asMap().entries.map((e) {
        return Column(children: [
          e.value,
          if (e.key < metrics.length - 1)
            Divider(height: 1, color: t.chromeBorder.withValues(alpha: 0.1)),
        ]);
      }).toList()),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String symbol;
  final String label;
  final String shortLabel;
  final String value;
  final Color? tone;
  final AppTokens t;
  const _MetricRow({
    required this.symbol,
    required this.label,
    required this.shortLabel,
    required this.value,
    required this.tone,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    final valueColor = tone ?? t.textNormal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(children: [
        _MetricSymbol(symbol: symbol, color: tone ?? t.textMuted),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(color: t.textNormal, fontSize: 12)),
        const SizedBox(width: 6),
        Text(shortLabel, style: TextStyle(color: t.textMuted, fontSize: 10)),
        const Spacer(),
        Text(value,
            style: TextStyle(
                color: valueColor, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _MetricSymbol extends StatelessWidget {
  final String symbol;
  final Color color;
  const _MetricSymbol({required this.symbol, required this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(14, 14),
      painter: _MetricSymbolPainter(symbol: symbol, color: color),
    );
  }
}

class _MetricSymbolPainter extends CustomPainter {
  final String symbol;
  final Color color;
  const _MetricSymbolPainter({required this.symbol, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    if (symbol == 'push') {
      // Vertical line up + arrowhead up
      canvas.drawLine(Offset(w / 2, h * 0.8), Offset(w / 2, h * 0.2), paint);
      canvas.drawLine(Offset(w / 2, h * 0.2), Offset(w * 0.3, h * 0.45), paint);
      canvas.drawLine(Offset(w / 2, h * 0.2), Offset(w * 0.7, h * 0.45), paint);
    } else if (symbol == 'pull') {
      // Vertical line down + arrowhead down
      canvas.drawLine(Offset(w / 2, h * 0.2), Offset(w / 2, h * 0.8), paint);
      canvas.drawLine(Offset(w / 2, h * 0.8), Offset(w * 0.3, h * 0.55), paint);
      canvas.drawLine(Offset(w / 2, h * 0.8), Offset(w * 0.7, h * 0.55), paint);
    } else {
      // Tree: 3 horizontal lines
      canvas.drawLine(
          Offset(w * 0.2, h * 0.25), Offset(w * 0.8, h * 0.25), paint);
      canvas.drawLine(
          Offset(w * 0.2, h * 0.5), Offset(w * 0.8, h * 0.5), paint);
      canvas.drawLine(
          Offset(w * 0.2, h * 0.75), Offset(w * 0.8, h * 0.75), paint);
    }
  }

  @override
  bool shouldRepaint(_MetricSymbolPainter old) =>
      old.symbol != symbol || old.color != color;
}


class _ActivityLog extends StatelessWidget {
  final AppTokens t;
  final SyncData result;
  const _ActivityLog({required this.t, required this.result});

  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      elevated: false,
      borderAlpha: 0.15,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Text(
            'Last sync activity: ${result.operation}',
            style: TextStyle(
                color: t.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ),
        Divider(height: 1, color: t.chromeBorder.withValues(alpha: 0.1)),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            result.output.isEmpty ? 'No output.' : result.output,
            style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: AppFonts.mono,
                height: 1.6),
          ),
        ),
      ]),
    );
  }
}



class _PrimaryBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool enabled;
  final VoidCallback onTap;
  const _PrimaryBtn(
      {required this.label,
      required this.t,
      required this.enabled,
      required this.onTap});
  @override
  State<_PrimaryBtn> createState() => _PrimaryBtnState();
}

class _PrimaryBtnState extends State<_PrimaryBtn> {
  bool _hov = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final chrome = primaryButtonChrome(
      t,
      hovered: _hov,
      pressed: _pressed,
      enabled: widget.enabled,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          duration: context.motion(const Duration(milliseconds: 80)),
          scale: chrome.scale,
          child: AnimatedContainer(
            duration: context.motion(const Duration(milliseconds: 100)),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: chrome.background,
              gradient: chrome.gradient,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: chrome.borderColor,
              ),
              boxShadow: chrome.shadows,
            ),
            child: Transform.translate(
              offset: chrome.offset,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                AppIcon(
                    name: 'sync',
                    size: 13,
                    color: widget.enabled ? t.accentBright : t.textMuted),
                const SizedBox(width: 6),
                Text(widget.label,
                    style: TextStyle(
                        color: widget.enabled ? t.btnText : t.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostBtn extends StatefulWidget {
  final String label;
  final AppTokens t;
  final bool enabled;
  final VoidCallback onTap;
  final String? note;
  const _GhostBtn(
      {required this.label,
      required this.t,
      this.enabled = true,
      required this.onTap,
      this.note});
  @override
  State<_GhostBtn> createState() => _GhostBtnState();
}

class _GhostBtnState extends State<_GhostBtn> {
  bool _hov = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final compact = widget.note == null;
    final chrome = ghostButtonChrome(
      t,
      hovered: _hov,
      pressed: _pressed,
      enabled: widget.enabled,
      baseBorderColor: t.secondaryBtnBorder,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hov = true),
      onExit: (_) => setState(() => _hov = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: context.motion(const Duration(milliseconds: 100)),
          height: compact ? 28 : 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: chrome.background,
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            border: Border.all(color: chrome.borderColor),
            boxShadow: chrome.shadows,
          ),
          child: Transform.translate(
            offset: chrome.offset,
            child: compact
                ? Center(
                    child: Text(widget.label,
                        style: TextStyle(
                            color: widget.enabled ? t.textNormal : t.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(widget.note!,
                          style: TextStyle(
                              color: t.textMuted,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0)),
                      Text(widget.label,
                          style: TextStyle(
                              color:
                                  widget.enabled ? t.textNormal : t.textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
