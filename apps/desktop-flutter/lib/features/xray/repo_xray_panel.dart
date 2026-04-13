import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/repository_state.dart';
import '../../app/repository_xray_state.dart';
import '../../backend/dtos.dart';
import '../../components/icons/app_icons.dart';
import '../../ui/control_chrome.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
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
          child: LayoutBuilder(builder: (context, c) {
            final tabs = _ViewTabs(
              current: _view,
              onChanged: (view) => setState(() => _view = view),
            );
            final strip = _DiagnosisStrip(
              cards: cards,
              selectedId: _selectedSignalId,
              onTap: (id) {
                setState(() {
                  _view = _XrayView.signals;
                  _selectedSignalId = id;
                });
              },
            );
            // Below this width, stacking the two rows avoids cramping both.
            final narrow = c.maxWidth < 420;
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(alignment: Alignment.centerLeft, child: tabs),
                  const SizedBox(height: 8),
                  strip,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tabs,
                const SizedBox(width: 10),
                Expanded(child: strip),
              ],
            );
          }),
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
                onSignalSelected: (id) => setState(() =>
                    _selectedSignalId = _selectedSignalId == id ? null : id),
                onHotspotSelected: (path) => setState(() =>
                    _selectedHotspotPath =
                        _selectedHotspotPath == path ? null : path),
                onPivotSelected: (hash) => setState(() =>
                    _selectedPivotHash =
                        _selectedPivotHash == hash ? null : hash),
                onStratumSelected: (id) => setState(() => _selectedStratumId =
                    _selectedStratumId == id ? null : id),
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
    // On a fresh snapshot, start with nothing selected so the Overview
    // inspector (repo anatomy) is the landing state. Users drill in by
    // clicking items.
    if (_lastSnapshotFingerprint != snapshot.header.fingerprint) {
      _lastSnapshotFingerprint = snapshot.header.fingerprint;
      _selectedSignalId = null;
      _selectedHotspotPath = null;
      _selectedPivotHash = null;
      _selectedStratumId = null;
      return;
    }
    // Invalidate selections that no longer exist in the current filtered set
    // (e.g. the machine-history toggle changed). Fall back to null so Overview
    // is shown rather than forcing a different item.
    if (_selectedSignalId != null &&
        !cards.any((card) => card.id == _selectedSignalId)) {
      _selectedSignalId = null;
    }
    if (_selectedHotspotPath != null &&
        !hotspots.any((hotspot) => hotspot.path == _selectedHotspotPath)) {
      _selectedHotspotPath = null;
    }
    if (_selectedPivotHash != null &&
        !pivots.any((pivot) => pivot.commitHash == _selectedPivotHash)) {
      _selectedPivotHash = null;
    }
    if (_selectedStratumId != null &&
        !snapshot.strata.any((stratum) => stratum.id == _selectedStratumId)) {
      _selectedStratumId = null;
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
      child: LayoutBuilder(builder: (context, c) {
        // Below this width the controls wrap to their own row under the title
        // so nothing overflows and the subtitle can keep its ellipsis.
        final narrow = c.maxWidth < 460;

        final titleBlock = Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: t.chromeBorderStrong),
              ),
              child: Center(
                child: AppIcon(
                    name: 'app-logo', size: 14, color: t.textStrong),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Repo X-Ray',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textStrong,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _DenseBadge(
                        value: '${snapshot.header.dirtyFileCount}',
                        label: 'dirty',
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    '${snapshot.header.repoName} · ${snapshot.header.branch} · ${snapshot.header.headShortHash}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 11,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ChromeChip(
              label: 'machine',
              leading: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: includeMachineHistory
                      ? t.accentBright
                      : t.textFaint.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
              active: includeMachineHistory,
              activeBorderColor: t.accentBright.withValues(alpha: 0.5),
              onTap: () => onToggleMachineHistory(!includeMachineHistory),
              textColor: t.textStrong,
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
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              titleBlock,
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: controls,
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: titleBlock),
            const SizedBox(width: 10),
            controls,
          ],
        );
      }),
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
    final t = context.tokens;
    if (cards.isEmpty) return const SizedBox.shrink();
    // Fixed-height frame so the equalizer reads as one compact figure.
    // The bars grow upward from the bottom; a hairline baseline reinforces
    // the "chart-like" read so the skyline encodes meaning at-a-glance.
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.chromeBorderStrong,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final card in cards)
            _DiagnosisToken(
              card: card,
              active: card.id == selectedId,
              onTap: () => onTap(card.id),
            ),
          const SizedBox(width: 6),
          // Soft count chip — unobtrusive, communicates "N signals detected"
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${cards.length}',
              style: TextStyle(
                color: t.textFaint,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
    return _TerritoryBoard(
      strata: snapshot.strata,
      hotspots: hotspots,
      selectedStratumId: selectedStratumId,
      selectedHotspotPath: selectedHotspotPath,
      onStratumSelected: onStratumSelected,
      onHotspotSelected: onHotspotSelected,
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
        SizedBox(
          height: 118,
          child: _CadenceRhythmBoard(
            cadence: cadence,
            pivots: pivots,
            selectedPivotHash: selectedPivotHash,
            onPivotSelected: onPivotSelected,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _PivotList(
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
    return ListView.builder(
      itemCount: cards.length,
      itemBuilder: (context, i) {
        final card = cards[i];
        return _SignalRow(
          card: card,
          active: card.id == selectedSignalId,
          isLast: i == cards.length - 1,
          onTap: () => onSignalSelected(card.id),
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

    final t = context.tokens;

    // Compute what to show in the inspector header
    final String inspectorTitle;
    final Color inspectorAccent;
    switch (view) {
      case _XrayView.map:
        if (hotspot != null) {
          inspectorTitle = _shortPath(hotspot.path);
          inspectorAccent = _hotspotAccent(t, hotspot.kind);
        } else if (stratum != null) {
          inspectorTitle = stratum.pathPrefix;
          inspectorAccent = _stratumAccent(t, stratum.label);
        } else {
          inspectorTitle = snapshot.header.repoName;
          inspectorAccent = t.accentBright;
        }
      case _XrayView.time:
        if (pivot != null) {
          inspectorTitle = pivot.shortHash;
          inspectorAccent = t.accentBright;
        } else {
          inspectorTitle = snapshot.header.repoName;
          inspectorAccent = t.accentBright;
        }
      case _XrayView.signals:
        if (card != null) {
          inspectorTitle = _compactCardTitle(card.title);
          inspectorAccent = _signalAccent(t, card.verdict);
        } else {
          inspectorTitle = snapshot.header.repoName;
          inspectorAccent = t.accentBright;
        }
    }

    return _PanelBlock(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InspectorModeBar(title: inspectorTitle, accent: inspectorAccent),
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

class _DiagnosisToken extends StatefulWidget {
  final RepositoryXrayCardData card;
  final bool active;
  final VoidCallback onTap;
  const _DiagnosisToken(
      {required this.card, required this.active, required this.onTap});
  @override
  State<_DiagnosisToken> createState() => _DiagnosisTokenState();
}

class _DiagnosisTokenState extends State<_DiagnosisToken> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = _signalAccent(t, widget.card.verdict);
    // Height encodes confidence: tall = high confidence hard-fact,
    // short = low confidence pattern. You read the skyline of the strip.
    final conf = widget.card.confidence;
    final barH = conf == 'high'
        ? 20.0
        : conf == 'medium'
            ? 13.0
            : 7.0;
    final active = widget.active;
    final hovered = _hovered;
    final barW = active ? 7.0 : 5.0;
    final alpha = active
        ? 1.0
        : hovered
            ? 0.95
            : 0.7;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Tooltip(
          message:
              '${_compactCardTitle(widget.card.title)} · ${widget.card.confidence}',
          waitDuration: const Duration(milliseconds: 250),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: SizedBox(
              // Full-height hit target so narrow bars stay easy to click
              height: 28,
              child: Stack(
                alignment: Alignment.bottomCenter,
                clipBehavior: Clip.none,
                children: [
                  // Invisible wider hit surface
                  const SizedBox(width: 10, height: 28),
                  AnimatedContainer(
                    duration: context.motion(context.surfaceShader.duration),
                    curve: context.surfaceShader.safeCurve,
                    width: barW,
                    height: barH,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: alpha),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2.5)),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.5),
                                blurRadius: 6,
                                spreadRadius: 0.5,
                              ),
                            ]
                          : null,
                    ),
                  ),
                  // Selection caret — tiny downward marker above active bar
                  if (active)
                    Positioned(
                      top: -1,
                      child: Container(
                        width: barW,
                        height: 2,
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
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
    final t = context.tokens;
    final si = snapshot.signalIntegrity;
    final rs = snapshot.refSummary;
    final h = snapshot.header;
    final machineCount = si.rawCommitCount - si.filteredCommitCount;
    final linearRatio = si.filteredCommitCount > 0
        ? rs.mergeCommitCount / si.filteredCommitCount
        : 0.0;
    final shapeHint = rs.mergeCommitCount == 0
        ? 'linear'
        : linearRatio > 0.15
            ? 'merge-heavy'
            : 'mostly linear';

    return ListView(children: [
      // ── Hero: commit count ──────────────────────────────────
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('${si.filteredCommitCount}',
              style: TextStyle(
                  color: t.textStrong,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'JetBrainsMono')),
          const SizedBox(width: 6),
          Text('commits',
              style: TextStyle(color: t.textMuted, fontSize: 11)),
        ],
      ),
      if (machineCount > 0) ...[
        const SizedBox(height: 2),
        Text('+$machineCount machine',
            style: TextStyle(
                color: t.textFaint,
                fontSize: 10,
                fontFamily: 'JetBrainsMono')),
      ],

      const SizedBox(height: 14),

      // ── Refs & topology ─────────────────────────────────────
      _InspectorRow(
        label: 'branches',
        value: rs.remoteBranchCount > 0
            ? '${rs.localBranchCount} local · ${rs.remoteBranchCount} remote'
            : '${rs.localBranchCount} local',
      ),
      const SizedBox(height: 5),
      _InspectorRow(
        label: 'tags',
        value: rs.tagCount == 0 ? 'none' : '${rs.tagCount}',
      ),
      if (rs.stashCount > 0) ...[
        const SizedBox(height: 5),
        _InspectorRow(
            label: 'stashes', value: '${rs.stashCount}'),
      ],
      if (rs.worktreeCount > 1) ...[
        const SizedBox(height: 5),
        _InspectorRow(
            label: 'worktrees', value: '${rs.worktreeCount}'),
      ],
      if (rs.noteCount > 0) ...[
        const SizedBox(height: 5),
        _InspectorRow(label: 'notes', value: '${rs.noteCount}'),
      ],

      const SizedBox(height: 10),

      // ── History shape ──────────────────────────────────────
      _InspectorRow(
        label: 'shape',
        value: rs.mergeCommitCount == 0
            ? shapeHint
            : '$shapeHint · ${rs.mergeCommitCount} merges',
      ),
      if (rs.renameCommitCount > 0) ...[
        const SizedBox(height: 5),
        _InspectorRow(
            label: 'renames', value: '${rs.renameCommitCount}'),
      ],
      if (si.hiddenRefCount > 0) ...[
        const SizedBox(height: 5),
        _InspectorRow(
            label: 'hidden refs', value: '${si.hiddenRefCount}'),
      ],

      const SizedBox(height: 10),

      // ── Head state ─────────────────────────────────────────
      _InspectorRow(label: 'branch', value: h.branch),
      const SizedBox(height: 5),
      _InspectorRow(label: 'head', value: h.headShortHash),

      // ── Freshness footer ───────────────────────────────────
      const SizedBox(height: 14),
      Text(
        'probed ${_relativeTime(h.computedAt)}',
        style: TextStyle(
          color: t.textFaint,
          fontSize: 9.5,
          fontFamily: 'JetBrainsMono',
          letterSpacing: 0.3,
        ),
      ),
    ]);
  }
}

class _SignalInspector extends StatelessWidget {
  final RepositoryXrayCardData card;
  final void Function(String hash)? onCommitSelected;
  const _SignalInspector({required this.card, this.onCommitSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = _signalAccent(t, card.verdict);
    return ListView(children: [
      // Verdict badge
      _Tag(text: card.verdict.replaceAll('-', ' '), color: accent),
      const SizedBox(height: 10),
      // Claim is the primary insight
      Text(card.claim,
          style: TextStyle(
              color: t.textStrong, fontSize: 12, height: 1.55)),
      if (card.evidence.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (var i = 0; i < card.evidence.length; i++) ...[
          _InspectorRow(
              label: card.evidence[i].label,
              value: card.evidence[i].detail),
          if (i < card.evidence.length - 1) const SizedBox(height: 5),
        ],
      ],
      if (card.primaryPath != null) ...[
        const SizedBox(height: 5),
        _InspectorRow(label: 'path', value: card.primaryPath!),
      ],
      if (card.primaryCommitHash != null && onCommitSelected != null) ...[
        const SizedBox(height: 12),
        _MiniButton(
            label: 'Open commit',
            icon: 'history',
            enabled: true,
            onTap: () => onCommitSelected!(card.primaryCommitHash!)),
      ],
    ]);
  }
}

class _HotspotInspector extends StatelessWidget {
  final RepositoryXrayHotspotData hotspot;
  final void Function(String hash)? onCommitSelected;
  const _HotspotInspector({required this.hotspot, this.onCommitSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(children: [
      // Full path in mono, truncated
      Text(hotspot.path,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: t.textMuted,
              fontSize: 9.5,
              fontFamily: 'JetBrainsMono')),
      const SizedBox(height: 12),
      // Touch count + owner count as large numbers side-by-side
      Row(children: [
        _InspectorStat(
            value: '${hotspot.touchCount}', label: 'touches'),
        const SizedBox(width: 20),
        _InspectorStat(
            value: '${hotspot.ownerCount}',
            label:
                'owner${hotspot.ownerCount == 1 ? '' : 's'}'),
      ]),
      const SizedBox(height: 10),
      _InspectorRow(
          label: 'last touched', value: hotspot.lastTouchedAt),
      if (hotspot.latestCommitHash != null && onCommitSelected != null) ...[
        const SizedBox(height: 12),
        _MiniButton(
            label: hotspot.latestShortHash ?? 'Open commit',
            icon: 'history',
            enabled: true,
            onTap: () => onCommitSelected!(hotspot.latestCommitHash!)),
      ],
    ]);
  }
}

class _StratumInspector extends StatelessWidget {
  final RepositoryXrayStratumData stratum;
  const _StratumInspector({required this.stratum});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = _stratumAccent(t, stratum.label);
    return ListView(children: [
      // Label tag
      _Tag(text: _compactStratumLabel(stratum.label), color: accent),
      const SizedBox(height: 8),
      // Path
      Text(stratum.pathPrefix,
          style: TextStyle(
              color: t.textStrong,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: 'JetBrainsMono')),
      if (stratum.summary.isNotEmpty) ...[
        const SizedBox(height: 10),
        // Summary is the most valuable info
        Text(stratum.summary,
            style:
                TextStyle(color: t.textNormal, fontSize: 11, height: 1.5)),
      ],
      const SizedBox(height: 12),
      Row(children: [
        _InspectorStat(
            value: '${stratum.touchCount}', label: 'touches'),
        const SizedBox(width: 20),
        _InspectorStat(
            value: '${stratum.ownerCount}',
            label: 'owner${stratum.ownerCount == 1 ? '' : 's'}'),
      ]),
      const SizedBox(height: 6),
      _InspectorRow(
          label: 'last touched', value: stratum.lastTouchedAt),
    ]);
  }
}

class _PivotInspector extends StatelessWidget {
  final RepositoryXrayPivotCommitData pivot;
  final void Function(String hash)? onCommitSelected;
  const _PivotInspector({required this.pivot, this.onCommitSelected});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ListView(children: [
      // Subject as hero
      Text(pivot.subject,
          style: TextStyle(
              color: t.textStrong,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.45)),
      const SizedBox(height: 10),
      // Hash + date + author as metadata row
      Wrap(spacing: 8, runSpacing: 4, children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: t.accentBright.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(pivot.shortHash,
              style: TextStyle(
                  color: t.accentBright,
                  fontSize: 10,
                  fontFamily: 'JetBrainsMono')),
        ),
        Text(pivot.authoredAt,
            style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono')),
        Text(pivot.authorName,
            style: TextStyle(color: t.textMuted, fontSize: 10)),
      ]),
      const SizedBox(height: 14),
      // Diff stats as colored numbers
      Row(children: [
        Text('+${pivot.insertions}',
            style: TextStyle(
                color: t.stateAdded,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'JetBrainsMono')),
        const SizedBox(width: 8),
        Text('-${pivot.deletions}',
            style: TextStyle(
                color: t.stateDeleted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: 'JetBrainsMono')),
        const SizedBox(width: 10),
        Text(
            '${pivot.filesChanged} file${pivot.filesChanged == 1 ? '' : 's'}',
            style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono')),
      ]),
      if (onCommitSelected != null) ...[
        const SizedBox(height: 14),
        _MiniButton(
            label: 'Open commit',
            icon: 'history',
            enabled: true,
            onTap: () => onCommitSelected!(pivot.commitHash)),
      ],
    ]);
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
  final String title;
  final Color accent;
  const _InspectorModeBar({required this.title, required this.accent});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              fontFamily: 'JetBrainsMono',
            ),
          ),
        ),
      ],
    );
  }
}

class _InspectorStat extends StatelessWidget {
  final String value;
  final String label;
  const _InspectorStat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            color: t.textStrong,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            fontFamily: 'JetBrainsMono',
            height: 1,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: t.textMuted,
            fontSize: 9.5,
            letterSpacing: 0.4,
          ),
        ),
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

    return InteractionFeedback(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(999),
      onHoverChanged: (h) => setState(() => _hovered = h),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: context.motion(context.surfaceShader.duration),
          curve: context.surfaceShader.safeCurve,
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

// ── Territory: unified treemap of strata + hotspots ──────────────────────────
//
// Replaces the old Strata bars + Heat grid. Top-level directories become big
// territory tiles sized by touch count; hot files/subdirs nest inside their
// parent stratum as smaller tiles. Orphan hotspots (no matching stratum) sit
// as their own top-level tiles. Clicking any tile selects it — the inspector
// on the right fills in with the corresponding stratum or hotspot details.

class _Parcel {
  final String key;
  final String label;
  final Color accent;
  final double value;
  final int count;
  final String? tagText;
  final bool selected;
  final bool isChild;
  final VoidCallback onTap;
  final List<_Parcel> children;

  const _Parcel({
    required this.key,
    required this.label,
    required this.accent,
    required this.value,
    required this.count,
    required this.tagText,
    required this.selected,
    required this.isChild,
    required this.onTap,
    required this.children,
  });
}

class _TreemapLayout {
  final Rect rect;
  final _Parcel parcel;
  final List<_TreemapLayout> children;
  const _TreemapLayout(this.rect, this.parcel, this.children);
}

/// Squarified-treemap layout (Bruls, Huijbregts & van Wijk).
/// Recurses for children so strata cells contain their hotspots.
List<_TreemapLayout> _layoutTreemap(List<_Parcel> parcels, Rect bounds) {
  if (parcels.isEmpty || bounds.width <= 0 || bounds.height <= 0) {
    return const [];
  }
  final filtered = parcels.where((p) => p.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (filtered.isEmpty) return const [];

  final total = filtered.fold<double>(0, (s, p) => s + p.value);
  final area = bounds.width * bounds.height;
  final scaled = filtered.map((p) => p.value * area / total).toList();

  final flat = <_TreemapLayout>[];
  _squarify(filtered, scaled, bounds, flat);

  return flat.map((layout) {
    if (layout.parcel.children.isEmpty) return layout;
    // Reserve space for the parent's label
    final labelH = layout.rect.height > 56 ? 24.0 : 0.0;
    const inset = 3.0;
    final childBounds = Rect.fromLTWH(
      layout.rect.left + inset,
      layout.rect.top + labelH + inset * 0.5,
      math.max(0, layout.rect.width - inset * 2),
      math.max(0, layout.rect.height - labelH - inset * 1.5),
    );
    if (childBounds.width < 40 || childBounds.height < 24) return layout;
    return _TreemapLayout(
      layout.rect,
      layout.parcel,
      _layoutTreemap(layout.parcel.children, childBounds),
    );
  }).toList();
}

void _squarify(List<_Parcel> parcels, List<double> scaled, Rect bounds,
    List<_TreemapLayout> out) {
  double worst(List<int> indices, double shortSide) {
    if (indices.isEmpty) return double.infinity;
    double s = 0, rmax = 0, rmin = double.infinity;
    for (final i in indices) {
      final v = scaled[i];
      s += v;
      if (v > rmax) rmax = v;
      if (v < rmin) rmin = v;
    }
    if (s == 0 || rmin == 0) return double.infinity;
    final ss = s * s;
    final ww = shortSide * shortSide;
    return math.max(ww * rmax / ss, ss / (ww * rmin));
  }

  int idx = 0;
  Rect remaining = bounds;
  final row = <int>[];
  while (idx < parcels.length) {
    if (remaining.width <= 0 || remaining.height <= 0) break;
    final shortSide = math.min(remaining.width, remaining.height);
    if (row.isEmpty) {
      row.add(idx++);
      continue;
    }
    final currentWorst = worst(row, shortSide);
    final candidateWorst = worst([...row, idx], shortSide);
    if (candidateWorst <= currentWorst) {
      row.add(idx++);
    } else {
      remaining = _placeRow(row, parcels, scaled, remaining, out);
      row.clear();
    }
  }
  if (row.isNotEmpty) {
    _placeRow(row, parcels, scaled, remaining, out);
  }
}

Rect _placeRow(List<int> rowIndices, List<_Parcel> parcels,
    List<double> scaled, Rect bounds, List<_TreemapLayout> out) {
  final rowSum = rowIndices.fold<double>(0, (s, i) => s + scaled[i]);
  final shortSide = math.min(bounds.width, bounds.height);
  if (rowSum <= 0 || shortSide <= 0) return bounds;
  final rowThickness = rowSum / shortSide;
  // When bounds are wider than tall, the row sits on the LEFT and cells stack
  // vertically. When taller than wide, row sits on TOP, cells side-by-side.
  final stackVertical = bounds.width > bounds.height;
  double offset = 0;
  for (final i in rowIndices) {
    final extent = scaled[i] / rowThickness;
    final rect = stackVertical
        ? Rect.fromLTWH(
            bounds.left, bounds.top + offset, rowThickness, extent)
        : Rect.fromLTWH(
            bounds.left + offset, bounds.top, extent, rowThickness);
    out.add(_TreemapLayout(rect, parcels[i], const []));
    offset += extent;
  }
  return stackVertical
      ? Rect.fromLTWH(bounds.left + rowThickness, bounds.top,
          bounds.width - rowThickness, bounds.height)
      : Rect.fromLTWH(bounds.left, bounds.top + rowThickness, bounds.width,
          bounds.height - rowThickness);
}

class _TerritoryBoard extends StatelessWidget {
  final List<RepositoryXrayStratumData> strata;
  final List<RepositoryXrayHotspotData> hotspots;
  final String? selectedStratumId;
  final String? selectedHotspotPath;
  final ValueChanged<String> onStratumSelected;
  final ValueChanged<String> onHotspotSelected;

  const _TerritoryBoard({
    required this.strata,
    required this.hotspots,
    required this.selectedStratumId,
    required this.selectedHotspotPath,
    required this.onStratumSelected,
    required this.onHotspotSelected,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Map every hotspot to a parent stratum (or null = orphan)
    String norm(String p) => p.replaceAll('\\', '/');
    final childMap = <String?, List<RepositoryXrayHotspotData>>{};
    for (final h in hotspots) {
      final hp = norm(h.path);
      String? parentId;
      for (final s in strata) {
        final sp = norm(s.pathPrefix);
        if (hp == sp) {
          // Hotspot IS the stratum itself — skip duplicate; the stratum tile
          // already represents it.
          parentId = '__DROP__';
          break;
        }
        if (hp.startsWith('$sp/')) {
          parentId = s.id;
          break;
        }
      }
      if (parentId == '__DROP__') continue;
      childMap.putIfAbsent(parentId, () => []).add(h);
    }

    _Parcel hotspotParcel(RepositoryXrayHotspotData h, {required bool isChild}) {
      final accent = _hotspotAccent(t, h.kind);
      return _Parcel(
        key: 'h:${h.path}',
        label: _shortPath(h.path),
        accent: accent,
        value: h.touchCount.toDouble(),
        count: h.touchCount,
        tagText: null,
        selected: selectedHotspotPath == h.path,
        isChild: isChild,
        onTap: () => onHotspotSelected(h.path),
        children: const [],
      );
    }

    final topLevel = <_Parcel>[];
    for (final s in strata) {
      final accent = _stratumAccent(t, s.label);
      final children = (childMap[s.id] ?? const <RepositoryXrayHotspotData>[])
          .map((h) => hotspotParcel(h, isChild: true))
          .toList();
      topLevel.add(_Parcel(
        key: 's:${s.id}',
        label: s.pathPrefix,
        accent: accent,
        value: s.touchCount.toDouble(),
        count: s.touchCount,
        tagText: _compactStratumLabel(s.label),
        selected: selectedStratumId == s.id,
        isChild: false,
        onTap: () => onStratumSelected(s.id),
        children: children,
      ));
    }
    for (final h in childMap[null] ?? const <RepositoryXrayHotspotData>[]) {
      topLevel.add(hotspotParcel(h, isChild: false));
    }

    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      elevated: false,
      innerHighlight: true,
      glaze: false,
      borderAlpha: 0.14,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _BoardHeader(label: 'Territory'),
              const Spacer(),
              Text(
                '${topLevel.length}',
                style: TextStyle(
                  color: t.textFaint,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final cells = _layoutTreemap(
                  topLevel,
                  Rect.fromLTWH(0, 0, c.maxWidth, c.maxHeight),
                );
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: _renderCells(cells),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _renderCells(List<_TreemapLayout> cells) {
    final out = <Widget>[];
    for (final cell in cells) {
      out.add(Positioned(
        left: cell.rect.left,
        top: cell.rect.top,
        width: cell.rect.width,
        height: cell.rect.height,
        child: _TerritoryCell(
          parcel: cell.parcel,
          hasChildren: cell.children.isNotEmpty,
        ),
      ));
      // Children painted AFTER the parent so they sit on top visually.
      // The parent's own label sits in a compact top "header band", below
      // which is canvas that children fill.
      if (cell.children.isNotEmpty) {
        out.addAll(_renderCells(cell.children));
      }
    }
    return out;
  }
}

class _TerritoryCell extends StatelessWidget {
  final _Parcel parcel;
  final bool hasChildren;
  const _TerritoryCell({
    required this.parcel,
    required this.hasChildren,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final selected = parcel.selected;
    final isChild = parcel.isChild;
    final accent = parcel.accent;
    return LayoutBuilder(builder: (context, c) {
      final big = c.maxWidth > 140 && c.maxHeight > 60;
      final medium = c.maxWidth > 80 && c.maxHeight > 30;
      final tiny = c.maxWidth < 40 || c.maxHeight < 18;
      // Region = cell that contains nested child cells. Label goes into a
      // compact top band so children don't overlap the text.
      final isRegion = hasChildren && !tiny;
      final radius = isChild ? 4.0 : 7.0;
      final bgAlpha = selected
          ? 0.14
          : isRegion
              ? 0.11
              : (isChild ? 0.07 : 0.09);

      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: parcel.onTap,
          child: Tooltip(
            message: '${parcel.label}  ·  ${parcel.count}×',
            waitDuration: const Duration(milliseconds: 400),
            child: AnimatedContainer(
              duration: context.motion(context.surfaceShader.duration),
              curve: context.surfaceShader.safeCurve,
              margin: EdgeInsets.all(isChild ? 1.5 : 2.5),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    accent.withValues(alpha: bgAlpha * 1.25),
                    accent.withValues(alpha: bgAlpha * 0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: 0.6)
                      : t.chromeBorder.withValues(alpha: 0.16),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius - 1),
                child: tiny
                    ? Container(color: accent.withValues(alpha: 0.22))
                    : isRegion
                        ? _regionLayout(t, big: big, medium: medium)
                        : _headerRow(t,
                            big: big, medium: medium, compact: false),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _regionLayout(AppTokens t,
      {required bool big, required bool medium}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 26,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: parcel.accent.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: _headerRow(t, big: big, medium: medium, compact: true),
        ),
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }

  Widget _headerRow(
    AppTokens t, {
    required bool big,
    required bool medium,
    required bool compact,
  }) {
    final selected = parcel.selected;
    final isChild = parcel.isChild;
    final accent = parcel.accent;
    return Row(children: [
      Container(
        width: isChild ? 2 : 3,
        color: accent.withValues(alpha: selected ? 0.95 : 0.7),
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              parcel.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textStrong,
                fontSize: compact ? 11 : (big ? 12 : (medium ? 10.5 : 9.5)),
                fontWeight: FontWeight.w700,
                fontFamily: isChild ? 'JetBrainsMono' : null,
                letterSpacing: 0.1,
              ),
            ),
            if (!compact && medium) ...[
              const SizedBox(height: 1),
              Text(
                '${parcel.count}×',
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 9,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ],
          ],
        ),
      ),
      // Inline count in the compact header-band (next to label)
      if (compact) ...[
        Text(
          '${parcel.count}×',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w600,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(width: 6),
      ],
      if (big && parcel.tagText != null) ...[
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: _Tag(text: parcel.tagText!, color: accent),
        ),
      ] else
        const SizedBox(width: 4),
    ]);
  }
}

class _BoardHeader extends StatelessWidget {
  final String label;
  const _BoardHeader({required this.label});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label,
      style: TextStyle(
        color: t.textMuted,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _CadenceRhythmBoard extends StatelessWidget {
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;
  const _CadenceRhythmBoard(
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
      for (final c in cadence)
        if (_cadenceDateEnd(c) != null) _cadenceDateEnd(c)!,
    ];
    if (allDates.isEmpty) return const SizedBox.shrink();

    final minDate = allDates.reduce((a, b) => a.isBefore(b) ? a : b);
    final maxDate = allDates.reduce((a, b) => a.isAfter(b) ? a : b);
    final spanDays = math.max(maxDate.difference(minDate).inDays.abs(), 1);

    double xFor(DateTime date, double width) =>
        ((date.difference(minDate).inDays) / spanDays).clamp(0.0, 1.0) *
            (width - 32) +
        16;

    final maxBurst = cadence
        .where((c) => c.kind == 'burst')
        .fold<int>(1, (m, c) => math.max(m, c.count));

    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      elevated: false,
      innerHighlight: true,
      glaze: false,
      borderAlpha: 0.14,
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final h = box.maxHeight;
        // Bottom chrome zones (stacked from the baseline down):
        //   [dates: Apr 3 · Apr 10 · Apr 12]   ← one line under each burst
        //   [reflog: ● 46]                     ← one line, accent marks
        const burstDateH = 14.0;
        const reflogH = 16.0;
        final barAreaH = h - burstDateH - reflogH;
        final maxBarH = (barAreaH - 20).clamp(10.0, double.infinity);

        double barH(RepositoryXrayCadenceData item) =>
            ((item.count / maxBurst).clamp(0.15, 1.0) * maxBarH)
                .clamp(8.0, maxBarH);

        return Stack(clipBehavior: Clip.hardEdge, children: [
          // ── Baseline ──────────────────────────────────────────
          Positioned(
            left: 12,
            right: 12,
            top: barAreaH,
            height: 1,
            child:
                Container(color: t.chromeBorder.withValues(alpha: 0.22)),
          ),

          // ── Gap fills + day-count label ───────────────────────
          for (final item in cadence)
            if (item.kind == 'gap' &&
                _cadenceDate(item) != null &&
                _cadenceDateEnd(item) != null) ...[
              Positioned(
                left: xFor(_cadenceDate(item)!, w),
                top: 0,
                width: math.max(
                    2.0,
                    xFor(_cadenceDateEnd(item)!, w) -
                        xFor(_cadenceDate(item)!, w)),
                height: barAreaH,
                child: Tooltip(
                  message: item.detail.isNotEmpty
                      ? item.detail
                      : '${item.count}-day gap · ${item.label}',
                  waitDuration: const Duration(milliseconds: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.chromeBorder.withValues(alpha: 0.05),
                      border: Border.symmetric(
                        vertical: BorderSide(
                            color: t.chromeBorder.withValues(alpha: 0.1),
                            width: 0.5),
                      ),
                    ),
                  ),
                ),
              ),
              // Day-count label centered in the gap region — makes
              // "empty space" communicate "7d of quiet" instantly.
              Positioned(
                left: ((xFor(_cadenceDate(item)!, w) +
                                xFor(_cadenceDateEnd(item)!, w)) /
                            2 -
                        18)
                    .clamp(0.0, w - 36),
                top: (barAreaH / 2 - 7).clamp(2.0, barAreaH - 14),
                width: 36,
                child: Text(
                  '${item.count}d',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textFaint.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'JetBrainsMono',
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],

          // ── Pivot hairlines ────────────────────────────────────
          for (final pivot in pivots)
            if (DateTime.tryParse(pivot.authoredAt) != null)
              Positioned(
                left: xFor(DateTime.parse(pivot.authoredAt), w) - 0.5,
                top: 0,
                width: 1,
                height: barAreaH,
                child: Container(
                  color: pivot.commitHash == selectedPivotHash
                      ? t.accentBright.withValues(alpha: 0.65)
                      : t.chromeBorder.withValues(alpha: 0.22),
                ),
              ),

          // ── Burst bars + count labels + date labels ────────────
          for (final item in cadence)
            if (item.kind == 'burst' && _cadenceDate(item) != null) ...[
              // The bar itself
              Positioned(
                left: (xFor(_cadenceDate(item)!, w) - 14)
                    .clamp(0.0, w - 28),
                top: barAreaH - barH(item),
                width: 28,
                height: barH(item),
                child: Tooltip(
                  message: item.detail.isNotEmpty
                      ? item.detail
                      : '${item.count} commits on ${item.label}',
                  waitDuration: const Duration(milliseconds: 400),
                  child: Container(
                    decoration: BoxDecoration(
                      color: _cadenceAccent(t, 'burst')
                          .withValues(alpha: 0.82),
                      borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4)),
                    ),
                  ),
                ),
              ),
              // Count label above the bar
              Positioned(
                left: (xFor(_cadenceDate(item)!, w) - 16)
                    .clamp(0.0, w - 32),
                top: math.max(0, barAreaH - barH(item) - 16),
                width: 32,
                child: Text(
                  '${item.count}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ),
              // Date label below the bar (Apr 3, Apr 10, Apr 12...)
              Positioned(
                left: (xFor(_cadenceDate(item)!, w) - 22)
                    .clamp(0.0, w - 44),
                top: barAreaH + 2,
                width: 44,
                child: Text(
                  _fmtDateMD(_cadenceDate(item)!),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'JetBrainsMono',
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ],

          // ── Reflog markers (centered under their date column) ──
          // Same 44px-wide anchor as the burst date label above, so when a
          // reflog and burst share a day they stack in a clean column.
          for (final item in cadence)
            if (item.kind == 'reflog' && _cadenceDate(item) != null)
              Positioned(
                left: (xFor(_cadenceDate(item)!, w) - 22)
                    .clamp(0.0, w - 44),
                top: barAreaH + burstDateH + 1,
                width: 44,
                height: 12,
                child: Tooltip(
                  message: item.detail.isNotEmpty
                      ? item.detail
                      : '${item.count} reflog events on ${item.label}',
                  waitDuration: const Duration(milliseconds: 400),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                            color: _cadenceAccent(t, 'reflog'),
                            shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 3),
                      Text('${item.count}',
                          style: TextStyle(
                              color: _cadenceAccent(t, 'reflog'),
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'JetBrainsMono')),
                    ],
                  ),
                ),
              ),

          // ── Interactive tap areas ──────────────────────────────
          for (final pivot in pivots)
            if (DateTime.tryParse(pivot.authoredAt) != null)
              Positioned(
                left: (xFor(DateTime.parse(pivot.authoredAt), w) - 20)
                    .clamp(0.0, w - 40),
                top: 0,
                width: 40,
                height: barAreaH,
                child: Tooltip(
                  message:
                      '${pivot.shortHash}  ·  ${pivot.filesChanged}f  ·  ${pivot.subject}',
                  waitDuration: const Duration(milliseconds: 300),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () => onPivotSelected(pivot.commitHash),
                      behavior: HitTestBehavior.translucent,
                    ),
                  ),
                ),
              ),
        ]);
      }),
    );
  }
}

// ── Pivot list (replaces horizontal scrolling strip) ──────────────────────────

class _PivotList extends StatelessWidget {
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;
  const _PivotList(
      {required this.pivots,
      required this.selectedPivotHash,
      required this.onPivotSelected});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final maxFiles =
        pivots.fold<int>(1, (m, p) => math.max(m, p.filesChanged));

    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      elevated: false,
      innerHighlight: false,
      glaze: false,
      borderAlpha: 0.14,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: pivots.length,
          itemBuilder: (context, i) {
            final p = pivots[i];
            final active = p.commitHash == selectedPivotHash;
            final frac = (p.filesChanged / maxFiles).clamp(0.04, 1.0);
            return MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => onPivotSelected(p.commitHash),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 80),
                  height: 36,
                  decoration: BoxDecoration(
                    color: active ? t.itemActiveBg : Colors.transparent,
                    border: Border(
                      left: BorderSide(
                        color:
                            active ? t.accentBright : Colors.transparent,
                        width: 3,
                      ),
                      bottom: i < pivots.length - 1
                          ? BorderSide(
                              color:
                                  t.chromeBorderFaint)
                          : BorderSide.none,
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                        active ? 9 : 12, 0, 12, 0),
                    child: Row(children: [
                      // Date
                      SizedBox(
                        width: 46,
                        child: Text(
                          _fmtDateCompact(p.authoredAt),
                          style: TextStyle(
                            color: t.textFaint,
                            fontSize: 9.5,
                            fontFamily: 'JetBrainsMono',
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Hash chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: t.accentBright.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(p.shortHash,
                            style: TextStyle(
                                color: t.accentBright,
                                fontSize: 9,
                                fontFamily: 'JetBrainsMono')),
                      ),
                      const SizedBox(width: 8),
                      // Subject
                      Expanded(
                        child: Text(
                          p.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: active ? t.textStrong : t.textNormal,
                            fontSize: 11,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // File count + heat bar
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${p.filesChanged}f',
                              style: TextStyle(
                                  color: t.textFaint,
                                  fontSize: 8.5,
                                  fontFamily: 'JetBrainsMono')),
                          const SizedBox(height: 2),
                          Container(
                            height: 3,
                            width: (28 * frac).clamp(3.0, 28.0),
                            decoration: BoxDecoration(
                              color: t.stateModified
                                  .withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Signal row (replaces grid tile) ──────────────────────────────────────────

class _SignalRow extends StatelessWidget {
  final RepositoryXrayCardData card;
  final bool active;
  final bool isLast;
  final VoidCallback onTap;
  const _SignalRow(
      {required this.card,
      required this.active,
      required this.isLast,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = _signalAccent(t, card.verdict);
    final confLevel = card.confidence == 'high'
        ? 3
        : card.confidence == 'medium'
            ? 2
            : 1;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          decoration: BoxDecoration(
            color: active ? t.itemActiveBg : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: active ? accent : accent.withValues(alpha: 0.35),
                width: 3,
              ),
              bottom: isLast
                  ? BorderSide.none
                  : BorderSide(
                      color: t.chromeBorderFaint),
            ),
          ),
          padding:
              EdgeInsets.fromLTRB(active ? 9 : 12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _compactCardTitle(card.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? t.textStrong : t.textNormal,
                        fontSize: 12,
                        fontWeight: active
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      card.claim,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: t.textMuted, fontSize: 10, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Signal-strength confidence bars (ascending heights)
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(3, (i) {
                  final filled = i < confLevel;
                  return Padding(
                    padding: EdgeInsets.only(left: i > 0 ? 2 : 0),
                    child: Container(
                      width: 4,
                      height: 4.0 + i * 3.5,
                      decoration: BoxDecoration(
                        color: filled
                            ? accent
                            : t.chromeBorder.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  if (lower.contains('reflog') ||
      lower.contains('intense local editing')) return 'reflog';
  if (lower.contains('hotspot concentration') ||
      lower.contains('narrow')) return 'narrow hotspot';
  return title.toLowerCase();
}

String _compactStratumLabel(String label) {
  final lower = label.toLowerCase();
  if (lower.contains('current')) return 'current';
  if (lower.contains('architecture')) return 'legacy';
  return lower;
}

Color _signalAccent(AppTokens t, String verdict) {
  // Palette hierarchy in this panel:
  //   accentBright (bright blue) → hard/definite/primary
  //   chromeAccent (muted teal)  → secondary/observed pattern
  //   stateModified (amber)      → reserved for activity heat (bursts,
  //                                 hot directories). Not used here so we
  //                                 don't overload the "warning-ish" feel.
  return switch (verdict) {
    'hard-fact' => t.accentBright,
    'strong-pattern' => t.chromeAccent,
    _ => t.chromeAccent,
  };
}

Color _stratumAccent(AppTokens t, String label) {
  final lower = label.toLowerCase();
  if (lower.contains('current')) return t.stateAdded;
  // "legacy" / "architecture migration" zones → muted teal (chromeAccent)
  // instead of amber. Amber stays reserved for activity-heat encodings
  // (bursts and hot directories) where warmth is metaphorically correct.
  if (lower.contains('legacy') || lower.contains('architecture')) {
    return t.chromeAccent;
  }
  return t.accentBright;
}

Color _hotspotAccent(AppTokens t, String kind) {
  return kind == 'directory' ? t.stateModified : t.accentBright;
}

Color _cadenceAccent(AppTokens t, String kind) {
  return switch (kind) {
    'burst' => t.stateModified,
    'gap' => t.textMuted,
    _ => t.accentBright,
  };
}

DateTime? _cadenceDateEnd(RepositoryXrayCadenceData item) {
  if (item.kind == 'gap') {
    final parts = item.label.split('->');
    if (parts.length > 1 && DateTime.tryParse(parts.last.trim()) != null) {
      return DateTime.parse(parts.last.trim());
    }
  }
  return null;
}

String _fmtDateMD(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}';
}

String _relativeTime(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final diff = DateTime.now().difference(d);
  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return iso.length >= 10 ? iso.substring(0, 10) : iso;
}

String _fmtDateCompact(String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) {
    return isoDate.length > 5 ? isoDate.substring(5) : isoDate;
  }
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}';
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
    return InteractionFeedback(
      onTap: widget.enabled ? widget.onTap : null,
      borderRadius: BorderRadius.circular(6),
      onHoverChanged: (h) => setState(() => _hovered = h),
      cursor: widget.enabled
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: Listener(
        onPointerDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
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
