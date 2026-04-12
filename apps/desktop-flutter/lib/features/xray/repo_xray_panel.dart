import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/repository_state.dart';
import '../../app/repository_xray_state.dart';
import '../../backend/dtos.dart';
import '../../components/icons/app_icons.dart';
import '../../ui/control_chrome.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';

enum _XrayView { map, time, signals }

class RepoXrayPanel extends StatefulWidget {
  final VoidCallback onClose;
  final void Function(String hash)? onCommitSelected;

  const RepoXrayPanel({
    super.key,
    required this.onClose,
    this.onCommitSelected,
  });

  @override
  State<RepoXrayPanel> createState() => _RepoXrayPanelState();
}

class _RepoXrayPanelState extends State<RepoXrayPanel> {
  bool _includeMachineHistory = false;
  String? _lastLoadedRepoPath;
  String? _lastSnapshotFingerprint;
  _XrayView _view = _XrayView.map;
  String? _selectedSignalId;
  String? _selectedHotspotPath;
  String? _selectedPivotHash;
  String? _selectedStratumId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repoPath = context.watch<RepositoryState>().activePath;
    final xrayState = context.read<RepositoryXrayState>();
    if (repoPath == null) {
      _lastLoadedRepoPath = null;
      return;
    }
    if (_lastLoadedRepoPath == repoPath &&
        xrayState.snapshotFor(repoPath) != null) {
      return;
    }
    _lastLoadedRepoPath = repoPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<RepositoryXrayState>().invalidateAllExcept(repoPath);
      context.read<RepositoryXrayState>().loadForRepo(repoPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repoPath = context.watch<RepositoryState>().activePath;
    return MaterialSurface(
      tone: AppMaterialTone.panelStrong,
      radius: 14,
      borderAlpha: 0.22,
      elevated: true,
      innerHighlight: true,
      glaze: true,
      child: repoPath == null
          ? const AppStatusView.noRepository(compact: true)
          : _body(context, repoPath),
    );
  }

  Widget _body(BuildContext context, String repoPath) {
    final xray = context.watch<RepositoryXrayState>();
    final loading = xray.isLoading(repoPath);
    final error = xray.errorFor(repoPath);
    final snapshot = xray.snapshotFor(repoPath);
    if (snapshot == null && loading) {
      return const AppStatusView.loading(
        title: 'Building Repo X-Ray',
        message: 'Probing Git history, refs, cadence, and hotspots.',
        compact: true,
      );
    }
    if (snapshot == null && error != null) {
      return AppStatusView.error(
        title: 'Repo X-Ray unavailable',
        message: error,
        compact: true,
      );
    }
    if (snapshot == null) {
      return const AppStatusView(
        title: 'Repo X-Ray',
        message: 'Open the panel again to probe the current repository.',
        compact: true,
      );
    }

    final cards = _includeMachineHistory ? snapshot.rawCards : snapshot.cards;
    final hotspots =
        _includeMachineHistory ? snapshot.rawHotspots : snapshot.hotspots;
    final cadence =
        _includeMachineHistory ? snapshot.rawCadence : snapshot.cadence;
    final pivots =
        _includeMachineHistory ? snapshot.rawPivots : snapshot.pivots;
    _syncSelection(snapshot, cards, hotspots, pivots);

    return Column(
      children: [
        _Header(
          snapshot: snapshot,
          loading: loading,
          includeMachineHistory: _includeMachineHistory,
          onToggleMachineHistory: (value) {
            setState(() {
              _includeMachineHistory = value;
              _selectedSignalId = null;
              _selectedHotspotPath = null;
              _selectedPivotHash = null;
              _selectedStratumId = null;
            });
          },
          onRefresh: () {
            context.read<RepositoryXrayState>().loadForRepo(
                  repoPath,
                  forceRefresh: true,
                );
          },
          onClose: widget.onClose,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              _ViewTabs(
                current: _view,
                onChanged: (view) => setState(() => _view = view),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DiagnosisStrip(
                  cards: cards,
                  selectedId: _selectedSignalId,
                  onTap: (id) {
                    setState(() {
                      _view = _XrayView.signals;
                      _selectedSignalId = id;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final showSideInspector = constraints.maxWidth >= 640;
              final main = _MainViewport(
                view: _view,
                snapshot: snapshot,
                cards: cards,
                hotspots: hotspots,
                cadence: cadence,
                pivots: pivots,
                selectedSignalId: _selectedSignalId,
                selectedHotspotPath: _selectedHotspotPath,
                selectedPivotHash: _selectedPivotHash,
                selectedStratumId: _selectedStratumId,
                onSignalSelected: (id) =>
                    setState(() => _selectedSignalId = id),
                onHotspotSelected: (path) =>
                    setState(() => _selectedHotspotPath = path),
                onPivotSelected: (hash) =>
                    setState(() => _selectedPivotHash = hash),
                onStratumSelected: (id) =>
                    setState(() => _selectedStratumId = id),
              );
              final inspector = _InspectorPanel(
                view: _view,
                snapshot: snapshot,
                cards: cards,
                hotspots: hotspots,
                cadence: cadence,
                pivots: pivots,
                selectedSignalId: _selectedSignalId,
                selectedHotspotPath: _selectedHotspotPath,
                selectedPivotHash: _selectedPivotHash,
                selectedStratumId: _selectedStratumId,
                onCommitSelected: widget.onCommitSelected,
              );

              if (showSideInspector) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 8, child: main),
                      const SizedBox(width: 12),
                      Expanded(flex: 5, child: inspector),
                    ],
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: [
                    Expanded(child: main),
                    const SizedBox(height: 12),
                    SizedBox(height: 210, child: inspector),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _syncSelection(
    RepositoryXraySnapshotData snapshot,
    List<RepositoryXrayCardData> cards,
    List<RepositoryXrayHotspotData> hotspots,
    List<RepositoryXrayPivotCommitData> pivots,
  ) {
    if (_lastSnapshotFingerprint != snapshot.header.fingerprint) {
      _lastSnapshotFingerprint = snapshot.header.fingerprint;
      _selectedSignalId = cards.isEmpty ? null : cards.first.id;
      _selectedHotspotPath = hotspots.isEmpty ? null : hotspots.first.path;
      _selectedPivotHash = pivots.isEmpty ? null : pivots.first.commitHash;
      _selectedStratumId =
          snapshot.strata.isEmpty ? null : snapshot.strata.first.id;
      return;
    }
    if (_selectedSignalId != null &&
        !cards.any((card) => card.id == _selectedSignalId)) {
      _selectedSignalId = cards.isEmpty ? null : cards.first.id;
    }
    if (_selectedHotspotPath != null &&
        !hotspots.any((hotspot) => hotspot.path == _selectedHotspotPath)) {
      _selectedHotspotPath = hotspots.isEmpty ? null : hotspots.first.path;
    }
    if (_selectedPivotHash != null &&
        !pivots.any((pivot) => pivot.commitHash == _selectedPivotHash)) {
      _selectedPivotHash = pivots.isEmpty ? null : pivots.first.commitHash;
    }
    if (_selectedStratumId != null &&
        !snapshot.strata.any((stratum) => stratum.id == _selectedStratumId)) {
      _selectedStratumId =
          snapshot.strata.isEmpty ? null : snapshot.strata.first.id;
    }
  }
}

class _Header extends StatelessWidget {
  final RepositoryXraySnapshotData snapshot;
  final bool loading;
  final bool includeMachineHistory;
  final ValueChanged<bool> onToggleMachineHistory;
  final VoidCallback onRefresh;
  final VoidCallback onClose;

  const _Header({
    required this.snapshot,
    required this.loading,
    required this.includeMachineHistory,
    required this.onToggleMachineHistory,
    required this.onRefresh,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
      decoration: BoxDecoration(
        color: t.panelOverlayStrong.withValues(alpha: 0.12),
        border: Border(
            bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.12))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: t.chromeBorder.withValues(alpha: 0.28)),
                ),
                child: Center(
                  child:
                      AppIcon(name: 'app-logo', size: 14, color: t.textStrong),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Repo X-Ray',
                          style: TextStyle(
                              color: t.textStrong,
                              fontSize: 17,
                              fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 8),
                        _DenseBadge(
                            value: '${snapshot.header.dirtyFileCount}',
                            label: 'dirty'),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${snapshot.header.repoName} | ${snapshot.header.branch} | ${snapshot.header.headShortHash}',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono'),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('machine',
                      style: TextStyle(color: t.textMuted, fontSize: 10)),
                  const SizedBox(width: 4),
                  Switch(
                    value: includeMachineHistory,
                    onChanged: onToggleMachineHistory,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              _MiniButton(
                label: loading ? 'Refreshing...' : 'Refresh',
                icon: 'search',
                enabled: !loading,
                onTap: onRefresh,
              ),
              const SizedBox(width: 8),
              _MiniButton(
                  label: 'Close', icon: 'x', enabled: true, onTap: onClose),
            ],
          ),
        ],
      ),
    );
  }
}

class _DiagnosisStrip extends StatelessWidget {
  final List<RepositoryXrayCardData> cards;
  final String? selectedId;
  final ValueChanged<String> onTap;

  const _DiagnosisStrip({
    required this.cards,
    required this.selectedId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            _DiagnosisToken(
              card: cards[i],
              active: cards[i].id == selectedId,
              onTap: () => onTap(cards[i].id),
            ),
            if (i != cards.length - 1) const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ViewTabs extends StatelessWidget {
  final _XrayView current;
  final ValueChanged<_XrayView> onChanged;

  const _ViewTabs({
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TabChip(
            label: 'Map',
            icon: 'app-logo',
            active: current == _XrayView.map,
            onTap: () => onChanged(_XrayView.map)),
        const SizedBox(width: 8),
        _TabChip(
            label: 'Time',
            icon: 'history',
            active: current == _XrayView.time,
            onTap: () => onChanged(_XrayView.time)),
        const SizedBox(width: 8),
        _TabChip(
            label: 'Signals',
            icon: 'search',
            active: current == _XrayView.signals,
            onTap: () => onChanged(_XrayView.signals)),
      ],
    );
  }
}

class _MainViewport extends StatelessWidget {
  final _XrayView view;
  final RepositoryXraySnapshotData snapshot;
  final List<RepositoryXrayCardData> cards;
  final List<RepositoryXrayHotspotData> hotspots;
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedSignalId;
  final String? selectedHotspotPath;
  final String? selectedPivotHash;
  final String? selectedStratumId;
  final ValueChanged<String> onSignalSelected;
  final ValueChanged<String> onHotspotSelected;
  final ValueChanged<String> onPivotSelected;
  final ValueChanged<String> onStratumSelected;

  const _MainViewport({
    required this.view,
    required this.snapshot,
    required this.cards,
    required this.hotspots,
    required this.cadence,
    required this.pivots,
    required this.selectedSignalId,
    required this.selectedHotspotPath,
    required this.selectedPivotHash,
    required this.selectedStratumId,
    required this.onSignalSelected,
    required this.onHotspotSelected,
    required this.onPivotSelected,
    required this.onStratumSelected,
  });

  @override
  Widget build(BuildContext context) {
    return _PanelBlock(
      child: switch (view) {
        _XrayView.map => _MapView(
            snapshot: snapshot,
            hotspots: hotspots,
            selectedHotspotPath: selectedHotspotPath,
            selectedStratumId: selectedStratumId,
            onHotspotSelected: onHotspotSelected,
            onStratumSelected: onStratumSelected,
          ),
        _XrayView.time => _TimeView(
            cadence: cadence,
            pivots: pivots,
            selectedPivotHash: selectedPivotHash,
            onPivotSelected: onPivotSelected,
          ),
        _XrayView.signals => _SignalsView(
            cards: cards,
            selectedSignalId: selectedSignalId,
            onSignalSelected: onSignalSelected,
          ),
      },
    );
  }
}

class _MapView extends StatelessWidget {
  final RepositoryXraySnapshotData snapshot;
  final List<RepositoryXrayHotspotData> hotspots;
  final String? selectedHotspotPath;
  final String? selectedStratumId;
  final ValueChanged<String> onHotspotSelected;
  final ValueChanged<String> onStratumSelected;

  const _MapView({
    required this.snapshot,
    required this.hotspots,
    required this.selectedHotspotPath,
    required this.selectedStratumId,
    required this.onHotspotSelected,
    required this.onStratumSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 420;
        final terrain = _TerrainBoard(
          strata: snapshot.strata,
          selectedId: selectedStratumId,
          onSelected: onStratumSelected,
        );
        final heat = _HotspotBoard(
          hotspots: hotspots,
          selectedPath: selectedHotspotPath,
          onSelected: onHotspotSelected,
        );
        if (!wide) {
          return Column(
            children: [
              Expanded(flex: 5, child: terrain),
              const SizedBox(height: 10),
              Expanded(flex: 4, child: heat),
            ],
          );
        }
        return Row(
          children: [
            Expanded(flex: 6, child: terrain),
            const SizedBox(width: 10),
            Expanded(flex: 4, child: heat),
          ],
        );
      },
    );
  }
}

class _TimeView extends StatelessWidget {
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;

  const _TimeView({
    required this.cadence,
    required this.pivots,
    required this.selectedPivotHash,
    required this.onPivotSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          flex: 6,
          child: _TimelineBoard(
            cadence: cadence,
            pivots: pivots,
            selectedPivotHash: selectedPivotHash,
            onPivotSelected: onPivotSelected,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 110,
          child: _PivotStrip(
            pivots: pivots,
            selectedPivotHash: selectedPivotHash,
            onPivotSelected: onPivotSelected,
          ),
        ),
      ],
    );
  }
}

class _SignalsView extends StatelessWidget {
  final List<RepositoryXrayCardData> cards;
  final String? selectedSignalId;
  final ValueChanged<String> onSignalSelected;

  const _SignalsView({
    required this.cards,
    required this.selectedSignalId,
    required this.onSignalSelected,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth < 520 ? 1 : 2;
        final spacing = 10.0;
        final tileWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
                crossAxisCount;
        final targetHeight = constraints.maxHeight < 340 ? 112.0 : 134.0;
        final aspectRatio = (tileWidth / targetHeight).clamp(1.35, 1.9);
        return GridView.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: cards.length,
          itemBuilder: (context, index) {
            final card = cards[index];
            return _SignalTile(
              card: card,
              active: card.id == selectedSignalId,
              onTap: () => onSignalSelected(card.id),
            );
          },
        );
      },
    );
  }
}

class _InspectorPanel extends StatelessWidget {
  final _XrayView view;
  final RepositoryXraySnapshotData snapshot;
  final List<RepositoryXrayCardData> cards;
  final List<RepositoryXrayHotspotData> hotspots;
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedSignalId;
  final String? selectedHotspotPath;
  final String? selectedPivotHash;
  final String? selectedStratumId;
  final void Function(String hash)? onCommitSelected;

  const _InspectorPanel({
    required this.view,
    required this.snapshot,
    required this.cards,
    required this.hotspots,
    required this.cadence,
    required this.pivots,
    required this.selectedSignalId,
    required this.selectedHotspotPath,
    required this.selectedPivotHash,
    required this.selectedStratumId,
    this.onCommitSelected,
  });

  @override
  Widget build(BuildContext context) {
    final card = selectedSignalId == null
        ? null
        : cards.cast<RepositoryXrayCardData?>().firstWhere(
              (item) => item!.id == selectedSignalId,
              orElse: () => null,
            );
    final hotspot = selectedHotspotPath == null
        ? null
        : hotspots.cast<RepositoryXrayHotspotData?>().firstWhere(
              (item) => item!.path == selectedHotspotPath,
              orElse: () => null,
            );
    final pivot = selectedPivotHash == null
        ? null
        : pivots.cast<RepositoryXrayPivotCommitData?>().firstWhere(
              (item) => item!.commitHash == selectedPivotHash,
              orElse: () => null,
            );
    final stratum = selectedStratumId == null
        ? null
        : snapshot.strata.cast<RepositoryXrayStratumData?>().firstWhere(
              (item) => item!.id == selectedStratumId,
              orElse: () => null,
            );

    return _PanelBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InspectorModeBar(view: view),
          const SizedBox(height: 10),
          Expanded(
            child: switch (view) {
              _XrayView.map => hotspot != null
                  ? _HotspotInspector(
                      hotspot: hotspot, onCommitSelected: onCommitSelected)
                  : stratum != null
                      ? _StratumInspector(stratum: stratum)
                      : _OverviewInspector(snapshot: snapshot),
              _XrayView.time => pivot != null
                  ? _PivotInspector(
                      pivot: pivot, onCommitSelected: onCommitSelected)
                  : _OverviewInspector(snapshot: snapshot),
              _XrayView.signals => card != null
                  ? _SignalInspector(
                      card: card, onCommitSelected: onCommitSelected)
                  : _OverviewInspector(snapshot: snapshot),
            },
          ),
        ],
      ),
    );
  }
}

class _PanelBlock extends StatelessWidget {
  final Widget child;
  const _PanelBlock({required this.child});
  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      tone: AppMaterialTone.surface1,
      radius: 12,
      borderAlpha: 0.16,
      elevated: false,
      innerHighlight: true,
      glaze: true,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: child,
      ),
    );
  }
}

class _DiagnosisToken extends StatelessWidget {
  final RepositoryXrayCardData card;
  final bool active;
  final VoidCallback onTap;
  const _DiagnosisToken(
      {required this.card, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = _signalAccent(t, card.verdict);
    return _ChromeChip(
      label: _compactCardTitle(card.title),
      leading: Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
      ),
      active: active,
      activeBorderColor: accent.withValues(alpha: 0.5),
      onTap: onTap,
      textColor: t.textStrong,
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final String icon;
  final bool active;
  final VoidCallback onTap;
  const _TabChip(
      {required this.label,
      required this.icon,
      required this.active,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _ChromeChip(
      label: label,
      leading: AppIcon(
          name: icon, size: 12, color: active ? t.textStrong : t.textMuted),
      active: active,
      onTap: onTap,
      textColor: t.textStrong,
    );
  }
}

class _OverviewInspector extends StatelessWidget {
  final RepositoryXraySnapshotData snapshot;
  const _OverviewInspector({required this.snapshot});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        _InspectorRow(label: 'fingerprint', value: snapshot.header.fingerprint),
        _InspectorRow(label: 'head', value: snapshot.header.headCommitHash),
        _InspectorRow(
            label: 'hidden refs',
            value: '${snapshot.signalIntegrity.hiddenRefCount}'),
        _InspectorRow(
            label: 'raw commits',
            value: '${snapshot.signalIntegrity.rawCommitCount}'),
        _InspectorRow(
            label: 'filtered commits',
            value: '${snapshot.signalIntegrity.filteredCommitCount}'),
      ],
    );
  }
}

class _SignalInspector extends StatelessWidget {
  final RepositoryXrayCardData card;
  final void Function(String hash)? onCommitSelected;
  const _SignalInspector({required this.card, this.onCommitSelected});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(card.title,
            style: TextStyle(
                color: context.tokens.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _InspectorRow(label: 'verdict', value: card.verdict),
        _InspectorRow(label: 'confidence', value: card.confidence),
        _InspectorRow(label: 'claim', value: card.claim),
        if (card.primaryPath != null)
          _InspectorRow(label: 'path', value: card.primaryPath!),
        if (card.primaryCommitHash != null)
          _InspectorRow(label: 'commit', value: card.primaryCommitHash!),
        const SizedBox(height: 8),
        for (final item in card.evidence) ...[
          _InspectorRow(label: item.label, value: item.detail),
          const SizedBox(height: 6),
        ],
        if (card.primaryCommitHash != null && onCommitSelected != null) ...[
          const SizedBox(height: 8),
          _MiniButton(
              label: 'Open commit',
              icon: 'history',
              enabled: true,
              onTap: () => onCommitSelected!(card.primaryCommitHash!)),
        ],
      ],
    );
  }
}

class _HotspotInspector extends StatelessWidget {
  final RepositoryXrayHotspotData hotspot;
  final void Function(String hash)? onCommitSelected;
  const _HotspotInspector({required this.hotspot, this.onCommitSelected});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(hotspot.path,
            style: TextStyle(
                color: context.tokens.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _InspectorRow(label: 'kind', value: hotspot.kind),
        _InspectorRow(label: 'touches', value: '${hotspot.touchCount}'),
        _InspectorRow(label: 'owners', value: '${hotspot.ownerCount}'),
        _InspectorRow(label: 'last touched', value: hotspot.lastTouchedAt),
        if (hotspot.latestCommitHash != null)
          _InspectorRow(
              label: 'latest commit', value: hotspot.latestCommitHash!),
        if (hotspot.latestCommitHash != null && onCommitSelected != null) ...[
          const SizedBox(height: 8),
          _MiniButton(
              label: hotspot.latestShortHash ?? 'Open commit',
              icon: 'history',
              enabled: true,
              onTap: () => onCommitSelected!(hotspot.latestCommitHash!)),
        ],
      ],
    );
  }
}

class _StratumInspector extends StatelessWidget {
  final RepositoryXrayStratumData stratum;
  const _StratumInspector({required this.stratum});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(stratum.pathPrefix,
            style: TextStyle(
                color: context.tokens.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _InspectorRow(label: 'label', value: stratum.label),
        _InspectorRow(label: 'touches', value: '${stratum.touchCount}'),
        _InspectorRow(label: 'owners', value: '${stratum.ownerCount}'),
        _InspectorRow(label: 'last touched', value: stratum.lastTouchedAt),
        _InspectorRow(label: 'summary', value: stratum.summary),
      ],
    );
  }
}

class _PivotInspector extends StatelessWidget {
  final RepositoryXrayPivotCommitData pivot;
  final void Function(String hash)? onCommitSelected;
  const _PivotInspector({required this.pivot, this.onCommitSelected});
  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(pivot.subject,
            style: TextStyle(
                color: context.tokens.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        _InspectorRow(label: 'short hash', value: pivot.shortHash),
        _InspectorRow(label: 'author', value: pivot.authorName),
        _InspectorRow(label: 'date', value: pivot.authoredAt),
        _InspectorRow(label: 'files changed', value: '${pivot.filesChanged}'),
        _InspectorRow(label: 'insertions', value: '${pivot.insertions}'),
        _InspectorRow(label: 'deletions', value: '${pivot.deletions}'),
        const SizedBox(height: 8),
        if (onCommitSelected != null)
          _MiniButton(
              label: 'Open commit',
              icon: 'history',
              enabled: true,
              onTap: () => onCommitSelected!(pivot.commitHash)),
      ],
    );
  }
}

class _InspectorRow extends StatelessWidget {
  final String label;
  final String value;
  const _InspectorRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
          width: 86,
          child: Text(label.toUpperCase(),
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: 9,
                  letterSpacing: 1.0,
                  fontFamily: 'JetBrainsMono'))),
      Expanded(
          child: Text(value,
              style:
                  TextStyle(color: t.textNormal, fontSize: 11, height: 1.4))),
    ]);
  }
}

class _InspectorModeBar extends StatelessWidget {
  final _XrayView view;
  const _InspectorModeBar({required this.view});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final label = switch (view) {
      _XrayView.map => 'map selection',
      _XrayView.time => 'time selection',
      _XrayView.signals => 'signal selection',
    };
    return Row(
      children: [
        Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: t.accentBright, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8)),
      ],
    );
  }
}

class _ChromeChip extends StatefulWidget {
  final String label;
  final Widget? leading;
  final bool active;
  final VoidCallback onTap;
  final Color? activeBorderColor;
  final Color? textColor;

  const _ChromeChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.leading,
    this.activeBorderColor,
    this.textColor,
  });

  @override
  State<_ChromeChip> createState() => _ChromeChipState();
}

class _ChromeChipState extends State<_ChromeChip> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = modeButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      active: widget.active,
    );
    final borderColor = widget.activeBorderColor ?? chrome.borderColor;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: chrome.background,
            gradient: chrome.gradient,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: borderColor),
            boxShadow: chrome.shadows,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.textColor ?? t.textNormal,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;
  final Color color;
  const _Tag({required this.text, required this.color});
  @override
  Widget build(BuildContext context) {
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 999,
      elevated: false,
      glaze: false,
      borderColor: color.withValues(alpha: 0.2),
      borderAlpha: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          text,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _DenseBadge extends StatelessWidget {
  final String value;
  final String label;
  const _DenseBadge({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 999,
      elevated: false,
      glaze: false,
      borderAlpha: 0.14,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Text(
          '$value $label',
          style: TextStyle(
              color: t.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _TerrainBoard extends StatelessWidget {
  final List<RepositoryXrayStratumData> strata;
  final String? selectedId;
  final ValueChanged<String> onSelected;
  const _TerrainBoard(
      {required this.strata,
      required this.selectedId,
      required this.onSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxTouches = strata.fold<int>(0, (m, e) => math.max(m, e.touchCount));
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 12,
      elevated: false,
      innerHighlight: true,
      glaze: false,
      borderAlpha: 0.14,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Strata',
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Expanded(
              child: Column(
                children: [
                  for (var i = 0; i < strata.length; i++) ...[
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final s = strata[i];
                          final accent = _stratumAccent(t, s.label);
                          final fraction = maxTouches > 0
                              ? (s.touchCount / maxTouches).clamp(0.12, 1.0)
                              : 0.12;
                          final width = math.max(108.0, c.maxWidth * fraction);
                          final verticalCompact = c.maxHeight < 62;
                          final ultraCompact = c.maxHeight < 48;
                          final compact = width < 186 || verticalCompact;
                          final showStats = width >= 126 && !verticalCompact;
                          final showTag = width >= 170 && !verticalCompact;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => onSelected(s.id),
                              child: SizedBox(
                                width: width,
                                height: math.max(48.0, c.maxHeight - 6),
                                child: MaterialSurface(
                                  tone: selectedId == s.id
                                      ? AppMaterialTone.surface1
                                      : AppMaterialTone.surface0,
                                  radius: 12,
                                  elevated: false,
                                  glaze: false,
                                  borderColor: selectedId == s.id
                                      ? accent.withValues(alpha: 0.42)
                                      : t.chromeBorder.withValues(alpha: 0.14),
                                  borderAlpha: 1,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(
                                          color: accent.withValues(
                                              alpha: selectedId == s.id
                                                  ? 0.9
                                                  : 0.55),
                                          width: 3,
                                        ),
                                      ),
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: compact ? 8 : 12,
                                      vertical: compact ? 6 : 10,
                                    ),
                                    child: compact
                                        ? Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      s.pathPrefix,
                                                      maxLines:
                                                          ultraCompact ? 1 : 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: t.textStrong,
                                                        fontSize: ultraCompact
                                                            ? 10.5
                                                            : 11.5,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    if (showStats) ...[
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        '${s.touchCount} | ${s.ownerCount}',
                                                        style: TextStyle(
                                                          color: t.textMuted,
                                                          fontSize: 9.5,
                                                          fontFamily:
                                                              'JetBrainsMono',
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ),
                                              if (showTag) ...[
                                                const SizedBox(width: 6),
                                                _Tag(
                                                  text: _compactStratumLabel(
                                                      s.label),
                                                  color: accent,
                                                ),
                                              ],
                                            ],
                                          )
                                        : Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(s.pathPrefix,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: TextStyle(
                                                            color: t.textStrong,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700)),
                                                    const SizedBox(height: 3),
                                                    Text(
                                                        '${s.touchCount} | ${s.ownerCount} | ${s.lastTouchedAt}',
                                                        style: TextStyle(
                                                            color: t.textMuted,
                                                            fontSize: 10,
                                                            fontFamily:
                                                                'JetBrainsMono')),
                                                  ],
                                                ),
                                              ),
                                              if (showTag) ...[
                                                const SizedBox(width: 8),
                                                _Tag(
                                                    text: _compactStratumLabel(
                                                        s.label),
                                                    color: accent),
                                              ],
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HotspotBoard extends StatelessWidget {
  final List<RepositoryXrayHotspotData> hotspots;
  final String? selectedPath;
  final ValueChanged<String> onSelected;
  const _HotspotBoard(
      {required this.hotspots,
      required this.selectedPath,
      required this.onSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxTouches =
        hotspots.fold<int>(0, (m, e) => math.max(m, e.touchCount));
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 12,
      elevated: false,
      innerHighlight: true,
      glaze: false,
      borderAlpha: 0.14,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Heat',
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8)),
            const SizedBox(height: 10),
            Expanded(
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.45,
                ),
                itemCount: math.min(hotspots.length, 6),
                itemBuilder: (context, index) {
                  final h = hotspots[index];
                  final accent = _hotspotAccent(t, h.kind);
                  final intensity = maxTouches > 0
                      ? (h.touchCount / maxTouches).clamp(0.12, 1.0)
                      : 0.12;
                  final active = selectedPath == h.path;
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(h.path),
                    child: MaterialSurface(
                      tone: active
                          ? AppMaterialTone.surface1
                          : AppMaterialTone.surface0,
                      radius: 12,
                      elevated: false,
                      glaze: false,
                      borderColor: active
                          ? accent.withValues(alpha: 0.42)
                          : t.chromeBorder.withValues(alpha: 0.14),
                      borderAlpha: 1,
                      child: LayoutBuilder(
                        builder: (context, tile) {
                          final compact =
                              tile.maxHeight < 108 || tile.maxWidth < 150;
                          final ultraCompact = tile.maxHeight < 92;
                          return Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                  color: accent.withValues(
                                      alpha: 0.25 + 0.45 * intensity),
                                  width: 3,
                                ),
                              ),
                            ),
                            padding: EdgeInsets.all(compact ? 8 : 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _shortPath(h.path),
                                  maxLines: ultraCompact ? 1 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.textStrong,
                                    fontSize: compact ? 10.5 : 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${h.touchCount}',
                                  style: TextStyle(
                                    color: t.textStrong,
                                    fontSize: compact ? 14 : 16,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'JetBrainsMono',
                                  ),
                                ),
                                if (!ultraCompact) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    '${h.kind} | ${h.ownerCount}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: t.textMuted,
                                      fontSize: 10,
                                      fontFamily: 'JetBrainsMono',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineBoard extends StatelessWidget {
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;
  const _TimelineBoard(
      {required this.cadence,
      required this.pivots,
      required this.selectedPivotHash,
      required this.onPivotSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final allDates = <DateTime>[
      for (final p in pivots)
        if (DateTime.tryParse(p.authoredAt) != null)
          DateTime.parse(p.authoredAt),
      for (final c in cadence)
        if (_cadenceDate(c) != null) _cadenceDate(c)!,
    ];
    final minDate = allDates.isEmpty
        ? DateTime.now()
        : allDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final maxDate = allDates.isEmpty
        ? DateTime.now()
        : allDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final spanDays = math.max(maxDate.difference(minDate).inDays.abs(), 1);
    double xFor(DateTime date, double width) =>
        ((date.difference(minDate).inDays) / spanDays).clamp(0.0, 1.0) *
            (width - 24) +
        12;

    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 12,
      elevated: false,
      innerHighlight: true,
      glaze: false,
      borderAlpha: 0.14,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, c) {
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _TimelinePainter(tokens: t),
                  ),
                ),
                for (final item in cadence)
                  if (_cadenceDate(item) != null)
                    Positioned(
                      left: xFor(_cadenceDate(item)!, c.maxWidth) - 10,
                      top: item.kind == 'reflog' ? 118 : 34,
                      child: _TimelineMarker(
                        label: item.kind,
                        count: item.count,
                        color: _cadenceAccent(t, item.kind),
                      ),
                    ),
                for (final pivot in pivots)
                  if (DateTime.tryParse(pivot.authoredAt) != null)
                    Positioned(
                      left: xFor(DateTime.parse(pivot.authoredAt), c.maxWidth) -
                          26,
                      top: 72,
                      child: GestureDetector(
                        onTap: () => onPivotSelected(pivot.commitHash),
                        child: _PivotMarker(
                          hash: pivot.shortHash,
                          active: pivot.commitHash == selectedPivotHash,
                        ),
                      ),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PivotStrip extends StatelessWidget {
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;
  const _PivotStrip(
      {required this.pivots,
      required this.selectedPivotHash,
      required this.onPivotSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: pivots.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final p = pivots[index];
        final active = p.commitHash == selectedPivotHash;
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => onPivotSelected(p.commitHash),
          child: MaterialSurface(
            tone: active ? AppMaterialTone.surface1 : AppMaterialTone.surface0,
            width: 180,
            radius: 12,
            elevated: false,
            glaze: false,
            borderColor: active
                ? t.itemActiveBorder
                : t.chromeBorder.withValues(alpha: 0.14),
            borderAlpha: 1,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.shortHash,
                      style: TextStyle(
                          color: t.accentBright,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono')),
                  const SizedBox(height: 6),
                  Text(p.subject,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textStrong,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('${p.authoredAt} | ${p.filesChanged}',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10,
                          fontFamily: 'JetBrainsMono')),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SignalTile extends StatelessWidget {
  final RepositoryXrayCardData card;
  final bool active;
  final VoidCallback onTap;
  const _SignalTile(
      {required this.card, required this.active, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = _signalAccent(t, card.verdict);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: MaterialSurface(
        tone: active ? AppMaterialTone.surface1 : AppMaterialTone.surface0,
        radius: 12,
        elevated: false,
        glaze: false,
        borderColor: active
            ? accent.withValues(alpha: 0.42)
            : t.chromeBorder.withValues(alpha: 0.14),
        borderAlpha: 1,
        child: LayoutBuilder(
          builder: (context, c) {
            final compact = c.maxHeight < 118 || c.maxWidth < 220;
            final ultraCompact = c.maxHeight < 98 || c.maxWidth < 180;
            final claimLines = ultraCompact ? 1 : (compact ? 2 : 3);
            final titleLines = ultraCompact ? 2 : 3;
            return Padding(
              padding: EdgeInsets.all(compact ? 10 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: accent, shape: BoxShape.circle),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _compactCardTitle(card.title),
                          maxLines: titleLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textStrong,
                            fontSize: compact ? 11.5 : 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(3, (i) {
                      final activeDot = i <
                          (card.confidence == 'high'
                              ? 3
                              : card.confidence == 'medium'
                                  ? 2
                                  : 1);
                      return Padding(
                        padding: EdgeInsets.only(right: i == 2 ? 0 : 4),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: activeDot
                                ? accent
                                : t.chromeBorder.withValues(alpha: 0.22),
                            shape: BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        card.claim,
                        maxLines: claimLines,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: compact ? 10 : 10.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TimelineMarker extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _TimelineMarker(
      {required this.label, required this.count, required this.color});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 36;
        return Column(
          children: [
            Container(
                width: compact ? 8 : 10,
                height: compact ? 8 : 10,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(height: 4),
            Text(
              compact ? '$count' : '$label $count',
              style: TextStyle(
                  color: t.textMuted,
                  fontSize: compact ? 9 : 10,
                  fontWeight: FontWeight.w700),
            ),
          ],
        );
      },
    );
  }
}

class _PivotMarker extends StatelessWidget {
  final String hash;
  final bool active;
  const _PivotMarker({required this.hash, required this.active});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 56;
        return Column(
          children: [
            Container(
                width: 2,
                height: 26,
                color: active
                    ? t.accentBright
                    : t.chromeBorder.withValues(alpha: 0.5)),
            const SizedBox(height: 4),
            MaterialSurface(
              tone:
                  active ? AppMaterialTone.surface1 : AppMaterialTone.surface0,
              radius: 999,
              elevated: false,
              glaze: false,
              borderColor: active
                  ? t.itemActiveBorder
                  : t.chromeBorder.withValues(alpha: 0.14),
              borderAlpha: 1,
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: compact ? 5 : 7, vertical: 4),
                child: Text(
                  compact ? hash.substring(0, math.min(hash.length, 5)) : hash,
                  style: TextStyle(
                      color: active ? t.accentBright : t.textMuted,
                      fontSize: compact ? 9 : 10,
                      fontFamily: 'JetBrainsMono'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TimelinePainter extends CustomPainter {
  final AppTokens tokens;
  const _TimelinePainter({required this.tokens});
  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = tokens.chromeBorder.withValues(alpha: 0.2)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(12, 78), Offset(size.width - 12, 78), line);
    canvas.drawLine(const Offset(12, 124), Offset(size.width - 12, 124), line);
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) =>
      oldDelegate.tokens != tokens;
}

DateTime? _cadenceDate(RepositoryXrayCadenceData item) {
  if (DateTime.tryParse(item.label) != null) {
    return DateTime.parse(item.label);
  }
  if (item.kind == 'gap') {
    final parts = item.label.split('->');
    if (parts.isNotEmpty && DateTime.tryParse(parts.first.trim()) != null) {
      return DateTime.parse(parts.first.trim());
    }
  }
  return null;
}

String _shortPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
  if (parts.length <= 2) return normalized;
  return '${parts[parts.length - 2]}/${parts.last}';
}

String _compactCardTitle(String title) {
  final lower = title.toLowerCase();
  if (lower.contains('hidden git namespaces')) return 'hidden refs';
  if (lower.contains('machine history dominates')) return 'machine-heavy';
  if (lower.contains('architecture migration')) return 'migration';
  if (lower.contains('single-owner hotspot')) return 'single-owner';
  if (lower.contains('no formal release/tag trail')) return 'no tags';
  if (lower.contains('bursty development cadence')) return 'bursty';
  if (lower.contains('branch model')) return 'branches';
  if (lower.contains('reflog')) return 'reflog';
  if (lower.contains('hotspot concentration')) return 'narrow hotspot';
  return title.toLowerCase();
}

String _compactStratumLabel(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('current')) return 'current';
  if (lower.contains('architecture')) return 'legacy';
  return lower;
}

Color _signalAccent(AppTokens t, String verdict) {
  return switch (verdict) {
    'hard-fact' => t.accentBright,
    'strong-pattern' => t.stateModified,
    _ => t.chromeAccent,
  };
}

Color _stratumAccent(AppTokens t, String label) {
  final lower = label.toLowerCase();
  if (lower.contains('current')) return t.stateAdded;
  if (lower.contains('legacy') || lower.contains('architecture')) {
    return t.stateModified;
  }
  return t.accentBright;
}

Color _hotspotAccent(AppTokens t, String kind) {
  return kind == 'directory' ? t.stateModified : t.stateDeleted;
}

Color _cadenceAccent(AppTokens t, String kind) {
  return switch (kind) {
    'burst' => t.stateModified,
    'gap' => t.textMuted,
    _ => t.accentBright,
  };
}

class _MiniButton extends StatefulWidget {
  final String label;
  final String? icon;
  final bool enabled;
  final VoidCallback onTap;
  const _MiniButton(
      {required this.label,
      this.icon,
      required this.enabled,
      required this.onTap});
  @override
  State<_MiniButton> createState() => _MiniButtonState();
}

class _MiniButtonState extends State<_MiniButton> {
  bool _hovered = false;
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = ghostButtonChrome(t,
        hovered: _hovered,
        pressed: _pressed,
        enabled: widget.enabled,
        baseBorderColor: t.secondaryBtnBorder);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: chrome.background,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: chrome.borderColor),
              boxShadow: chrome.shadows),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (widget.icon != null) ...[
              AppIcon(name: widget.icon!, size: 12, color: t.textMuted),
              const SizedBox(width: 6)
            ],
            Text(widget.label,
                style: TextStyle(color: t.textNormal, fontSize: 11)),
          ]),
        ),
      ),
    );
  }
}
