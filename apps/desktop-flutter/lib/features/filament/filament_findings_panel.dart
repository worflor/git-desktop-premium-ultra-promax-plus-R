import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../app/repository_state.dart';
import '../../backend/git.dart' show runGitProbe;
import '../../backend/logos_core.dart' show FlowSseLattice;
import '../../backend/logos_flow.dart'
    show analyzeFlowCached, FlowAnalysisResult, FlowBugKind, FlowFinding;
import '../../ui/tokens.dart';

const _codeExtensions = {
  '.dart', '.js', '.ts', '.tsx', '.jsx', '.py', '.go', '.rs',
  '.java', '.kt', '.swift', '.rb', '.cpp', '.c', '.h', '.hpp',
  '.cs', '.lua', '.php', '.scala', '.zig', '.vue', '.svelte',
};

class FilamentFindingsPanel extends StatefulWidget {
  const FilamentFindingsPanel({super.key});

  @override
  State<FilamentFindingsPanel> createState() => _FilamentFindingsPanelState();
}

class _FilamentFindingsPanelState extends State<FilamentFindingsPanel> {
  final Map<String, FlowAnalysisResult> _results = {};
  final Map<String, FlowAnalysisResult> _rawResults = {};
  final FlowSseLattice _lattice = FlowSseLattice();
  int _totalFiles = 0;
  int _scannedFiles = 0;
  bool _done = false;
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
    final probe = await runGitProbe(repoPath, ['ls-files']);
    if (!mounted || _gen != gen) return;
    if (probe.exitCode != 0) {
      setState(() => _done = true);
      return;
    }

    final allPaths = const LineSplitter()
        .convert(probe.stdout.toString())
        .where((l) => l.isNotEmpty)
        .where((f) => _codeExtensions.contains(p.extension(f).toLowerCase()))
        .toList();

    setState(() => _totalFiles = allPaths.length);

    const concurrency = 8;
    for (var i = 0; i < allPaths.length; i += concurrency) {
      if (!mounted || _gen != gen) return;
      final batch = allPaths.skip(i).take(concurrency).map((fp) async {
        try {
          final result = await analyzeFlowCached(p.join(repoPath, fp));
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

    if (!mounted || _gen != gen) return;

    // Second pass: filter through the calibrated lattice.
    final calibrated = <String, FlowAnalysisResult>{};
    for (final entry in _rawResults.entries) {
      final filtered = entry.value.filterBy(_lattice);
      if (filtered.findings.isNotEmpty) {
        calibrated[entry.key] = filtered;
      }
    }

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
    for (final entry in _results.values) {
      for (final f in entry.findings) {
        total++;
        if (f.certainty < 0.1) {
          crit++;
        } else if (f.certainty < 0.3) {
          warn++;
        } else {
          info++;
        }
      }
    }

    final buf = StringBuffer();
    buf.writeln('filament $total findings across ${_results.length} files '
        '[C=$crit W=$warn I=$info]');
    buf.writeln();

    for (final entry in sorted) {
      final path = entry.key;
      final result = entry.value;
      final gap = result.spectralGap;
      final findings = [...result.findings]
        ..sort((a, b) => a.certainty.compareTo(b.certainty));

      buf.writeln('── $path (${gap.toStringAsFixed(2)})');
      for (final f in findings) {
        final sev = f.certainty < 0.1
            ? 'C'
            : f.certainty < 0.3
                ? 'W'
                : 'I';
        final kind = switch (f.kind) {
          FlowBugKind.staleValue => 'stale',
          FlowBugKind.temporalShift => 'temporal',
          FlowBugKind.contextInversion => 'context',
        };
        final src = f.sourceText.length > 64
            ? '${f.sourceText.substring(0, 61)}...'
            : f.sourceText;
        buf.writeln(
            '  $sev L${f.sourceLine + 1} $kind '
            '[${f.certainty.toStringAsFixed(3)} p=${f.pathCount}] $src');
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
    for (final entry in _results.values) {
      for (final f in entry.findings) {
        totalFindings++;
        if (f.certainty < 0.1) {
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
                if (critCount > 0 || warnCount > 0 || infoCount > 0) ...[
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
                          (a, b) => a.certainty.compareTo(b.certainty));
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
      _ => t.textMuted.withValues(alpha: 0.6),
    };
    final kind = switch (finding.kind) {
      FlowBugKind.staleValue => 'stale value',
      FlowBugKind.temporalShift => 'temporal shift',
      FlowBugKind.contextInversion => 'context inversion',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            sev,
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
