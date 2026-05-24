import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/logos_git_state.dart';
import '../../app/repository_state.dart';
import '../../backend/git.dart' show runGitProbe;
import '../../backend/gyat.dart' show GyatLattice, gyatForRepo;
import '../../backend/logos_core.dart' show FlowSseLattice, flowKGInteractionStrength;
import '../../backend/logos_flow.dart'
    show analyzeFlowCached, analyzeInterFile, CrossFileInterference, crossFileMix, dreamAnalysis, FlowAnalysisResult, FlowBugKind, FlowFinding, InterFileResult;
import '../../ui/tokens.dart';

/// Stability region in the coherence × lyapunov plane.
///   `·` coherent + low impact    — stable, uninteresting
///   `›` coherent + high impact   — directed energy, worth watching
///   `~` incoherent + low impact  — scattered but harmless
///   `◆` incoherent + high impact — turbulent, most concerning
///   `※` contradictory flow       — bimodal confident disagreement
String _stabilityGlyph(
    double coherence, double lyapunov, FlowBugKind kind) {
  if (kind == FlowBugKind.contradictoryFlow) return '※';
  final coherent = coherence >= 0.75;
  final impactful = lyapunov >= 0.7;
  if (coherent && !impactful) return '·';
  if (coherent && impactful) return '›';
  if (!coherent && !impactful) return '~';
  return '◆';
}

class FilamentFindingsPanel extends StatefulWidget {
  const FilamentFindingsPanel({super.key});

  @override
  State<FilamentFindingsPanel> createState() => _FilamentFindingsPanelState();
}

class _FilamentFindingsPanelState extends State<FilamentFindingsPanel> {
  final Map<String, FlowAnalysisResult> _results = {};
  final Map<String, FlowAnalysisResult> _rawResults = {};
  FlowSseLattice _lattice = FlowSseLattice();
  GyatLattice? _gyat;
  List<CrossFileInterference> _crossFileInterference = const [];
  InterFileResult? _interFileResult;
  double _kgInteraction = 0.0;
  int _totalFiles = 0;
  int _scannedFiles = 0;
  bool _done = false;
  bool _scanLightweight = false;
  int _gen = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repoPath = context.read<RepositoryState>().activePath;
    if (repoPath != null && !_done && _gen == 0) {
      _scan(repoPath);
    }
  }

  Future<void> _scan(String repoPath) async {
    final gen = ++_gen;

    // ── GYAT: restore the repo's lifelong lattice ───────────────────
    final gyat = await gyatForRepo(repoPath);
    if (!mounted || _gen != gen) return;
    _gyat = gyat;

    // ── Scale 2: inter-file structural scan ─────────────────────────
    // If the Logos engine is available, run the oscillator on the
    // co-change graph first. Per-file certainties feed into Scale 1
    // as logosCoupling.
    final engine = context.read<LogosGitState>().engineFor(repoPath);
    InterFileResult? interFile;
    if (engine != null) {
      final basis = engine.spectralBasis();
      if (basis != null) {
        interFile = analyzeInterFile(
          engine.graph,
          basis,
          nodePaths: engine.nodePaths,
        );
      }
    }
    if (!mounted || _gen != gen) return;
    _interFileResult = interFile;

    // ── Scale 1: per-file flow scan ─────────────────────────────────
    final probe = await runGitProbe(repoPath, ['ls-files']);
    if (!mounted || _gen != gen) return;
    if (probe.exitCode != 0) {
      setState(() => _done = true);
      return;
    }

    final allPaths = const LineSplitter()
        .convert(probe.stdout.toString())
        .where((l) => l.isNotEmpty)
        .toList();

    setState(() => _totalFiles = allPaths.length);

    // Snapshot the GYAT prior once per scan. The lattice may change
    // during the scan as observations land, but we want a stable
    // prior across the batch so walker novelty doesn't drift mid-scan.
    final globalCouplingW = gyat.globalCoupling?.rawWeights;
    final priorMeans = gyat.cellMeansSnapshot;
    final priorCounts = gyat.cellCountsSnapshot;

    const concurrency = 8;
    // Once the lattice reaches its factored fixpoint mid-scan, further
    // walker depth contributes no new spectral information. Switch
    // remaining batches to a lightweight probe — same address coverage,
    // shorter walks. Sticky: never flips back from light to deep within
    // a single scan (avoids oscillation if a late batch perturbs the
    // factoredness signal momentarily).
    var lightweight = false;
    for (var i = 0; i < allPaths.length; i += concurrency) {
      if (!mounted || _gen != gen) return;
      if (!lightweight && _lattice.isFactored) {
        lightweight = true;
      }
      final batchLightweight = lightweight;
      final batch = allPaths.skip(i).take(concurrency).map((fp) async {
        try {
          // Scale 2 certainty → logosCoupling for this file.
          final coupling = interFile?.certaintyForPath(
              fp, engine?.pathToId ?? const {});
          final result = await analyzeFlowCached(
            p.join(repoPath, fp),
            logosCoupling: coupling,
            globalCouplingWeights: globalCouplingW,
            priorMeans: priorMeans,
            priorCounts: priorCounts,
            lightweight: batchLightweight,
          );
          if (result != null && result.findings.isNotEmpty) {
            return (fp, result);
          }
        } catch (_) {}
        return null;
      });
      final results = await Future.wait(batch);
      if (!mounted || _gen != gen) return;
      setState(() {
        _scannedFiles = (i + concurrency).clamp(0, allPaths.length);
        for (final r in results) {
          if (r != null) {
            _rawResults[r.$1] = r.$2;
            r.$2.accumulateInto(_lattice);
          }
        }
      });
    }

    _scanLightweight = lightweight;

    // ── Calibration pipeline ────────────────────────────────────────
    //   1. dream iterates to spectral fixed point (factoredness ≥ noise
    //      floor) — bounded by hypercube diameter (8 max). Skipped
    //      entirely when the lattice is already factored — additional
    //      iterations don't change anything past fixpoint.
    //   2. cross-file mix adds inter-file Born interference
    //   3. filter reads the fully converged lattice
    if (_lattice.totalObservations > 0) {
      if (!_lattice.isFactored) {
        final warmSet = <int>{};
        for (var a = 0; a < 256; a++) {
          if (_lattice.cellCount(a) >= 8) warmSet.add(a);
        }
        final h = _lattice.entropy(warmSet);
        final maxIter = h.ceil().clamp(2, 8);
        for (var iter = 0; iter < maxIter; iter++) {
          dreamAnalysis(_lattice);
          if (_lattice.isFactored) break;
        }
      }
      _crossFileInterference = crossFileMix(_rawResults, _lattice);
    }

    if (!mounted || _gen != gen) return;

    // Walsh-adaptive sigma: K-G interaction strength measures how much
    // genuine multi-body coupling the factored per-axis model can't
    // explain. High → lower threshold (storm, catch more). Low → higher
    // threshold (calm, reduce noise). Range: sigma ∈ [0.75, 1.5].
    _kgInteraction = flowKGInteractionStrength(_lattice);
    final adaptiveSigma = 1.5 / (1.0 + _kgInteraction);

    final calibrated = <String, FlowAnalysisResult>{};
    for (final entry in _rawResults.entries) {
      final filtered = entry.value.filterBy(_lattice, sigma: adaptiveSigma);
      if (filtered.findings.isNotEmpty) {
        calibrated[entry.key] = filtered;
      }
    }

    // ── GYAT: absorb this scan into the session lattice ───────────
    // No disk write — the lattice lives in-memory only. Bootstrap
    // re-derives it from git on next session start.
    gyat.absorb(_lattice);


    if (!mounted || _gen != gen) return;
    setState(() {
      _results.clear();
      _results.addAll(calibrated);
      _scannedFiles = allPaths.length;
      _done = true;
    });
  }

  String _formatFindings() {
    final sorted = _results.entries.toList()
      ..sort((a, b) => b.value.spectralGap.compareTo(a.value.spectralGap));

    var total = 0;
    var crit = 0;
    var warn = 0;
    var info = 0;
    var joints = 0;
    for (final entry in _results.values) {
      for (final f in entry.findings) {
        total++;
        if (f.kind == FlowBugKind.contradictoryFlow) {
          joints++;
        } else if (f.certainty < 0.1) {
          crit++;
        } else if (f.certainty < 0.3) {
          warn++;
        } else {
          info++;
        }
      }
    }

    final buf = StringBuffer();
    final sigmaStr = (1.5 / (1.0 + _kgInteraction)).toStringAsFixed(2);
    final gyatObs = _gyat?.lattice.totalObservations ?? 0;
    final gyatFe = _gyat?.negLogPartition().toStringAsFixed(3) ?? '—';
    buf.writeln('filament $total findings across ${_results.length} files '
        '[C=$crit W=$warn I=$info J=$joints] '
        'σ=$sigmaStr kg=${_kgInteraction.toStringAsFixed(2)}');
    final fact = _lattice.factoredness.toStringAsFixed(2);
    final factTag = _lattice.isFactored ? '✓' : '';
    final lightTag = _scanLightweight ? ' ⚡' : '';
    buf.writeln(
        '  gyat: ${gyatObs}obs F=$gyatFe  scan: fact=$fact$factTag$lightTag');
    buf.writeln('  ·stable ›directed ~scattered ◆turbulent ※joint');
    buf.writeln();

    for (final entry in sorted) {
      final path = entry.key;
      final result = entry.value;
      final gap = result.spectralGap;
      final findings = [...result.findings]
        ..sort((a, b) => b.composite.compareTo(a.composite));

      buf.writeln('── $path (${gap.toStringAsFixed(2)})');
      for (final f in findings) {
        final sev = f.kind == FlowBugKind.contradictoryFlow
            ? 'J'
            : f.certainty < 0.1
                ? 'C'
                : f.certainty < 0.3
                    ? 'W'
                    : 'I';
        final kind = switch (f.kind) {
          FlowBugKind.staleValue => 'stale',
          FlowBugKind.temporalShift => 'temporal',
          FlowBugKind.contextInversion => 'context',
          FlowBugKind.contradictoryFlow => 'joint',
        };
        final glyph = _stabilityGlyph(f.coherence, f.lyapunov, f.kind);
        final raw = f.sourceText;
        final src = raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
        buf.writeln(
            '  $sev$glyph L${f.sourceLine + 1} $kind '
            '[${f.composite.toStringAsFixed(2)} '
            'p=${f.pathCount}] $src');
      }
    }

    if (_interFileResult != null && _interFileResult!.findings.isNotEmpty) {
      buf.writeln();
      buf.writeln('── inter-file structural '
          '(${_interFileResult!.findings.length} findings, '
          'gap=${_interFileResult!.spectralGap.toStringAsFixed(2)})');
      for (final f in _interFileResult!.findings) {
        final hex = f.address.toRadixString(16).padLeft(2, '0');
        final kind = switch (f.kind) {
          FlowBugKind.staleValue => 'stale',
          FlowBugKind.temporalShift => 'temporal',
          FlowBugKind.contextInversion => 'context',
          FlowBugKind.contradictoryFlow => 'joint',
        };
        final glyph = _stabilityGlyph(f.coherence, f.lyapunov, f.kind);
        buf.writeln('  $glyph 0x$hex $kind '
            '[cert=${f.certainty.toStringAsFixed(2)} '
            'p=${f.pathCount}] ${f.sourceText}');
      }
    }

    if (_crossFileInterference.isNotEmpty) {
      buf.writeln();
      buf.writeln('── cross-file interference '
          '(${_crossFileInterference.length} addresses)');
      for (final x in _crossFileInterference) {
        final hex = x.address.toRadixString(16).padLeft(2, '0');
        final tag = x.contradictory ? ' — ※joint' : '';
        buf.writeln('  0x$hex · ${x.fileCount} files · '
            'coh=${x.coherence.toStringAsFixed(2)} · '
            'cert=${x.certainty.toStringAsFixed(2)}$tag');
        buf.writeln('    ${x.files.join('  ')}');
      }
    }

    return buf.toString().trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repoPath = context.watch<RepositoryState>().activePath;

    if (repoPath == null) {
      return Center(
        child: Text(
          'No repository open.',
          style: TextStyle(color: t.textMuted, fontSize: 12),
        ),
      );
    }

    final sortedFiles = _results.entries.toList()
      ..sort((a, b) => b.value.spectralGap.compareTo(a.value.spectralGap));

    var totalFindings = 0;
    var critCount = 0;
    var warnCount = 0;
    var infoCount = 0;
    var jointCount = 0;
    for (final entry in _results.values) {
      for (final f in entry.findings) {
        totalFindings++;
        if (f.kind == FlowBugKind.contradictoryFlow) {
          jointCount++;
        } else if (f.certainty < 0.1) {
          critCount++;
        } else if (f.certainty < 0.3) {
          warnCount++;
        } else {
          infoCount++;
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_done) ...[
                Text(
                  'scanning $_scannedFiles / $_totalFiles files…',
                  style: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.7),
                    fontSize: 11,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: _totalFiles > 0
                        ? _scannedFiles / _totalFiles
                        : null,
                    backgroundColor: t.chromeBorder.withValues(alpha: 0.15),
                    color: t.accentBright.withValues(alpha: 0.5),
                    minHeight: 2,
                  ),
                ),
              ],
              if (_done || _results.isNotEmpty) ...[
                if (_done) const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$totalFindings findings across ${_results.length} files',
                        style: TextStyle(
                          color: t.textMuted.withValues(alpha: 0.7),
                          fontSize: 11,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    if (_done && totalFindings > 0)
                      _CopyButton(
                        onTap: () {
                          Clipboard.setData(
                              ClipboardData(text: _formatFindings()));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied $totalFindings findings'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        t: t,
                      ),
                  ],
                ),
                if (critCount > 0 || warnCount > 0 || infoCount > 0 ||
                    jointCount > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (critCount > 0)
                        _SeverityPill(
                            label: 'critical', count: critCount, t: t),
                      if (warnCount > 0) ...[
                        if (critCount > 0) const SizedBox(width: 8),
                        _SeverityPill(label: 'warn', count: warnCount, t: t),
                      ],
                      if (infoCount > 0) ...[
                        if (critCount > 0 || warnCount > 0)
                          const SizedBox(width: 8),
                        _SeverityPill(label: 'info', count: infoCount, t: t),
                      ],
                      if (jointCount > 0) ...[
                        if (critCount > 0 || warnCount > 0 || infoCount > 0)
                          const SizedBox(width: 8),
                        _SeverityPill(
                            label: 'joint', count: jointCount, t: t),
                      ],
                    ],
                  ),
                ],
              ],
              const SizedBox(height: 12),
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    t.chromeBorder.withValues(alpha: 0),
                    t.chromeBorder.withValues(alpha: 0.35),
                    t.chromeBorder.withValues(alpha: 0),
                  ]),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: sortedFiles.isEmpty && _done
              ? Center(
                  child: Text(
                    'No execution-flow findings.',
                    style: TextStyle(
                      color: t.textMuted.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: sortedFiles.length,
                  itemBuilder: (context, index) {
                    final entry = sortedFiles[index];
                    final findings = [...entry.value.findings]
                      ..sort(
                          (a, b) => b.composite.compareTo(a.composite));
                    return _FileSection(
                      path: entry.key,
                      gap: entry.value.spectralGap,
                      findings: findings,
                      t: t,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  final VoidCallback onTap;
  final AppTokens t;
  const _CopyButton({required this.onTap, required this.t});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered
                ? t.chromeBorder.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: t.chromeBorder.withValues(alpha: _hovered ? 0.3 : 0.18),
            ),
          ),
          child: Text(
            'COPY',
            style: TextStyle(
              color: t.textMuted.withValues(alpha: _hovered ? 0.8 : 0.6),
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _SeverityPill extends StatelessWidget {
  final String label;
  final int count;
  final AppTokens t;
  const _SeverityPill({
    required this.label,
    required this.count,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '$label $count',
      style: TextStyle(
        color: t.textMuted.withValues(alpha: 0.55),
        fontSize: 10,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _FileSection extends StatelessWidget {
  final String path;
  final double gap;
  final List<FlowFinding> findings;
  final AppTokens t;
  const _FileSection({
    required this.path,
    required this.gap,
    required this.findings,
    required this.t,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                gap.toStringAsFixed(2),
                style: TextStyle(
                  color: t.accentBright.withValues(alpha: 0.85),
                  fontSize: 10,
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final f in findings) ...[
            _FindingRow(finding: f, t: t),
            const SizedBox(height: 2),
          ],
        ],
      ),
    );
  }
}

class _FindingRow extends StatelessWidget {
  final FlowFinding finding;
  final AppTokens t;
  const _FindingRow({required this.finding, required this.t});

  @override
  Widget build(BuildContext context) {
    final sev = finding.severity;
    final sevColor = switch (sev) {
      'critical' => t.textStrong,
      'warn' => t.textNormal,
      'joint' => t.accentBright,
      _ => t.textMuted.withValues(alpha: 0.6),
    };
    final kind = switch (finding.kind) {
      FlowBugKind.staleValue => 'stale value',
      FlowBugKind.temporalShift => 'temporal shift',
      FlowBugKind.contextInversion => 'context inversion',
      FlowBugKind.contradictoryFlow => 'contradictory flow',
    };
    final glyph =
        _stabilityGlyph(finding.coherence, finding.lyapunov, finding.kind);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            '$sev$glyph',
            style: TextStyle(
              color: sevColor,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Text(
          'L${finding.sourceLine + 1}',
          style: TextStyle(
            color: t.textMuted.withValues(alpha: 0.5),
            fontSize: 9,
            fontFamily: 'monospace',
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${finding.sourceText} — $kind',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: t.textMuted.withValues(alpha: 0.65),
              fontSize: 9.5,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}
