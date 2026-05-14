import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../../app/ai_activity_state.dart';
import '../../app/ai_settings_state.dart';
import '../../app/repository_state.dart';
import '../../app/repository_xray_state.dart';
import '../../backend/aperture_sweep.dart'
    show ApertureEvent, ApertureSample, ApertureSweep, CenterOfGravityStratum;
import '../../backend/dtos.dart';
import '../../backend/engram_fit.dart'
    show branchLabelConverging, branchLabelDiverging, branchLabelSteady;
import '../../backend/ai.dart';
import '../../backend/repo_summary/api.dart';
import '../../backend/repo_summary/types.dart' as rs;
import '../../components/icons/app_icons.dart';
import '../../ui/control_chrome.dart';
import '../../ui/form_controls.dart';
import '../../ui/design_primitives.dart';
import '../../ui/interaction_feedback.dart';
import '../../ui/material_surface.dart';
import '../../ui/motion.dart';
import '../../ui/status_view.dart';
import '../../ui/tokens.dart';

enum _XrayView { map, time, signals, summary }

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

  // Summary state — hoisted here so it survives tab switches and
  // panel close/reopen within the same repo session.
  rs.RepoDoc? _summaryDoc;
  String? _summaryMarkdown;
  String? _summaryError;
  String? _summaryPresentedHtml;
  String? _summaryRepoPath;

  void _onSummaryStateChanged(
    rs.RepoDoc? doc, String? markdown, String? error, String? presentedHtml,
  ) {
    _summaryDoc = doc;
    _summaryMarkdown = markdown;
    _summaryError = error;
    _summaryPresentedHtml = presentedHtml;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repoPath = context.read<RepositoryState>().activePath;
    if (repoPath != _summaryRepoPath) {
      _summaryRepoPath = repoPath;
      _summaryDoc = null;
      _summaryMarkdown = null;
      _summaryError = null;
      _summaryPresentedHtml = null;
    }
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
    final repoPath = context.select<RepositoryState, String?>(
      (s) => s.activePath,
    );
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
                summaryDoc: _summaryDoc,
                summaryMarkdown: _summaryMarkdown,
                summaryError: _summaryError,
                summaryPresentedHtml: _summaryPresentedHtml,
                onSummaryStateChanged: _onSummaryStateChanged,
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

              // Summary view fills the whole area; no inspector sidebar.
              if (_view == _XrayView.summary) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: main,
                );
              }
              if (showSideInspector) {
                // Map view gets a floating inspector — territory tiles
                // flow around it in an L-shape via the obstacle param,
                // so the empty space below the (short) metadata card
                // becomes more room for tiles.
                if (_view == _XrayView.map) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: LayoutBuilder(builder: (ctx, c) {
                      // Match the previous flex 5/13 inspector width with a
                      // 12px gap; clamp to a comfortable range so tiny or
                      // huge windows still look right.
                      final rawInspectorW = (c.maxWidth - 12) * 5 / 13;
                      final inspectorW = rawInspectorW.clamp(280.0, 460.0);
                      // The metadata card is naturally short. A capped fixed
                      // height keeps geometry deterministic for the
                      // territory's L-shape carve-out (no two-pass measure).
                      final inspectorH = math.min(c.maxHeight * 0.55, 380.0);

                      // Convert the inspector's panel-local rect into the
                      // territory's *treemap-interior* coords. The territory
                      // sits inside two surfaces, each contributing chrome:
                      //   _PanelBlock — Padding(12) + MaterialSurface
                      //                 1px border ≈ 13px inset.
                      //   _TerritoryBoard — MaterialSurface 1px border +
                      //                     Padding(12, 10, 12, 12) +
                      //                     header row (~18px) +
                      //                     8px gap = 13/29 + content.
                      // Combined origin: (26, 42 + headerH). The previous
                      // value was 6px short on the bottom side, which is
                      // exactly the overflow the docs/* tiles reported.
                      const treemapOriginX = 13.0 + 13.0; // 26
                      const treemapOriginY =
                          13.0 + 13.0 + 18.0 + 8.0; // 52
                      final inspectorPanelLeft = c.maxWidth - inspectorW;
                      // 12px breathing gap between inspector bottom and
                      // the tiles that flow underneath.
                      final inspectorPanelBottom = inspectorH + 12.0;
                      final obstacle = Rect.fromLTRB(
                        math.max(0, inspectorPanelLeft - treemapOriginX),
                        0, // inspector top extends above the treemap origin
                        c.maxWidth - treemapOriginX,
                        math.max(0, inspectorPanelBottom - treemapOriginY),
                      );

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: _MainViewport(
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
                                  _selectedSignalId =
                                      _selectedSignalId == id ? null : id),
                              onHotspotSelected: (path) => setState(() =>
                                  _selectedHotspotPath =
                                      _selectedHotspotPath == path
                                          ? null
                                          : path),
                              onPivotSelected: (hash) => setState(() =>
                                  _selectedPivotHash =
                                      _selectedPivotHash == hash ? null : hash),
                              onStratumSelected: (id) => setState(() =>
                                  _selectedStratumId =
                                      _selectedStratumId == id ? null : id),
                              summaryDoc: _summaryDoc,
                              summaryMarkdown: _summaryMarkdown,
                              summaryError: _summaryError,
                              summaryPresentedHtml: _summaryPresentedHtml,
                              onSummaryStateChanged: _onSummaryStateChanged,
                              mapObstacle: obstacle,
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            width: inspectorW,
                            height: inspectorH,
                            child: inspector,
                          ),
                        ],
                      );
                    }),
                  );
                }
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
                      fontFamily: AppFonts.mono,
                    ),
                  ),
                  if (snapshot.metabolism.activeDays > 0) ...[
                    const SizedBox(height: 2),
                    _MetabolismLine(metabolism: snapshot.metabolism),
                  ],
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
                fontFamily: AppFonts.mono,
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
        const SizedBox(width: 8),
        _TabChip(
            label: 'Summary',
            icon: 'repo-summary',
            active: current == _XrayView.summary,
            onTap: () => onChanged(_XrayView.summary)),
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

  /// Optional carve-out for the map view's L-shape territory layout
  /// (treemap-interior coords). Ignored for non-map views.
  final Rect? mapObstacle;

  final rs.RepoDoc? summaryDoc;
  final String? summaryMarkdown;
  final String? summaryError;
  final String? summaryPresentedHtml;
  final void Function(rs.RepoDoc?, String?, String?, String?)
      onSummaryStateChanged;

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
    required this.summaryDoc,
    required this.summaryMarkdown,
    required this.summaryError,
    required this.summaryPresentedHtml,
    required this.onSummaryStateChanged,
    this.mapObstacle,
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
            obstacle: mapObstacle,
          ),
        _XrayView.time => _TimeView(
            repoPath: snapshot.header.repoPath,
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
        _XrayView.summary => _SummaryView(
          repoPath: snapshot.header.repoPath,
          initialDoc: summaryDoc,
          initialMarkdown: summaryMarkdown,
          initialError: summaryError,
          initialPresentedHtml: summaryPresentedHtml,
          onStateChanged: onSummaryStateChanged,
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

  /// Optional rect (in the territory board's *treemap interior* coord
  /// space) that the treemap should avoid placing tiles in. Used by the
  /// L-shape layout where the inspector floats top-right and territory
  /// tiles flow underneath it.
  final Rect? obstacle;

  const _MapView({
    required this.snapshot,
    required this.hotspots,
    required this.selectedHotspotPath,
    required this.selectedStratumId,
    required this.onHotspotSelected,
    required this.onStratumSelected,
    this.obstacle,
  });

  @override
  Widget build(BuildContext context) {
    final obsMap = <String, int>{};
    final rc = snapshot.reviewerConstellations;
    if (rc != null) {
      for (final r in rc.reviewers) {
        for (final p in r.topPaths) {
          obsMap[p] = (obsMap[p] ?? 0) + 1;
        }
      }
    }
    return _TerritoryBoard(
      strata: snapshot.strata,
      hotspots: hotspots,
      selectedStratumId: selectedStratumId,
      selectedHotspotPath: selectedHotspotPath,
      onStratumSelected: onStratumSelected,
      onHotspotSelected: onHotspotSelected,
      obstacle: obstacle,
      observerCountByPath: obsMap,
    );
  }
}

class _TimeView extends StatelessWidget {
  final String repoPath;
  final List<RepositoryXrayCadenceData> cadence;
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;

  const _TimeView({
    required this.repoPath,
    required this.cadence,
    required this.pivots,
    required this.selectedPivotHash,
    required this.onPivotSelected,
  });

  @override
  Widget build(BuildContext context) {
    // Cadence pinned at top (fixed height); below it, a single
    // scrollable column holding pivots + growth-rings section. Rings
    // live here because they describe temporal structure reconstructed
    // from the current shape — the same beat the Time view is for.
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
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PivotList(
                  pivots: pivots,
                  selectedPivotHash: selectedPivotHash,
                  onPivotSelected: onPivotSelected,
                  shrinkWrap: true,
                ),
                if (pivots.isNotEmpty) const SizedBox(height: 14),
                _RingsSection(repoPath: repoPath),
              ],
            ),
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
          inspectorAccent = _stratumAccent(t, stratum.role);
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
      case _XrayView.summary:
        // Summary view occupies the full viewport — this inspector is
        // never mounted for it. The case exists only for switch
        // exhaustiveness.
        inspectorTitle = snapshot.header.repoName;
        inspectorAccent = t.accentBright;
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
              _XrayView.summary => _OverviewInspector(snapshot: snapshot),
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
    final flow = snapshot.flow;
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
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('${si.filteredCommitCount}',
              style: TextStyle(
                  color: t.textStrong,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  fontFamily: AppFonts.mono)),
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
                fontFamily: AppFonts.mono)),
      ],

      const SizedBox(height: 14),

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

      _InspectorRow(
        label: 'shape',
        value: rs.mergeCommitCount == 0
            ? shapeHint
            : '$shapeHint · ${rs.mergeCommitCount} merges',
      ),
      const SizedBox(height: 5),
      _InspectorRow(
        label: 'flow',
        value:
            'g ${flow.gradientMass.toStringAsFixed(2)} Â· c ${flow.curlMass.toStringAsFixed(2)} Â· h ${flow.harmonicMass.toStringAsFixed(2)}',
      ),
      const SizedBox(height: 5),
      _InspectorRow(
        label: 'stress',
        value:
            '${flow.structuralStress.toStringAsFixed(2)} Â· conf ${flow.confidence.toStringAsFixed(2)}',
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

      _InspectorRow(label: 'branch', value: h.branch),
      const SizedBox(height: 5),
      _InspectorRow(label: 'head', value: h.headShortHash),

      const SizedBox(height: 14),
      Text(
        'probed ${_relativeTime(h.computedAt)}',
        style: TextStyle(
          color: t.textFaint,
          fontSize: 9.5,
          fontFamily: AppFonts.mono,
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
              fontFamily: AppFonts.mono)),
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
      if (hotspot.isKeystone) ...[
        const SizedBox(height: 10),
        // Keystone badge — a file in the top band of pull-per-touch.
        // Reads as a structural observation, not a hotspot ranking.
        Row(children: [
          Icon(Icons.hub_outlined, size: 11, color: t.accentBright),
          const SizedBox(width: 4),
          Text(
            hotspot.keystoneScore == null
                ? 'keystone'
                : 'keystone  φ=${hotspot.keystoneScore!.toStringAsFixed(2)}',
            style: TextStyle(
              color: t.accentBright,
              fontSize: 9.5,
              fontFamily: AppFonts.mono,
              letterSpacing: 0.2,
            ),
          ),
        ]),
      ],
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
    final accent = _stratumAccent(t, stratum.role);
    return ListView(children: [
      _Tag(text: _compactStratumLabel(stratum.role), color: accent),
      const SizedBox(height: 8),
      // Path
      Text(stratum.pathPrefix,
          style: TextStyle(
              color: t.textStrong,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFamily: AppFonts.mono)),
      const SizedBox(height: 10),
      Text('Touched ${stratum.touchCount} times in filtered history.',
          style:
              TextStyle(color: t.textNormal, fontSize: 11, height: 1.5)),
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
                  fontFamily: AppFonts.mono)),
        ),
        Text(pivot.authoredAt,
            style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: AppFonts.mono)),
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
                fontFamily: AppFonts.mono)),
        const SizedBox(width: 8),
        Text('-${pivot.deletions}',
            style: TextStyle(
                color: t.stateDeleted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: AppFonts.mono)),
        const SizedBox(width: 10),
        Text(
            '${pivot.filesChanged} file${pivot.filesChanged == 1 ? '' : 's'}',
            style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: AppFonts.mono)),
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
                  fontFamily: AppFonts.mono))),
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
              fontFamily: AppFonts.mono,
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
            fontFamily: AppFonts.mono,
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

/// Compact metabolism readout for the X-Ray header. A tiny
/// trajectory-coloured sparkline — no text. The visual *is* the
/// statement: the line's shape, stroke weight, and glow all carry
/// the signal (converging = warm accent, diverging = muted, steady =
/// neutral; vitality from spectral radius scales stroke + halo).
/// Hover tooltip still carries the numeric detail for anyone who
/// wants it. Silent when the activity window is too short to fit.
class _MetabolismLine extends StatelessWidget {
  final RepositoryXrayMetabolismData metabolism;
  const _MetabolismLine({required this.metabolism});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final trajectory = metabolism.trajectoryLabel;
    final accent = switch (trajectory) {
      branchLabelConverging => t.accentBright,
      branchLabelDiverging => t.textMuted,
      branchLabelSteady => t.textStrong,
      _ => t.textFaint,
    };
    final hl = metabolism.halfLifeDays;
    final tooltipParts = [
      if (trajectory.isNotEmpty) trajectory,
      '|λ|=${metabolism.spectralRadius.toStringAsFixed(2)}',
      if (hl != null) '${hl.round()}d half-life',
    ];
    return Tooltip(
      message: tooltipParts.join(' · '),
      waitDuration: const Duration(milliseconds: 400),
      child: _Sparkline(
        values: metabolism.sparkline,
        color: accent,
        width: 72,
        height: 10,
        // Spectral radius → visual vitality. Stroke weight and halo
        // breathe with how alive the repo is. Dying repo reads as a
        // hairline; sustained orbit breathes with a soft glow.
        vitality: metabolism.spectralRadius,
      ),
    );
  }
}

/// Tiny zero-chrome line sparkline. Values assumed normalised to
/// [0, 1]; zero and out-of-range inputs render as a flat baseline
/// instead of crashing.
/// The [vitality] parameter (Engram spectral radius, clamped to [0, 1])
/// modulates how *alive* the line looks:
///   * stroke width grows from ~0.8px (decaying repo) to ~2.2px
///     (sustained orbit) — the line has more presence when the repo
///     is homeostatic;
///   * a Gaussian-blurred glow is painted underneath with alpha = the
///     same vitality scalar — dying repos render as a flat line with
///     no halo, sustained orbits get a soft breath around them.
/// Both effects degrade to "the old look" when vitality is null — no
/// behavioural change for callers that don't pass the signal.
class _Sparkline extends StatelessWidget {
  final List<double> values;
  final Color color;
  final double width;
  final double height;
  final double? vitality;
  const _Sparkline({
    required this.values,
    required this.color,
    required this.width,
    required this.height,
    this.vitality,
  });
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return SizedBox(width: width, height: height);
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          vitality: vitality,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final double? vitality;
  _SparklinePainter({
    required this.values,
    required this.color,
    this.vitality,
  });
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    // Build the path once, reuse for both glow + stroke passes.
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final v = values[i].clamp(0.0, 1.0);
      final x = i * dx;
      final y = size.height - v * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Vitality ∈ [0, 1]. Spectral radius can bleed slightly past 1.0
    // in near-sustained orbits (our orbit ceiling tolerance), so clamp.
    final v = (vitality ?? 0).clamp(0.0, 1.0);

    // Underglow: only drawn when there's meaningful vitality. A
    // blurred stroke beneath the main line, alpha scaling with v —
    // so a decaying repo paints no glow at all, a sustained orbit
    // gets a soft breath. Blur sigma ties to the stroke width so the
    // halo always looks proportional.
    if (v > 0) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: 0.55 * v)
        ..strokeWidth = 1.6 + 1.4 * v
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.2 + 1.4 * v);
      canvas.drawPath(path, glowPaint);
    }

    // Main stroke. Width ramps from 0.8px (no vitality) to ~2.2px
    // (fully orbital). The line has more *presence* in a living repo
    // without shouting.
    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
      ..strokeWidth = 0.8 + 1.4 * v
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values ||
      old.color != color ||
      old.vitality != vitality;
}

//
// Replaces the old Strata bars + Heat grid. Top-level directories become big
// territory tiles sized by touch count; hot files/subdirs nest inside their
// parent stratum as smaller tiles. Orphan hotspots (no matching stratum) sit
// as their own top-level tiles. Clicking any tile selects it — the inspector
// on the right fills in with the corresponding stratum or hotspot details.

// Expressed as multipliers on the base `bgAlpha` (which itself comes
// from the parcel's own role — region / child / orphan / selected).
// Named so the relationships between normal, keystone, and selected
// tiles read explicitly in the decoration block rather than as
// scattered literals.
const double _parcelGradientAlphaMul = 1.25; // normal warm-corner
const double _keystoneGradientAlphaMul = 1.8; // warmer corner for keystones
const double _parcelCoolCornerAlphaMul = 0.55; // diagonal fade target
const double _parcelSelectedBorderAlpha = 0.6; // full selection border
const double _parcelChromeBorderAlpha = 0.16; // neutral chrome border
// Keystone border sits between selection (0.6) and chrome (0.16) —
// midpoint ≈ 0.38, softened to 0.34 so the effect stays quieter
// than a selection while still whispering structural importance.
const double _keystoneBorderAlpha = 0.34;

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
  /// Keystone bridge-file marker. Rendered as a stronger border +
  /// warmer inner gradient stop so the tile reads as structurally
  /// load-bearing before the user notices the tag text. Default false
  /// so every non-hotspot-file parcel (directories, strata) stays
  /// neutral.
  final bool isKeystone;

  /// Bus-factor signal — true when only one author has touched this
  /// path in the snapshot's window.
  final bool soloOwner;

  /// Number of distinct reviewers who have observed this path through
  /// forge reviews. Null = no observation data. 0 = unobserved.
  final int? observerCount;

  /// Compact human label for the parcel's last-touched age, or null
  /// when none is available. Shown inline on big tiles only.
  final String? recencyLabel;

  /// Top co-changed paths for this parcel (file parcels only). Drives
  /// the coupling overlay that draws lines from the selected tile to
  /// its strongest co-changers.
  final List<String> coupledTo;

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
    this.isKeystone = false,
    this.soloOwner = false,
    this.observerCount,
    this.recencyLabel,
    this.coupledTo = const [],
  });
}

class _TreemapLayout {
  final Rect rect;
  final _Parcel parcel;
  final List<_TreemapLayout> children;
  const _TreemapLayout(this.rect, this.parcel, this.children);
}

/// Decompose [fullArea] into 1–2 non-overlapping rects that avoid
/// [obstacle] (anchored to the top-right corner). Used by the L-shape
/// treemap layout: returns `[leftStrip, bottomStrip]` when an obstacle
/// is present and both strips are non-degenerate; otherwise returns
/// the largest rect that fits.
List<Rect> _regionsAroundObstacle(Rect fullArea, Rect? obstacle) {
  if (obstacle == null) return [fullArea];
  // Clamp obstacle to the area.
  final ox = obstacle.left.clamp(0.0, fullArea.width);
  final oy = obstacle.top.clamp(0.0, fullArea.height);
  final or = obstacle.right.clamp(0.0, fullArea.width);
  final ob = obstacle.bottom.clamp(0.0, fullArea.height);
  if (or - ox <= 0 || ob - oy <= 0) return [fullArea];

  // L-shape decomposition: full-height left strip + bottom-right block.
  // We assume the obstacle is anchored top-right (the inspector card).
  // Left strip: from x=0 to x=obstacleLeft, full height.
  // Bottom block: from x=obstacleLeft to right, from obstacleBottom to bottom.
  final regions = <Rect>[];
  if (ox > 0) {
    regions.add(Rect.fromLTWH(0, 0, ox, fullArea.height));
  }
  if (ob < fullArea.height) {
    regions.add(
      Rect.fromLTWH(ox, ob, fullArea.width - ox, fullArea.height - ob),
    );
  }
  if (regions.isEmpty) return [fullArea];
  return regions;
}

/// Squarified-treemap layout (Bruls, Huijbregts & van Wijk).
/// Recurses for children so strata cells contain their hotspots.
/// Multi-region: when [bounds] has more than one rect, parcels are
/// distributed across the regions by greedy area-share allocation
/// (largest parcel first → region with the most remaining capacity),
/// then each region is squarified independently. This is what makes the
/// L-shape layout possible — territory tiles flow around the floating
/// inspector card.
// Single-slot cache for the squarified treemap layout. The LayoutBuilder
// surrounding the call fires on every resize, inspector-toggle, and
// unrelated rebuild of the xray panel, yet the inputs (parcels list
// identity + bounds rects) are stable across those rebuilds. Memoising
// here turns a repeated O(n log n + squarify) per frame into a single
// Rect + identical-pointer check per frame.
List<_Parcel>? _treemapCacheParcels;
List<Rect>? _treemapCacheBounds;
List<_TreemapLayout>? _treemapCacheResult;

bool _boundsEqual(List<Rect> a, List<Rect> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<_TreemapLayout> _layoutTreemap(List<_Parcel> parcels, List<Rect> bounds) {
  if (identical(_treemapCacheParcels, parcels) &&
      _treemapCacheBounds != null &&
      _boundsEqual(_treemapCacheBounds!, bounds) &&
      _treemapCacheResult != null) {
    return _treemapCacheResult!;
  }
  final result = _layoutTreemapUncached(parcels, bounds);
  _treemapCacheParcels = parcels;
  _treemapCacheBounds = List<Rect>.from(bounds);
  _treemapCacheResult = result;
  return result;
}

List<_TreemapLayout> _layoutTreemapUncached(
    List<_Parcel> parcels, List<Rect> bounds) {
  if (parcels.isEmpty) return const [];
  final regions =
      bounds.where((r) => r.width > 0 && r.height > 0).toList(growable: false);
  if (regions.isEmpty) return const [];
  final filtered = parcels.where((p) => p.value > 0).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  if (filtered.isEmpty) return const [];

  if (regions.length == 1) {
    return _layoutTreemapSingle(filtered, regions.first);
  }

  // Distribute parcels across regions by area share. We compute each
  // region's target share = its area / total area, then walk the parcels
  // (largest first) placing each in the region with the most remaining
  // capacity. This gives squarified fidelity per region while keeping
  // overall area-proportionality across the whole layout.
  final totalArea =
      regions.fold<double>(0, (s, r) => s + r.width * r.height);
  final remainingArea =
      regions.map((r) => r.width * r.height).toList(growable: false);
  final totalValue = filtered.fold<double>(0, (s, p) => s + p.value);
  final perRegion =
      List<List<_Parcel>>.generate(regions.length, (_) => <_Parcel>[]);
  for (final p in filtered) {
    var bestI = 0;
    var bestRem = remainingArea[0];
    for (var i = 1; i < remainingArea.length; i++) {
      if (remainingArea[i] > bestRem) {
        bestRem = remainingArea[i];
        bestI = i;
      }
    }
    perRegion[bestI].add(p);
    remainingArea[bestI] -= (p.value / totalValue) * totalArea;
  }

  final out = <_TreemapLayout>[];
  for (var i = 0; i < regions.length; i++) {
    out.addAll(_layoutTreemapSingle(perRegion[i], regions[i]));
  }
  return out;
}

List<_TreemapLayout> _layoutTreemapSingle(
    List<_Parcel> filtered, Rect bounds) {
  if (filtered.isEmpty || bounds.width <= 0 || bounds.height <= 0) {
    return const [];
  }
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
      // Recursive descent intentionally bypasses the top-level cache
      // slot — caching children would just thrash the one slot with
      // the last-recursion's result and destroy the outer-call hit
      // rate. Child layouts are cheap anyway (few items per cell).
      _layoutTreemapUncached(layout.parcel.children, [childBounds]),
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
  final Map<String, int> observerCountByPath;

  /// Treemap-interior rect (i.e. relative to the LayoutBuilder area below
  /// the header) to avoid placing tiles in. When set, the treemap renders
  /// into an L-shape: full-height left strip + full-width bottom strip.
  /// Use cases: the floating inspector card in map view occupies the
  /// top-right corner, so the territory snakes around it.
  final Rect? obstacle;

  const _TerritoryBoard({
    required this.strata,
    required this.hotspots,
    required this.selectedStratumId,
    required this.selectedHotspotPath,
    required this.onStratumSelected,
    required this.onHotspotSelected,
    this.obstacle,
    this.observerCountByPath = const {},
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // Snapshot reference date = most-recent lastTouchedAt across the
    // hotspots+strata we're about to render. Anchors the human-
    // readable age label only; sizing itself is driven by the
    // backend-computed aliveMass (touchCount × exp(-ageDays/halfLife)
    // with a repo-derived half-life — see `_selectAliveHalfLife`).
    DateTime? newest;
    for (final h in hotspots) {
      final d = DateTime.tryParse(h.lastTouchedAt);
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }
    for (final s in strata) {
      final d = DateTime.tryParse(s.lastTouchedAt);
      if (d != null && (newest == null || d.isAfter(newest))) newest = d;
    }

    double ageDaysFor(String iso) {
      final d = DateTime.tryParse(iso);
      if (d == null || newest == null) return 0.0;
      return newest.difference(d).inDays.toDouble().abs();
    }
    String? recencyLabelOf(String iso) {
      final age = ageDaysFor(iso);
      if (age < 1.5) return 'today';
      if (age < 7) return '${age.round()}d';
      if (age < 60) return '${(age / 7).round()}w';
      if (age < 730) return '${(age / 30).round()}mo';
      return '${(age / 365).round()}y';
    }

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

    _Parcel hotspotParcel(RepositoryXrayHotspotData h,
        {required bool isChild}) {
      final accent = _hotspotAccent(t, h.kind);
      return _Parcel(
        key: 'h:${h.path}',
        label: _shortPath(h.path),
        accent: accent,
        value: h.touchCount.toDouble(),
        count: h.touchCount,
        // Keystone files get a compact `keystone` tag on their tile so
        // they're visible in the overview, not just the inspector pane.
        tagText: h.isKeystone ? 'keystone' : null,
        selected: selectedHotspotPath == h.path,
        isChild: isChild,
        onTap: () => onHotspotSelected(h.path),
        children: const [],
        isKeystone: h.isKeystone,
        soloOwner: h.ownerCount == 1,
        observerCount: observerCountByPath.isNotEmpty
            ? (observerCountByPath[h.path] ?? 0)
            : null,
        recencyLabel: recencyLabelOf(h.lastTouchedAt),
        coupledTo: h.coupledTo,
      );
    }

    final topLevel = <_Parcel>[];
    for (final s in strata) {
      final accent = _stratumAccent(t, s.role);
      final children = (childMap[s.id] ?? const <RepositoryXrayHotspotData>[])
          .map((h) => hotspotParcel(h, isChild: true))
          .toList();
      topLevel.add(_Parcel(
        key: 's:${s.id}',
        label: s.pathPrefix,
        accent: accent,
        value: s.touchCount.toDouble(),
        count: s.touchCount,
        tagText: _compactStratumLabel(s.role),
        selected: selectedStratumId == s.id,
        isChild: false,
        onTap: () => onStratumSelected(s.id),
        children: children,
        soloOwner: s.ownerCount == 1,
        recencyLabel: recencyLabelOf(s.lastTouchedAt),
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
                  fontFamily: AppFonts.mono,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                final fullArea = Rect.fromLTWH(0, 0, c.maxWidth, c.maxHeight);
                final regions = _regionsAroundObstacle(fullArea, obstacle);
                final cells = _layoutTreemap(topLevel, regions);
                final children = _renderCells(cells);
                // Coupling overlay: when a hotspot is selected, collect
                // the rects of its top co-changers that happen to be on
                // the visible board, then draw curved lines to them.
                // Lines render *above* the cells but ignore pointer events
                // so tile interaction stays unaffected. Snappy: no fade,
                // appears the frame the selection changes.
                final selPath = selectedHotspotPath;
                if (selPath != null) {
                  final pathToRect = <String, Rect>{};
                  _collectHotspotRects(cells, pathToRect);
                  final selRect = pathToRect[selPath];
                  final selectedHotspot = hotspots.firstWhere(
                    (h) => h.path == selPath,
                    orElse: () => const RepositoryXrayHotspotData(
                      kind: '',
                      path: '',
                      touchCount: 0,
                      ownerCount: 0,
                      lastTouchedAt: '',
                    ),
                  );
                  if (selRect != null && selectedHotspot.coupledTo.isNotEmpty) {
                    final targets = <Rect>[];
                    for (final tgt in selectedHotspot.coupledTo) {
                      final r = pathToRect[tgt];
                      if (r != null && r != selRect) targets.add(r);
                    }
                    if (targets.isNotEmpty) {
                      children.add(Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _CouplingOverlayPainter(
                              source: selRect,
                              targets: targets,
                              color: t.accentBright,
                            ),
                          ),
                        ),
                      ));
                    }
                  }
                }
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: children,
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
      // Render-time area cull. Tiles below the readability floor (one
      // line of label text + ~6 chars of width at the smallest font
      // tier ≈ 14 × 70 px) carry no information — the label is
      // unreadable, the count is invisible — so we skip them entirely.
      // Their squarified area still belongs to them in the layout
      // (proportions stay correct for everything else); we just don't
      // paint them. This is what makes the top-N caps redundant at
      // the panel level — the screen self-gates the visible count.
      if (cell.rect.width * cell.rect.height < _kMinReadableTileArea) {
        continue;
      }
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

/// Minimum tile area, in pixels², for a tile to be rendered. Derived
/// from font metrics: the smallest label tier is ~9.5pt → ~14px line
/// height, and a tile narrower than ~70px can't fit even a 6-char
/// label without ellipsing into uselessness. 14 × 70 = 980; rounded
/// up to 1000 for clean arithmetic. This is the readability floor —
/// it *is* a constant, but it's a typography constant, not a UX cap.
const double _kMinReadableTileArea = 1000.0;

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
    // Tile chrome stays at full accent — aliveness is encoded by tile
    // SIZE (backend aliveMass). Re-tinting by recency would be
    // redundant double-encoding and would risk muddying the petrichor
    // accent palette.
    final accent = parcel.accent;
    return LayoutBuilder(builder: (context, c) {
      // Height thresholds account for the two-row (label + count)
      // content the tile renders at each tier PLUS the tile's own
      // margin (`EdgeInsets.all(isChild ? 1.5 : 2.5)`, so up to 5px
      // consumed by chrome). The medium breakpoint's old value of
      // `> 30` let the two-row layout engage at inner heights of ~25,
      // but the two rows want ~27 px (text ~14 + spacer 1 + count ~12),
      // producing an overflow of a few pixels on small orphan tiles.
      // `> 34` is the smallest height that reliably fits the two-row
      // content plus the 5px margin. Purely a typography bound — the
      // same shape as [_kMinReadableTileArea]'s min-legible size.
      final big = c.maxWidth > 140 && c.maxHeight > 60;
      final medium = c.maxWidth > 80 && c.maxHeight > 34;
      final tiny = c.maxWidth < 40 || c.maxHeight < 18;
      // Region = cell that contains nested child cells. Label goes into a
      // compact top band (26px) so children don't overlap the text. If the
      // cell is too short for that band we collapse to a single-row header
      // — important for the L-shape layout's bottom strip, which can
      // distribute very wide-but-short region tiles.
      final isRegion = hasChildren && !tiny && c.maxHeight >= 34;
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
            message: '${parcel.label}  ·  ${parcel.count}×'
                '${parcel.observerCount != null ? (parcel.observerCount! > 0 ? '  ·  ${parcel.observerCount} reviewer${parcel.observerCount == 1 ? '' : 's'}' : '  ·  unreviewed') : ''}',
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
                    // Warm-corner alpha. Normal tiles sit at the base
                    // multiplier (1.25). Keystones lift it to the
                    // midpoint between normal and "fully saturated"
                    // (1 + (2 - 1.25)·½ = 1.375·… rounded to a clean
                    // factor below) so they read as denser than a
                    // regular hotspot without shouting.
                    accent.withValues(
                      alpha: bgAlpha *
                          (parcel.isKeystone
                              ? _keystoneGradientAlphaMul
                              : _parcelGradientAlphaMul) *
                          (parcel.observerCount == 0 ? 0.55 : 1.0),
                    ),
                    accent.withValues(
                      alpha: bgAlpha * _parcelCoolCornerAlphaMul *
                          (parcel.observerCount == 0 ? 0.55 : 1.0),
                    ),
                  ],
                ),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: selected
                      ? accent.withValues(alpha: _parcelSelectedBorderAlpha)
                      // Non-selected keystones borrow a whisper of
                      // accent: the midpoint between the neutral
                      // chromeBorder and a full selection border
                      // (`(0.16 + 0.6) / 2 ≈ 0.38`, softened down to
                      // 0.34 so the effect stays quieter than a
                      // selection). Pure derivation from the two
                      // existing border alphas.
                      : parcel.isKeystone
                          ? accent.withValues(
                              alpha: _keystoneBorderAlpha,
                            )
                          : t.chromeBorder
                              .withValues(alpha: _parcelChromeBorderAlpha),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius - 1),
                child: tiny
                    ? Container(color: accent.withValues(alpha: 0.22))
                    : isRegion
                        ? _regionLayout(t, accent,
                            big: big, medium: medium)
                        : _headerRow(t, accent,
                            big: big, medium: medium, compact: false),
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _regionLayout(AppTokens t, Color accent,
      {required bool big, required bool medium}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 26,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: accent.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: _headerRow(t, accent,
              big: big, medium: medium, compact: true),
        ),
        const Expanded(child: SizedBox.shrink()),
      ],
    );
  }

  Widget _headerRow(
    AppTokens t,
    Color accent, {
    required bool big,
    required bool medium,
    required bool compact,
  }) {
    final selected = parcel.selected;
    final isChild = parcel.isChild;
    final stripeW = isChild ? 2.0 : 3.0;
    return Row(children: [
      // Left edge: solid accent normally; dashed when this is a
      // bus-factor-of-one file. The hatch reads as "single-owner risk"
      // at a glance — same width and color family as the regular
      // stripe, just broken so it's distinguishable without a legend.
      SizedBox(
        width: stripeW,
        child: parcel.soloOwner
            ? CustomPaint(
                painter: _SoloOwnerStripePainter(
                  color: accent.withValues(alpha: selected ? 0.95 : 0.7),
                ),
              )
            : Container(
                color: accent.withValues(alpha: selected ? 0.95 : 0.7),
              ),
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
                fontFamily: isChild ? AppFonts.mono : null,
                letterSpacing: 0.1,
              ),
            ),
            if (!compact && medium) ...[
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${parcel.count}×',
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 9,
                      fontFamily: AppFonts.mono,
                    ),
                  ),
                  if (big && parcel.recencyLabel != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '· ${parcel.recencyLabel}',
                      style: TextStyle(
                        color: t.textFaint,
                        fontSize: 9,
                        fontFamily: AppFonts.mono,
                      ),
                    ),
                  ],
                ],
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
            fontFamily: AppFonts.mono,
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

/// Walk the laid-out cell tree and collect the rect of every hotspot
/// (non-stratum) cell, keyed by its hotspot path. Used by the coupling
/// overlay to look up where a co-changer's tile lives on the board.
///
/// **Must apply the same readability cull as [_renderCells]**. Cells
/// below [_kMinReadableTileArea] are dropped from the render stack;
/// if we recorded their rects here, the coupling overlay would draw
/// lines to empty regions where no tile is painted. When a parent
/// is culled, its children are unreachable in the rendered tree, so
/// we stop recursing too (matching `_renderCells`'s `continue`).
void _collectHotspotRects(
    List<_TreemapLayout> cells, Map<String, Rect> out) {
  for (final cell in cells) {
    if (cell.rect.width * cell.rect.height < _kMinReadableTileArea) {
      continue;
    }
    final key = cell.parcel.key;
    if (key.startsWith('h:')) {
      out[key.substring(2)] = cell.rect;
    }
    if (cell.children.isNotEmpty) {
      _collectHotspotRects(cell.children, out);
    }
  }
}

/// Coupling overlay: draws a faint curved line from the selected
/// hotspot's tile to each visible co-change neighbour. Renders above
/// all cells, ignores pointer events. The curve is a single cubic with
/// vertical-pull control points so lines arc cleanly between tiles
/// instead of cutting across them in straight gashes.
class _CouplingOverlayPainter extends CustomPainter {
  _CouplingOverlayPainter({
    required this.source,
    required this.targets,
    required this.color,
  });

  final Rect source;
  final List<Rect> targets;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (targets.isEmpty) return;
    final src = source.center;
    // Two-tone stroke: a wider faint glow underneath + a crisp thin
    // line on top. Gives the lines presence without resorting to pure
    // saturation (would clash with the petrichor accent palette).
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.10);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.60);

    // Source anchor dot — small filled circle on the selected tile to
    // tell the user where the lines emanate from.
    canvas.drawCircle(src, 3.0, Paint()..color = color.withValues(alpha: 0.85));

    for (final t in targets) {
      final dst = t.center;
      // Cubic with vertical pull-in: control points sit halfway between
      // the endpoints horizontally, but their y is biased toward each
      // endpoint's y. Produces a soft S-curve that hugs neither tile.
      final dx = (dst.dx - src.dx);
      final pull = dx.abs() * 0.45;
      final c1 = Offset(src.dx + dx.sign * pull, src.dy);
      final c2 = Offset(dst.dx - dx.sign * pull, dst.dy);
      final path = Path()
        ..moveTo(src.dx, src.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, dst.dx, dst.dy);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
      // Target dot — slightly smaller than the source to imply
      // direction (this co-changes WITH the source).
      canvas.drawCircle(
          dst, 2.2, Paint()..color = color.withValues(alpha: 0.70));
    }
  }

  @override
  bool shouldRepaint(covariant _CouplingOverlayPainter old) =>
      old.source != source ||
      old.color != color ||
      old.targets.length != targets.length ||
      !_listEq(old.targets, targets);

  static bool _listEq(List<Rect> a, List<Rect> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Bus-factor stripe: vertical dashes along the left edge of a tile,
/// signalling that only one author has touched this path. Same width
/// and color family as the regular accent stripe — the broken pattern
/// is the entire signal, no extra hue or chrome.
class _SoloOwnerStripePainter extends CustomPainter {
  _SoloOwnerStripePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    // Dash: 4px on, 3px off. Renders 4–10 dashes depending on tile
    // height, which is always enough to read as "broken stripe" without
    // tipping into morse-code noise.
    const dashOn = 4.0;
    const dashOff = 3.0;
    var y = 0.0;
    while (y < size.height) {
      final h = math.min(dashOn, size.height - y);
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, h), paint);
      y += dashOn + dashOff;
    }
  }

  @override
  bool shouldRepaint(covariant _SoloOwnerStripePainter old) =>
      old.color != color;
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
        //   [dates: Apr 3 · Apr 10-12 · …]    ← one line under each bucket
        //   [reflog: ● 46]                     ← one line, accent marks
        const burstDateH = 14.0;
        const reflogH = 16.0;
        const barWidth = 28.0;
        // Minimum horizontal clearance between bucket centres: wide
        // enough for the 44px date label under each bar to breathe
        // against its neighbour. Bursts whose x-positions are closer
        // than this collapse into a single bucket — preserves every
        // count, just paints them as one "Feb 23–25" block instead of
        // three bars on top of each other.
        const bucketStride = 48.0;
        final barAreaH = h - burstDateH - reflogH;
        final maxBarH = (barAreaH - 20).clamp(10.0, double.infinity);

        // Sort bursts chronologically, then walk left-to-right
        // merging any whose positions would collide.
        final burstItems = [
          for (final c in cadence)
            if (c.kind == 'burst' && _cadenceDate(c) != null) c,
        ]..sort((a, b) => _cadenceDate(a)!.compareTo(_cadenceDate(b)!));

        final buckets = <_BurstBucket>[];
        for (final item in burstItems) {
          final x = xFor(_cadenceDate(item)!, w);
          if (buckets.isNotEmpty &&
              x - buckets.last.centerX < bucketStride) {
            buckets.last.add(item, x);
          } else {
            buckets.add(_BurstBucket.start(item, x));
          }
        }

        // Height scaling uses the largest bucket sum, not the
        // largest single-day burst — otherwise a coalesced bucket
        // (3 days of 60 commits each → 180) would visually overflow
        // a single-day burst of 90. Post-bucket normalisation keeps
        // the tallest visible bar occupying the same relative
        // fraction of the chart regardless of clustering.
        final maxBucketCount =
            buckets.fold<int>(1, (m, b) => math.max(m, b.sumCount));
        double barH(int count) =>
            ((count / maxBucketCount).clamp(0.15, 1.0) * maxBarH)
                .clamp(8.0, maxBarH);

        return Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: 12,
            right: 12,
            top: barAreaH,
            height: 1,
            child:
                Container(color: t.chromeBorder.withValues(alpha: 0.22)),
          ),

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
                    fontFamily: AppFonts.mono,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],

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

          //
          // One bar per bucket. Singleton buckets look identical to
          // the old single-day rendering. Merged buckets get a count
          // badge showing the total + `×n` multiplier and a date
          // range label, so three tightly-packed days appear as one
          // tall bar reading "Feb 23–25 · 198 ×3" instead of three
          // overlapping stubs.
          for (final bucket in buckets) ...[
            Positioned(
              left: (bucket.centerX - barWidth / 2).clamp(0.0, w - barWidth),
              top: barAreaH - barH(bucket.sumCount),
              width: barWidth,
              height: barH(bucket.sumCount),
              child: Tooltip(
                message: bucket.tooltipMessage(),
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
            // Count label above the bar. Wider box when the bucket
            // coalesces multiple bursts so the "×n" multiplier sits
            // beside the total cleanly instead of wrapping.
            Positioned(
              left: (bucket.centerX - 20).clamp(0.0, w - 40),
              top: math.max(0, barAreaH - barH(bucket.sumCount) - 16),
              width: 40,
              child: Text(
                bucket.countLabel(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  fontFamily: AppFonts.mono,
                ),
              ),
            ),
            // Date label below the bar — singleton shows one date,
            // bucket shows the span.
            Positioned(
              left: (bucket.centerX - 24).clamp(0.0, w - 48),
              top: barAreaH + 2,
              width: 48,
              child: Text(
                bucket.dateLabel(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFonts.mono,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],

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
                              fontFamily: AppFonts.mono)),
                    ],
                  ),
                ),
              ),

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

/// Coalesced group of adjacent cadence bursts. When consecutive-day
/// bursts would paint at overlapping pixel positions (because the repo's
/// total span is wide relative to the chart's width), they merge into
/// one bucket that renders as a single bar carrying the summed count.
/// The label vocabulary absorbs the merge: "Apr 3" stays itself,
/// "Apr 3–5" replaces three collided stubs. Restrained — a single-day
/// bucket behaves identically to the pre-rework single-burst render.
class _BurstBucket {
  final List<RepositoryXrayCadenceData> items;
  final double centerX;
  int sumCount;

  _BurstBucket._({
    required this.items,
    required this.centerX,
    required this.sumCount,
  });

  factory _BurstBucket.start(
    RepositoryXrayCadenceData item,
    double x,
  ) => _BurstBucket._(
        items: [item],
        centerX: x,
        sumCount: item.count,
      );

  void add(RepositoryXrayCadenceData item, double x) {
    items.add(item);
    sumCount += item.count;
    // centerX stays anchored at the first item's position — prevents
    // a growing bucket from sliding rightward and colliding with the
    // next singleton.
  }

  /// Count label — a plain integer for singleton buckets, the sum
  /// plus a multiplier for merged buckets so the reader sees both
  /// "how much activity" and "how many days it spans" at a glance.
  String countLabel() {
    if (items.length == 1) return '${items.first.count}';
    return '$sumCount ×${items.length}';
  }

  /// Date label — one `MMM d` for singleton, `MMM d–d` for a bucket
  /// spanning within one month, `MMM d–MMM d` for cross-month ranges.
  String dateLabel() {
    if (items.length == 1) {
      final d = _cadenceDate(items.first);
      return d == null ? items.first.label : _fmtDateMD(d);
    }
    final first = _cadenceDate(items.first);
    final last = _cadenceDate(items.last);
    if (first == null || last == null) return items.first.label;
    final sameMonth = first.month == last.month && first.year == last.year;
    if (sameMonth) {
      return '${_fmtDateMD(first)}–${last.day}';
    }
    return '${_fmtDateMD(first)}–${_fmtDateMD(last)}';
  }

  String tooltipMessage() {
    if (items.length == 1) {
      final item = items.first;
      return item.detail.isNotEmpty
          ? item.detail
          : '${item.count} commits on ${item.label}';
    }
    // Multi-day bucket — list per-day breakdown so the tooltip still
    // carries the full data under the coalesced bar.
    final lines = items
        .map((i) => '${i.label}: ${i.count}')
        .join('\n');
    return '$sumCount commits · ${items.length} days\n$lines';
  }
}


class _PivotList extends StatelessWidget {
  final List<RepositoryXrayPivotCommitData> pivots;
  final String? selectedPivotHash;
  final ValueChanged<String> onPivotSelected;

  /// When `true` the internal [ListView] wraps to its content height
  /// and disables its own scrolling — needed when the caller nests
  /// this list inside another scrollable (e.g. the Time view's
  /// scroll column that also renders growth-rings below).
  final bool shrinkWrap;

  const _PivotList({
    required this.pivots,
    required this.selectedPivotHash,
    required this.onPivotSelected,
    this.shrinkWrap = false,
  });

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
          shrinkWrap: shrinkWrap,
          physics: shrinkWrap ? const NeverScrollableScrollPhysics() : null,
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
                    color: active
                        ? t.itemActiveBg
                        : t.itemActiveBg.withValues(alpha: 0),
                    border: Border(
                      left: BorderSide(
                        color: active
                            ? t.accentBright
                            : t.accentBright.withValues(alpha: 0),
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
                            fontFamily: AppFonts.mono,
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
                                fontFamily: AppFonts.mono)),
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
                                  fontFamily: AppFonts.mono)),
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
            color: active
                ? t.itemActiveBg
                : t.itemActiveBg.withValues(alpha: 0),
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
  // Parse once, not twice. The prior shape called `tryParse` as a
  // predicate and then `parse` for the value — paying the parse cost
  // on every hit, which adds up to hundreds of parses per panel
  // rebuild given how many call sites dereference this helper.
  final direct = DateTime.tryParse(item.label);
  if (direct != null) return direct;
  if (item.kind == 'gap') {
    final parts = item.label.split('->');
    if (parts.isNotEmpty) {
      return DateTime.tryParse(parts.first.trim());
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

String _compactStratumLabel(StratumRole role) {
  return switch (role) {
    StratumRole.current => 'current',
    StratumRole.legacy => 'legacy',
    StratumRole.zone => 'repo zone',
  };
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

Color _stratumAccent(AppTokens t, StratumRole role) {
  return switch (role) {
    StratumRole.current => t.stateAdded,
    StratumRole.legacy => t.chromeAccent,
    StratumRole.zone => t.accentBright,
  };
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
    if (parts.length > 1) {
      return DateTime.tryParse(parts.last.trim());
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

// ── Growth-rings section — embedded inside [_TimeView] ───────────
//
// Reads the codebase's history from its current shape via an aperture
// sweep — a sequence of spectral probes at geometrically-spaced
// commit-window depths. Surfaces three correlated views inline under
// the existing cadence/pivots panel:
//
//   * centre-of-gravity trajectory — the sequence of "top
//     housekeeping" files across the sweep; reads like a narrative
//     of the repo's recent work order, deepest-focus first.
//   * compound events — aperture bins where multiple observables
//     flip together; each maps to an approximate commit range and
//     is tagged with what changed (cleavage/topology/size/class).
//   * invariant / running / artifact classification — which
//     observables describe the repo's species (hold across all
//     lens settings) vs its developmental arc (drift predictably
//     with scale) vs lens noise.
//
// The sweep is expensive (multiple spectral-basis builds) and runs
// per-sample inside [Isolate.run] so the main isolate stays
// responsive. The section triggers a background load when first
// rendered and reads through [RepositoryXrayState.ringsFor].

class _RingsSection extends StatefulWidget {
  final String repoPath;

  const _RingsSection({required this.repoPath});

  @override
  State<_RingsSection> createState() => _RingsSectionState();
}

class _RingsSectionState extends State<_RingsSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context
          .read<RepositoryXrayState>()
          .loadRingsForRepo(widget.repoPath);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final state = context.watch<RepositoryXrayState>();
    final rings = state.ringsFor(widget.repoPath);
    final loading = state.isLoadingRings(widget.repoPath);
    final error = state.ringsErrorFor(widget.repoPath);
    final progress = state.ringsProgressFor(widget.repoPath);

    // Streaming UX: partial rings data appears as soon as the first
    // sample completes, so the section is rarely in the pure "empty,
    // loading" state for long. Three presentations coexist:
    //   * rings=null, loading: slim progress bar only
    //   * rings!=null, loading: partial data + progress hint
    //   * rings!=null, done: final data
    //   * rings=null, error: error banner
    final hint = rings != null
        ? loading
            ? 'probing ${progress?.$1 ?? rings.sweep.length}/${progress?.$2 ?? rings.sweep.length}… · '
                '${rings.sweep.length} samples so far · '
                '${rings.events.length} events · '
                '${rings.centerTrajectory.length} strata'
            : '${rings.sweep.length} samples · ${rings.events.length} events · '
                '${rings.centerTrajectory.length} strata'
        : error != null
            ? 'unavailable — $error'
            : progress != null
                ? 'probing ${progress.$1}/${progress.$2}…'
                : loading
                    ? 'probing…'
                    : 'preparing sweep';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(label: 'Growth rings', hint: hint),
        const SizedBox(height: 8),
        if (loading)
          // Progress rail always visible while sweeping, whether
          // partial data has arrived or not. The bar fills as
          // samples complete; partial data fills in below it.
          Container(
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: t.chromeBorder.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
            child: progress == null
                ? null
                : FractionallySizedBox(
                    widthFactor:
                        (progress.$1 / progress.$2).clamp(0.02, 1.0),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.accentBright.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
          ),
        if (rings == null && !loading)
          // Only show this empty-state when there's truly nothing —
          // not during the first sample's travel time.
          Text('No rings data yet.',
              style: TextStyle(color: t.textMuted, fontSize: 11))
        else if (rings != null) ...[
          _RingsClassificationRow(
              classification: rings.observableClassification),
          const SizedBox(height: 12),
          // Aperture scrubber — drag through the probe to see the
          // repo through different memory horizons. The live readout
          // below the track uses `sweep.sampleAt(window)` continuous-
          // domain interpolation so the cursor glides between real
          // samples without snapping.
          _ApertureScrubber(sweep: rings.sweep),
          const SizedBox(height: 14),
          _SectionSubHeader(
              label: 'Centre-of-gravity trajectory',
              hint: 'close focus → wide focus'),
          const SizedBox(height: 6),
          _CenterTrajectoryList(strata: rings.centerTrajectory),
          const SizedBox(height: 10),
          _SectionSubHeader(
              label: 'Compound events',
              hint: '${rings.events.length} detected'),
          const SizedBox(height: 6),
          if (rings.events.isEmpty)
            Text(loading
                ? 'No compound events detected yet — still sampling.'
                : 'No compound events in the sampled range.',
                style: TextStyle(color: t.textMuted, fontSize: 11))
          else
            Column(
              children: [
                for (final e in rings.events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: _EventCard(event: e),
                  ),
              ],
            ),
        ],
      ],
    );
  }
}

/// Interactive aperture scrubber. Draggable track over the
/// commit-window space of an [ApertureSweep]. Real sample positions
/// render as ticks whose height reflects the sample's decisiveness
/// (confident archetype = tall tick; uncertain = short). The thumb
/// glides log-space between ticks via [ApertureSweep.sampleAt], and
/// the compact readout below shows the interpolated observables at
/// the cursor's window. No separate "slider" affordance — the ticks
/// ARE the handles, the whole card surface scrubs.
class _ApertureScrubber extends StatefulWidget {
  const _ApertureScrubber({required this.sweep});
  final ApertureSweep sweep;

  @override
  State<_ApertureScrubber> createState() => _ApertureScrubberState();
}

class _ApertureScrubberState extends State<_ApertureScrubber> {
  // Current cursor position expressed as a window value. Defaults to
  // the sweep's widest sample — the "full memory" lens — so the
  // initial view matches the headline stats the rest of the panel
  // shows.
  int? _window;
  bool _dragging = false;

  int get _minWindow => widget.sweep.samples.first.window;
  int get _maxWindow => widget.sweep.samples.last.window;
  int get _currentWindow => _window ?? _maxWindow;

  @override
  void didUpdateWidget(covariant _ApertureScrubber old) {
    super.didUpdateWidget(old);
    // If the sweep range shifts (refresh, HEAD moved), clamp the
    // cursor into the new bounds rather than holding a stale value.
    if (_window != null) {
      final w = _window!;
      if (w < _minWindow || w > _maxWindow) _window = null;
    }
  }

  double _tForWindow(int w) {
    if (_maxWindow <= _minWindow) return 0.0;
    final la = math.log(_minWindow.toDouble());
    final lb = math.log(_maxWindow.toDouble());
    final lw = math.log(w.toDouble());
    return ((lw - la) / (lb - la)).clamp(0.0, 1.0).toDouble();
  }

  int _windowForT(double t) {
    final la = math.log(_minWindow.toDouble());
    final lb = math.log(_maxWindow.toDouble());
    final lw = la + (lb - la) * t.clamp(0.0, 1.0);
    return math.exp(lw).round().clamp(_minWindow, _maxWindow).toInt();
  }

  void _seek(double localX, double width) {
    if (width <= 0) return;
    setState(() {
      _window = _windowForT(localX / width);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (widget.sweep.samples.length < 2) {
      // One sample → there's nothing to scrub between. Just show the
      // single-sample digest in the same slot so layout stays stable.
      return _ApertureScrubberReadout(
        sample: widget.sweep.samples.isEmpty
            ? null
            : widget.sweep.samples.first,
        tokens: t,
      );
    }
    final sample = widget.sweep.sampleAt(_currentWindow);
    final cursorT = _tForWindow(_currentWindow);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (ctx, constraints) {
            final width = constraints.maxWidth;
            return MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Listener(
                onPointerDown: (e) {
                  setState(() => _dragging = true);
                  _seek(e.localPosition.dx, width);
                },
                onPointerMove: (e) {
                  if (!_dragging) return;
                  _seek(e.localPosition.dx, width);
                },
                onPointerUp: (_) => setState(() => _dragging = false),
                onPointerCancel: (_) => setState(() => _dragging = false),
                child: SizedBox(
                  height: 28,
                  child: CustomPaint(
                    painter: _ApertureScrubberPainter(
                      sweep: widget.sweep,
                      cursorT: cursorT,
                      dragging: _dragging,
                      accent: t.accentBright,
                      faint: t.chromeBorder,
                      textFaint: t.textFaint,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        _ApertureScrubberReadout(sample: sample, tokens: t),
      ],
    );
  }
}

class _ApertureScrubberPainter extends CustomPainter {
  _ApertureScrubberPainter({
    required this.sweep,
    required this.cursorT,
    required this.dragging,
    required this.accent,
    required this.faint,
    required this.textFaint,
  });
  final ApertureSweep sweep;
  final double cursorT;
  final bool dragging;
  final Color accent;
  final Color faint;
  final Color textFaint;

  double _tForSample(ApertureSample s) {
    final lo = sweep.samples.first.window;
    final hi = sweep.samples.last.window;
    if (hi <= lo) return 0.0;
    final la = math.log(lo.toDouble());
    final lb = math.log(hi.toDouble());
    final lw = math.log(s.window.toDouble());
    return ((lw - la) / (lb - la)).clamp(0.0, 1.0).toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final midY = size.height / 2 + 4;
    // Track — hairline baseline the ticks stand on.
    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = faint.withValues(alpha: 0.35)
        ..strokeWidth = 0.75,
    );
    // Tick per real sample. Height reflects decisiveness so the user
    // sees at a glance which windows the engine read confidently.
    for (final s in sweep.samples) {
      final t = _tForSample(s);
      final x = t * size.width;
      final h = 6 + 10 * s.decisiveness.clamp(0.0, 1.0);
      canvas.drawLine(
        Offset(x, midY - h / 2),
        Offset(x, midY + h / 2),
        Paint()
          ..color = accent.withValues(alpha: 0.38 + 0.32 * s.decisiveness)
          ..strokeWidth = 1.4,
      );
    }
    // Cursor — fat line + soft halo. Halo brightens during drag to
    // confirm capture without a separate indicator.
    final cx = cursorT * size.width;
    final haloAlpha = dragging ? 0.22 : 0.12;
    canvas.drawLine(
      Offset(cx, 2),
      Offset(cx, size.height - 2),
      Paint()
        ..color = accent.withValues(alpha: haloAlpha)
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(cx, 4),
      Offset(cx, size.height - 4),
      Paint()
        ..color = accent.withValues(alpha: dragging ? 0.95 : 0.78)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _ApertureScrubberPainter old) =>
      old.cursorT != cursorT ||
      old.dragging != dragging ||
      !identical(old.sweep, sweep);
}

class _ApertureScrubberReadout extends StatelessWidget {
  const _ApertureScrubberReadout({
    required this.sample,
    required this.tokens,
  });
  final ApertureSample? sample;
  final AppTokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final s = sample;
    if (s == null) {
      return Text(
        'scrubbing unavailable — no samples yet',
        style: TextStyle(color: t.textMuted, fontSize: 10.5),
      );
    }
    final muted = TextStyle(
      color: t.textMuted,
      fontSize: 10,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      fontFamilyFallback: const ['monospace'],
    );
    final value = TextStyle(
      color: t.textNormal,
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      fontFamilyFallback: const ['monospace'],
    );
    String pair(String label, String body) => '$label $body';
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(pair('W', '${s.window}'),
            style: value.copyWith(color: t.accentBright)),
        Text(pair('ARCHETYPE', s.nearestArchetype), style: muted),
        Text(pair('FIEDLER', s.fiedler.toStringAsFixed(3)), style: muted),
        Text(pair('β₀/β₁', '${s.componentCount}/${s.cycleCount}'), style: muted),
        Text(pair('CENTRE', s.topHousekeepingPath), style: muted),
      ],
    );
  }
}

class _SectionSubHeader extends StatelessWidget {
  final String label;
  final String hint;
  const _SectionSubHeader({required this.label, required this.hint});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label,
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            )),
        const SizedBox(width: 6),
        Expanded(
          child: Text(hint,
              style: TextStyle(color: t.textMuted, fontSize: 10),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final String hint;
  const _SectionHeader({required this.label, required this.hint});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(label,
            style: TextStyle(
              color: t.textStrong,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            )),
        const SizedBox(width: 8),
        Expanded(
          child: Text(hint,
              style: TextStyle(color: t.textMuted, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _RingsClassificationRow extends StatelessWidget {
  final Map<String, String> classification;
  const _RingsClassificationRow({required this.classification});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (classification.isEmpty) {
      return Text('Observable classification unavailable.',
          style: TextStyle(color: t.textMuted, fontSize: 11));
    }
    Color colorFor(String cls) {
      switch (cls) {
        case 'invariant':
          return t.stateAdded;
        case 'running':
          return t.accentBright;
        case 'artifact':
          return t.textMuted;
      }
      return t.textMuted;
    }

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final entry in classification.entries)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: colorFor(entry.value).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: colorFor(entry.value).withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(entry.key,
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 10,
                    fontFamily: AppFonts.mono,
                  )),
              const SizedBox(width: 6),
              Text(entry.value,
                  style: TextStyle(
                    color: colorFor(entry.value),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  )),
            ]),
          ),
      ],
    );
  }
}

class _CenterTrajectoryList extends StatelessWidget {
  final List<CenterOfGravityStratum> strata;
  const _CenterTrajectoryList({required this.strata});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (strata.isEmpty) {
      return Text('No trajectory — only one stratum observed.',
          style: TextStyle(color: t.textMuted, fontSize: 11));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < strata.length; i++)
          _TrajectoryRow(
            stratum: strata[i],
            stratumIndex: i,
            total: strata.length,
          ),
      ],
    );
  }
}

class _TrajectoryRow extends StatelessWidget {
  final CenterOfGravityStratum stratum;
  final int stratumIndex;
  final int total;

  const _TrajectoryRow({
    required this.stratum,
    required this.stratumIndex,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Close-focus (first) = current activity; wide-focus (last) = history.
    final isFirst = stratumIndex == 0;
    final isLast = stratumIndex == total - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              'w=${stratum.window}',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: AppFonts.mono,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stratum.path,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 12,
                    fontFamily: AppFonts.mono,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (isFirst) 'close focus · current attention',
                    if (isLast) 'wide focus · deepest stratum',
                    'archetype: ${stratum.nearestArchetype}',
                  ].join('  ·  '),
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
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

class _EventCard extends StatelessWidget {
  final ApertureEvent event;
  const _EventCard({required this.event});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      borderAlpha: 0.22,
      elevated: false,
      innerHighlight: false,
      glaze: false,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  'aperture ${event.fromWindow}→${event.toWindow}',
                  style: TextStyle(
                    color: t.textStrong,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFonts.mono,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'mag ${event.magnitude.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: AppFonts.mono,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final obs in event.flippedObservables)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: t.accentBright.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(
                        color: t.accentBright.withValues(alpha: 0.35),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      obs,
                      style: TextStyle(
                        color: t.textNormal,
                        fontSize: 10,
                        fontFamily: AppFonts.mono,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Summary view — lives inside the xray panel as its fourth tab. Runs
// the repo_summary pipeline on a background isolate and renders the
// markdown result with Copy + Save actions.
// ─────────────────────────────────────────────────────────────────────

class _SummaryView extends StatefulWidget {
  final String repoPath;
  final rs.RepoDoc? initialDoc;
  final String? initialMarkdown;
  final String? initialError;
  final String? initialPresentedHtml;
  final void Function(rs.RepoDoc?, String?, String?, String?) onStateChanged;

  const _SummaryView({
    required this.repoPath,
    required this.initialDoc,
    required this.initialMarkdown,
    required this.initialError,
    required this.initialPresentedHtml,
    required this.onStateChanged,
  });
  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  bool _generating = false;
  bool _presenting = false;
  int _presentPromptChars = 0;
  int _presentOutputChars = 0;
  late rs.RepoDoc? _doc = widget.initialDoc;
  late String? _markdown = widget.initialMarkdown;
  late String? _error = widget.initialError;
  late String? _presentedHtml = widget.initialPresentedHtml;
  bool _presentMode = false;
  final _presentCtrl = TextEditingController();
  final _presentFocus = FocusNode();
  final _keyboardFocus = FocusNode();

  void _pushState() {
    widget.onStateChanged(_doc, _markdown, _error, _presentedHtml);
  }

  @override
  void dispose() {
    _presentCtrl.dispose();
    _presentFocus.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _enterPresentMode() {
    if (_presentMode) return;
    setState(() => _presentMode = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _presentFocus.requestFocus();
    });
  }

  void _exitPresentMode() {
    if (!_presentMode) return;
    setState(() => _presentMode = false);
  }

  @override
  void didUpdateWidget(covariant _SummaryView old) {
    super.didUpdateWidget(old);
    if (old.repoPath != widget.repoPath) {
      _doc = null;
      _markdown = null;
      _error = null;
      _presentedHtml = null;
      _generating = false;
      _presenting = false;
      _presentMode = false;
      _presentCtrl.clear();
      _presentPromptChars = 0;
      _presentOutputChars = 0;
    }
  }

  Future<void> _runGenerate() async {
    if (_generating) return;
    final repoPath = widget.repoPath;
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final rootToken = RootIsolateToken.instance!;
      final doc = await compute<_SummaryJob, rs.RepoDoc>(
        _runSummaryJob,
        _SummaryJob(rootToken: rootToken, repoPath: repoPath),
      );
      if (!mounted) return;
      if (widget.repoPath != repoPath) {
        setState(() => _generating = false);
        return;
      }
      setState(() {
        _doc = doc;
        _markdown = repoDocToMarkdown(doc);
        _generating = false;
      });
      _pushState();
    } on Object catch (e) {
      if (!mounted) return;
      if (widget.repoPath != repoPath) {
        setState(() => _generating = false);
        return;
      }
      setState(() {
        _error = 'Analysis failed: $e';
        _generating = false;
      });
      _pushState();
    }
  }

  Future<void> _copyToClipboard() async {
    final md = _markdown;
    if (md == null) return;
    await Clipboard.setData(ClipboardData(text: md));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Summary copied to clipboard.'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _saveToFile() async {
    final md = _markdown;
    if (md == null) return;
    final defaultName = '${_doc?.repoName ?? 'repo'}-summary.md';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save repository summary',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['md'],
      );
      if (path == null) return;
      await File(path).writeAsString(md);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved to $path'),
        duration: const Duration(seconds: 3),
      ));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  Future<void> _runPresent() async {
    if (_presenting) return;
    final md = _markdown;
    final doc = _doc;
    if (md == null || doc == null) return;
    final repoPath = widget.repoPath;
    final repoName = doc.repoName;
    final aiSettings = context.read<AiSettingsState>();
    final activity = context.read<AiActivityState>();
    final categoryId = aiSettings.presentModelCategoryId;
    final modelValue = aiSettings.modelSelections[categoryId] ?? '';
    if (modelValue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No AI model configured.'),
        duration: Duration(seconds: 3),
      ));
      return;
    }

    final scopeKey = 'present:$repoPath';
    setState(() => _presenting = true);
    activity.start(
      repoPath: repoPath,
      kind: AiActivityKind.present,
      scopeKey: scopeKey,
      scopeLabel: _presentCtrl.text.trim().isEmpty
          ? null
          : _presentCtrl.text.trim(),
    );

    try {
      final dataJson = const JsonEncoder.withIndent('  ').convert(doc.toJson());
      final userDirection = _presentCtrl.text.trim();
      final customPrompt = aiSettings.presentPrompt.trim();

      final instruction = customPrompt.isNotEmpty
          ? customPrompt
          : 'You are a production designer building a one-page interactive '
              'experience. Your audience has never seen this codebase. Your '
              'job is to make them *feel* its shape — what it does, how it\'s '
              'organized, where the weight sits, how the pieces connect — in '
              'under sixty seconds of scrolling.\n\n'
              'You have one input: a structured RepoDoc (JSON) measured '
              'from the repository\'s actual git history and file structure. '
              'Every number is evidence. The JSON IS the source of truth — '
              'render it, don\'t re-interpret it.\n\n'
              'THE DATA\n'
              '- files[]: every active file. centrality = structural importance '
              '(0-1). activity = how actively changed. authenticity = signal vs '
              'noise (0 = mechanical churn, 1 = intentional work). role = '
              'source/test/doc/etc. regionId = which cluster it belongs to. '
              'well = semantic concept.\n'
              '- couplingEdges[]: files that change together, with strength. '
              'This IS the dependency structure — not imports, but co-evolution.\n'
              '- regions[]: clusters of related files. cohesion = how self-'
              'contained (0-1). themes = what the cluster is about. '
              'neighborNames = which other regions it talks to.\n'
              '- regionLinks[]: the weight of connections between regions.\n'
              '- backbone[]: the load-bearing files. keystoneScore combines '
              'centrality with stability — high score = important AND reliable.\n'
              '- archetypeDistances: proximity to 6 architecture shapes '
              '(lower = closer). tree = spine with branches. modular = '
              'independent clusters. bulk = one big ball. crystalline = '
              'regular lattice. poisson = loosely coupled. goe = richly '
              'interconnected.\n'
              '- stats: the numbers at a glance.\n\n'
              'CREATIVE DIRECTION\n'
              'Build something someone would want to send to their team. '
              'Use the data to drive real visualizations — graphs, charts, '
              'spatial layouts, whatever the data calls for. Let the '
              'topology of the code inform the topology of the page. '
              'Surprise with craft, not with noise.\n\n'
              'CONSTRAINTS\n'
              'Single self-contained HTML file. All CSS and JS inline. '
              'Zero external dependencies. Output the HTML directly — no '
              'explanation, no markdown fences, no preamble.';

      final parts = <String>[instruction];
      if (userDirection.isNotEmpty) {
        parts.add('\nUSER DIRECTION\n$userDirection');
      }
      parts.add('\n---\n\n## Repository Data\n```json\n$dataJson\n```');
      final prompt = parts.join('\n');
      _presentPromptChars = prompt.length;

      final effort = aiSettings.resolveEffort(categoryId, modelValue);
      final modelInfo = aiSettings.runtimeModelCategories
          .expand((c) => c.models)
          .where((m) => m.value == modelValue)
          .firstOrNull;

      final r = await runAsk(
        repositoryPath: repoPath,
        modelValue: modelValue,
        prompt: prompt,
        reasoningEffort: effort.effort,
        fastMode: effort.fast,
        supportsReasoning: modelInfo?.supportsReasoning ?? true,
        commandLabelPrefix: 'ai.present',
        maxTokens: 65536,
      );

      if (!mounted) return;
      if (widget.repoPath != repoPath) {
        setState(() => _presenting = false);
        return;
      }
      if (!r.ok) {
        activity.fail(
          repoPath: repoPath,
          kind: AiActivityKind.present,
          error: r.error ?? 'Present failed.',
          scopeKey: scopeKey,
        );
        setState(() => _presenting = false);
        _pushState();
        return;
      }

      var html = (r.data ?? '').trim();
      if (html.startsWith('```')) {
        final firstNewline = html.indexOf('\n');
        if (firstNewline != -1) html = html.substring(firstNewline + 1);
        if (html.endsWith('```')) {
          html = html.substring(0, html.length - 3).trimRight();
        }
      }
      if (!html.startsWith('<') && !html.startsWith('<!')) {
        final doctype = html.indexOf('<!');
        final tag = html.indexOf('<html');
        final first = doctype >= 0 && (tag < 0 || doctype < tag)
            ? doctype
            : tag;
        if (first > 0) html = html.substring(first);
      }

      _presentOutputChars = html.length;
      final tempDir = Directory.systemTemp;
      final safeName = repoName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-.]'), '_');
      final filePath =
          '${tempDir.path}${Platform.pathSeparator}$safeName-present.html';
      await File(filePath).writeAsString(html);

      if (Platform.isWindows) {
        await Process.run(
          'cmd',
          ['/c', 'start', '""', '"${filePath.replaceAll('/', '\\')}"'],
          runInShell: true,
        );
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else {
        await Process.run('xdg-open', [filePath]);
      }

      if (!mounted) return;
      if (widget.repoPath != repoPath) {
        setState(() => _presenting = false);
        return;
      }
      activity.complete(
        repoPath: repoPath,
        kind: AiActivityKind.present,
        result: AiPresentResult(html: html, filePath: filePath),
        scopeKey: scopeKey,
      );
      activity.markSeen(
        repoPath: repoPath,
        kind: AiActivityKind.present,
      );
      setState(() {
        _presenting = false;
        _presentedHtml = html;
      });
      _pushState();
    } on Object catch (e) {
      if (!mounted) return;
      activity.fail(
        repoPath: repoPath,
        kind: AiActivityKind.present,
        error: 'Present failed: $e',
        scopeKey: scopeKey,
      );
      setState(() => _presenting = false);
      _pushState();
    }
  }

  Future<void> _downloadPresentation() async {
    final html = _presentedHtml;
    if (html == null) return;
    final defaultName = '${_doc?.repoName ?? 'repo'}-presentation.html';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save presentation',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: const ['html'],
      );
      if (path == null) return;
      await File(path).writeAsString(html);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Saved to $path'),
        duration: const Duration(seconds: 3),
      ));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Save failed: $e'),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final aiSettings = context.watch<AiSettingsState>();
    final categoryId = aiSettings.presentModelCategoryId;
    final modelValue = aiSettings.modelSelections[categoryId] ?? '';
    final hasModel = modelValue.isNotEmpty;
    final categoryLabel =
        aiSettings.labelForCategory(categoryId, 'Quality').toLowerCase();
    final canPresent = _markdown != null && hasModel;

    return _PanelBlock(
      child: KeyboardListener(
        focusNode: _keyboardFocus,
        onKeyEvent: (event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape &&
              _presentMode &&
              !_presenting) {
            _exitPresentMode();
          }
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SummaryToolbar(
              generating: _generating,
              presenting: _presenting,
              presentMode: _presentMode,
              hasDoc: _markdown != null,
              hasModel: hasModel,
              hasPresentation: _presentedHtml != null,
              presentCategoryLabel: categoryLabel,
              onGenerate: _runGenerate,
              onCopy: _markdown == null ? null : _copyToClipboard,
              onSave: _markdown == null ? null : _saveToFile,
              onPresentTap: canPresent ? _enterPresentMode : null,
              onPresentSubmit:
                  canPresent && !_presenting ? _runPresent : null,
              onPresentDismiss: _exitPresentMode,
              onDownloadPresentation:
                  _presentedHtml == null ? null : _downloadPresentation,
              presentController: _presentCtrl,
              presentFocusNode: _presentFocus,
              presentPromptChars: _presentPromptChars,
              presentOutputChars: _presentOutputChars,
            ),
            const SizedBox(height: 8),
            Expanded(child: _summaryBody()),
          ],
        ),
      ),
    );
  }

  Widget _summaryBody() {
    final t = context.tokens;
    if (_generating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 22, height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(t.accentBright),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Reading the repo and clustering features…',
              style: TextStyle(color: t.textMuted, fontSize: 12),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _error!,
            style: TextStyle(color: t.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final md = _markdown;
    if (md == null) {
      return Center(
        child: Text(
          'Run Logos analysis to map this repository\'s structure and regions.',
          style: TextStyle(color: t.textMuted, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );
    }
    return Markdown(
      data: md,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      selectable: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(color: t.textNormal, fontSize: 13, height: 1.55),
        h1: TextStyle(
          color: t.textNormal, fontSize: 20,
          fontWeight: FontWeight.w700, height: 1.3,
        ),
        h2: TextStyle(
          color: t.textNormal, fontSize: 16,
          fontWeight: FontWeight.w600, height: 1.3,
        ),
        h3: TextStyle(
          color: t.accentBright, fontSize: 13,
          fontWeight: FontWeight.w600, height: 1.3,
        ),
        code: TextStyle(
          color: t.accentBright,
          fontFamily: AppFonts.mono,
          fontSize: 11,
          backgroundColor: t.chromeBorder.withValues(alpha: 0.3),
        ),
        codeblockDecoration: BoxDecoration(
          color: t.chromeBorder.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        blockquote: TextStyle(
          color: t.textMuted, fontStyle: FontStyle.italic, fontSize: 12,
        ),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(
            color: t.accentBright.withValues(alpha: 0.4), width: 3,
          )),
          color: t.chromeBorder.withValues(alpha: 0.1),
        ),
        listBullet: TextStyle(color: t.textNormal, fontSize: 13),
        strong: TextStyle(color: t.textNormal, fontWeight: FontWeight.w700),
        em: TextStyle(color: t.textMuted, fontStyle: FontStyle.italic),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: t.chromeBorder, width: 1),
          ),
        ),
      ),
    );
  }
}

String _tokensK(int chars) {
  final t = chars ~/ 4;
  return t >= 1000 ? '${(t / 1000).toStringAsFixed(1)}k' : '$t';
}

class _SummaryToolbar extends StatelessWidget {
  const _SummaryToolbar({
    required this.generating,
    required this.presenting,
    required this.presentMode,
    required this.hasDoc,
    required this.hasModel,
    required this.hasPresentation,
    required this.presentCategoryLabel,
    required this.onGenerate,
    required this.onCopy,
    required this.onSave,
    required this.onPresentTap,
    required this.onPresentSubmit,
    required this.onPresentDismiss,
    required this.onDownloadPresentation,
    required this.presentController,
    required this.presentFocusNode,
    this.presentPromptChars = 0,
    this.presentOutputChars = 0,
  });
  final bool generating;
  final bool presenting;
  final bool presentMode;
  final bool hasDoc;
  final bool hasModel;
  final bool hasPresentation;
  final String presentCategoryLabel;
  final VoidCallback onGenerate;
  final VoidCallback? onCopy;
  final VoidCallback? onSave;
  final VoidCallback? onPresentTap;
  final VoidCallback? onPresentSubmit;
  final VoidCallback onPresentDismiss;
  final VoidCallback? onDownloadPresentation;
  final TextEditingController presentController;
  final FocusNode presentFocusNode;
  final int presentPromptChars;
  final int presentOutputChars;

  @override
  Widget build(BuildContext context) {
    final submitLabel = presenting
        ? 'presenting with $presentCategoryLabel…'
        : 'present with $presentCategoryLabel';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          _SummaryActionButton(
            label: hasDoc ? 'Re-analyze' : 'Analyze',
            icon: 'sync',
            primary: true,
            loading: generating,
            onTap: generating ? null : onGenerate,
          ),
          const SizedBox(width: 6),
          _SummaryActionButton(label: 'Copy', icon: 'check', onTap: onCopy),
          const SizedBox(width: 6),
          _SummaryActionButton(label: 'Save', icon: 'fetch', onTap: onSave),
          if (hasPresentation && presentMode) ...[
            const SizedBox(width: 6),
            _SummaryActionButton(
              label: 'Download',
              icon: 'fetch',
              onTap: onDownloadPresentation,
            ),
          ],
          const Spacer(),
          if (presentMode) ...[
            _SummaryActionButton(
              label: 'Exit',
              icon: 'check',
              onTap: onPresentDismiss,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: AppTextField(
                  controller: presentController,
                  focusNode: presentFocusNode,
                  hintText: 'direction',
                  height: 28,
                  fontSize: 11.5,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  enabled: !presenting,
                  onSubmitted: (_) => onPresentSubmit?.call(),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SummaryActionButton(
              label: submitLabel,
              icon: 'push',
              primary: true,
              loading: presenting,
              onTap: onPresentSubmit,
            ),
            if (presentPromptChars > 0) ...[
              const SizedBox(width: 8),
              Text(
                '${_tokensK(presentPromptChars)} → ${_tokensK(presentOutputChars)}',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 9,
                  color: context.tokens.textFaint.withValues(alpha: 0.6),
                ),
              ),
            ],
          ] else ...[
            _SummaryActionButton(
              label: !hasModel
                  ? 'no AI model configured'
                  : 'present with $presentCategoryLabel',
              icon: 'push',
              onTap: onPresentTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryActionButton extends StatelessWidget {
  const _SummaryActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.primary = false,
    this.loading = false,
  });
  final String label;
  final String icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final disabled = onTap == null;
    final fg = disabled
        ? t.textMuted
        : (primary ? t.accentBright : t.textNormal);
    final bg = primary && !disabled
        ? t.accentBright.withValues(alpha: 0.10)
        : Colors.transparent;
    final radius = BorderRadius.circular(6);
    return HoverableTap(
      onTap: onTap,
      borderRadius: radius,
      builder: (context, hovered) => AnimatedContainer(
        duration: AppMotion.snap,
        curve: AppMotion.snapCurve,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: hovered && !disabled
              ? (primary
                  ? t.accentBright.withValues(alpha: 0.16)
                  : t.chromeBorder.withValues(alpha: 0.15))
              : bg,
          borderRadius: radius,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 12, height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(fg),
                ),
              )
            else
              AppIcon(name: icon, size: 12, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: fg, fontSize: 11.5, fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message sent from the main isolate to the summary worker isolate.
/// Carries the [RootIsolateToken] the worker needs to bootstrap plugin
/// channels so `runGitProbe`, diagnostics writers, and path-provider
/// calls all succeed from inside `compute`.
class _SummaryJob {
  const _SummaryJob({required this.rootToken, required this.repoPath});
  final RootIsolateToken rootToken;
  final String repoPath;
}

/// Top-level worker entry for `compute`. Initialises the binary
/// messenger, then delegates to the pipeline. Must be top-level (not
/// a closure or instance method) so its tear-off is sendable to the
/// background isolate.
Future<rs.RepoDoc> _runSummaryJob(_SummaryJob job) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(job.rootToken);
  return generateRepoSummary(job.repoPath);
}

