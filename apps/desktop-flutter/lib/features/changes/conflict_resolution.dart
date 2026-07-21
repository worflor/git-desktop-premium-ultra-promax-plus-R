// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/ai_settings_state.dart';
import '../../app/repository_state.dart';
import '../../backend/ai.dart';
import '../../backend/git.dart';
import '../../i18n/gen/strings.g.dart';
import '../../ui/control_chrome.dart';
import '../../ui/design_primitives.dart';
import '../../ui/material_surface.dart';
import '../../ui/tokens.dart';
import '../branches/branches_page.dart' show showPatchPreviewDialog;
import '../diff/diff_models.dart' show parseUnifiedDiff;

// ---------------------------------------------------------------------------
// AI-assisted conflict resolution — shared by the Changes-page strip and the
// unified conflict window so "resolve with AI" means the same thing
// everywhere: read the conflicted files, ask the model for ONE unified diff
// that removes every marker, and route the result through the same
// patch-preview window imported patches use. Non-mutating until the user
// applies in that preview.
// ---------------------------------------------------------------------------

Future<void> resolveConflictsWithAi(
  BuildContext context,
  String repoPath,
  String categoryId,
  List<String> conflictedPaths,
) async {
  if (conflictedPaths.isEmpty) return;
  final aiSettings = context.read<AiSettingsState>();
  final modelValue = aiSettings.modelSelections[categoryId] ?? '';
  if (modelValue.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.t.changes.conflictResolution.noModelConfigured(
            category:
                aiSettings.labelForCategory(categoryId, categoryId)))));
    return;
  }

  final snapshots = <({String path, String content})>[];
  var skippedSensitive = 0;
  for (final p in conflictedPaths) {
    // Never send credentials-shaped paths to a provider.
    if (isSensitivePath(p)) {
      skippedSensitive++;
      continue;
    }
    try {
      final abs = (p.startsWith('/') || p.contains(':'))
          ? p
          : '$repoPath${Platform.pathSeparator}$p';
      final text = await File(abs).readAsString();
      snapshots.add((path: p, content: _extractConflictExcerpts(text)));
    } catch (_) {}
  }
  if (snapshots.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(skippedSensitive > 0
            ? context.t.changes.conflictResolution
                .sensitiveFilesSkipped(n: skippedSensitive)
            : context.t.changes.conflictResolution.couldNotReadFiles)));
    return;
  }

  final prompt = _buildMergeResolutionPrompt(snapshots);
  final secretHit = detectLikelySecretInPrompt(prompt);
  if (secretHit != null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.t.changes.conflictResolution
            .blockedSecret(secret: secretHit))));
    return;
  }

  final r = await generatePatch(
    repositoryPath: repoPath,
    modelValue: modelValue,
    prompt: prompt,
    commandLabelPrefix: 'ai.merge_resolve',
  );
  if (!context.mounted) return;
  if (!r.ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(context.t.changes.conflictResolution
            .resolutionFailed(error: '${r.error}'))));
    return;
  }

  final resolvedLines = parseUnifiedDiff(r.data!.patch);
  final resolvedPaths = <String>{
    for (final l in resolvedLines)
      if (l.filePath != null) l.filePath!,
  };
  final expectedPaths = snapshots.map((s) => s.path).toSet();
  final intersect = expectedPaths.intersection(resolvedPaths);
  await showPatchPreviewDialog(
    context,
    repoPath: repoPath,
    rawPatch: r.data!.patch,
    sourceLabel: context.t.changes.conflictResolution.mergeResolutionLabel(
        resolved: intersect.length,
        total: expectedPaths.length,
        category: aiSettings.labelForCategory(categoryId, categoryId)),
    expectedPaths: expectedPaths,
    onApplied: () async {
      // Only stage the files the patch ACTUALLY touched — any skipped UU
      // file must stay UU so the user resolves it by hand.
      if (intersect.isNotEmpty) {
        await stagePaths(repoPath, intersect.toList());
      }
      if (context.mounted) {
        await context.read<RepositoryState>().refreshStatus();
      }
    },
  );
}

/// Default AI category for resolution: 'fast' when configured (most conflicts
/// are mechanical), else the first category that has a model. Empty when none.
String defaultResolveCategory(AiSettingsState ai) {
  if ((ai.modelSelections['fast'] ?? '').isNotEmpty) return 'fast';
  return ai.modelSelections.entries
      .firstWhere((e) => e.value.isNotEmpty, orElse: () => const MapEntry('', ''))
      .key;
}

String _buildMergeResolutionPrompt(
    List<({String path, String content})> files) {
  final buf = StringBuffer();
  buf.writeln(
      'You are resolving git merge conflicts in a working tree. For each file');
  buf.writeln(
      'below, the text contains unresolved conflict markers (<<<<<<<, =======, >>>>>>>).');
  buf.writeln();
  buf.writeln('Rules:');
  buf.writeln(
      '  1. Produce ONE unified diff that applies with `git apply` over the current tree.');
  buf.writeln(
      '  2. Every conflict marker must be removed — no <<<<<<<, =======, or >>>>>>> lines in the output.');
  buf.writeln(
      '  3. Preserve the MEANING of both sides. Rename/callsite changes on one side should propagate to the other side\'s callsites if both sides edit the same symbol.');
  buf.writeln(
      '  4. Do NOT introduce new functionality the conflict didn\'t already introduce.');
  buf.writeln(
      '  5. Output format: unified diff only. No code fences, no prose, no explanations.');
  buf.writeln();
  buf.writeln(
      'Files (shown as current conflict excerpts with surrounding context, not full files):');
  buf.writeln();
  for (final f in files) {
    buf.writeln('--- file: ${f.path} ---');
    buf.writeln(f.content);
    buf.writeln('--- end: ${f.path} ---');
    buf.writeln();
  }
  buf.writeln(
      'Output the unified diff that resolves every conflict across all files above.');
  return buf.toString();
}

String _extractConflictExcerpts(String content) {
  final normalized = content.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  final ranges = <({int start, int end})>[];
  const contextLines = 28;
  int? conflictStart;

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.startsWith('<<<<<<< ')) {
      conflictStart ??= i;
      continue;
    }
    if (conflictStart != null && line.startsWith('>>>>>>> ')) {
      ranges.add((
        start: math.max(0, conflictStart - contextLines),
        end: math.min(lines.length, i + contextLines + 1),
      ));
      conflictStart = null;
    }
  }
  if (conflictStart != null) {
    ranges.add((start: math.max(0, conflictStart - contextLines), end: lines.length));
  }
  if (ranges.isEmpty) return normalized;

  ranges.sort((a, b) => a.start.compareTo(b.start));
  final merged = <({int start, int end})>[];
  for (final range in ranges) {
    if (merged.isEmpty || range.start > merged.last.end) {
      merged.add(range);
      continue;
    }
    final last = merged.removeLast();
    merged.add((start: last.start, end: math.max(last.end, range.end)));
  }

  final buf = StringBuffer();
  var cursor = 0;
  for (final range in merged) {
    if (range.start > cursor) {
      buf.writeln('... omitted lines ${cursor + 1}-${range.start} ...');
    }
    buf.writeln('@@ conflict excerpt lines ${range.start + 1}-${range.end} @@');
    buf.writeln(lines.sublist(range.start, range.end).join('\n'));
    cursor = range.end;
  }
  if (cursor < lines.length) {
    buf.writeln('... omitted lines ${cursor + 1}-${lines.length} ...');
  }
  return buf.toString().trim();
}

// ---------------------------------------------------------------------------
// The unified conflict window — the intermediate surface every conflict
// lands in. Mirrors the patch-preview's role: tell the user, then offer the
// full suite (AI resolve / 3-way merge editor / defer) instead of marching
// them straight into the editor.
// ---------------------------------------------------------------------------

enum ConflictAction { ai, manual, defer }

class ConflictChoice {
  final ConflictAction action;

  /// The AI model category the user picked (only for [ConflictAction.ai]).
  final String? aiCategory;
  const ConflictChoice(this.action, {this.aiCategory});
}

/// Shows the conflict window. Returns the user's choice, or null if dismissed
/// (treated the same as [ConflictAction.defer] by callers). [opLabel] names
/// the operation that hit the conflict ("pull", "merge", "cherry-pick", …).
/// When [canDefer] is false (e.g. a dirty pull whose state isn't persisted),
/// the third action is "discard" rather than "later".
Future<ConflictChoice?> showConflictWindow(
  BuildContext context, {
  required String opLabel,
  required List<String> paths,
  required int blockCount,
  bool canDefer = true,
}) {
  return showDialog<ConflictChoice>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => _ConflictWindow(
      opLabel: opLabel,
      paths: paths,
      blockCount: blockCount,
      canDefer: canDefer,
    ),
  );
}

class _ConflictWindow extends StatelessWidget {
  final String opLabel;
  final List<String> paths;
  final int blockCount;
  final bool canDefer;

  const _ConflictWindow({
    required this.opLabel,
    required this.paths,
    required this.blockCount,
    required this.canDefer,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ai = context.watch<AiSettingsState>();
    final cat = defaultResolveCategory(ai);
    final geo = context.surfaceShader.geometry;
    final fileCount = paths.length;
    final alt = ai.modelSelections.entries
        .where((e) => e.value.isNotEmpty && e.key != cat)
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: MaterialSurface(
          tone: AppMaterialTone.surface1,
          elevated: true,
          radius: geo.cardRadius,
          borderColor: t.chromeBorder,
          borderAlpha: 0.2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(children: [
                  Text('◇',
                      style: TextStyle(
                        color: t.stateConflicted,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFonts.mono,
                        fontFamilyFallback: AppFonts.monoFallback,
                      )),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.t.changes.conflictResolution.conflictSummary(
                        op: opLabel,
                        conflicts: context.t.changes.conflictResolution
                            .conflictCount(n: blockCount),
                        files: context.t.common.fileCount(n: fileCount),
                      ),
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ),
              // File list
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.bg0.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(geo.badgeRadius),
                  border: Border.all(color: t.chromeBorder.withValues(alpha: 0.1)),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final p in paths)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            p,
                            style: TextStyle(
                              color: t.textNormal,
                              fontSize: 11.5,
                              fontFamily: AppFonts.mono,
                              fontFamilyFallback: AppFonts.monoFallback,
                              height: 1.4,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Actions
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Row(children: [
                  _WindowButton(
                    label: context.t.changes.conflictResolution.mergeEditorButton,
                    accent: t.accentBright,
                    onTap: () => Navigator.of(context)
                        .pop(const ConflictChoice(ConflictAction.manual)),
                  ),
                  const SizedBox(width: 6),
                  if (cat.isNotEmpty)
                    _AiResolveButton(
                      defaultCategory: cat,
                      alternates: alt,
                      labelFor: (c) => ai.labelForCategory(c, c),
                      onPick: (c) => Navigator.of(context).pop(
                          ConflictChoice(ConflictAction.ai, aiCategory: c)),
                    )
                  else
                    Text(context.t.changes.conflictResolution.noAiModel,
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10.5,
                          fontStyle: FontStyle.italic,
                          fontFamily: AppFonts.mono,
                          fontFamilyFallback: AppFonts.monoFallback,
                        )),
                  const Spacer(),
                  // Same slot, but the two variants must not read alike: 'later'
                  // is harmless (defer the resolution) while 'discard' throws
                  // the merge away. Give discard the delete tier so its danger
                  // is legible; keep later muted.
                  _WindowButton(
                    label: canDefer
                        ? context.t.changes.conflictResolution.later
                        : context.t.changes.conflictResolution.discard,
                    accent: canDefer ? t.textMuted : t.stateDeleted,
                    subdued: canDefer,
                    onTap: () => Navigator.of(context)
                        .pop(const ConflictChoice(ConflictAction.defer)),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WindowButton extends StatelessWidget {
  final String label;
  final Color accent;
  final bool subdued;
  final VoidCallback onTap;
  const _WindowButton({
    required this.label,
    required this.accent,
    required this.onTap,
    this.subdued = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return ChromeButton(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      borderRadius: BorderRadius.circular(context.surfaceShader.geometry.pillRadius),
      chromeBuilder: ({required hovered, required pressed}) => ghostButtonChrome(
        t,
        hovered: hovered,
        pressed: pressed,
        enabled: true,
        baseBorderColor:
            accent.withValues(alpha: subdued ? 0.18 : 0.4),
      ),
      child: Text(label,
          style: TextStyle(
            color: subdued ? t.textMuted : accent,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFamily: AppFonts.mono,
            fontFamilyFallback: AppFonts.monoFallback,
          )),
    );
  }
}

/// Primary "resolve with AI" button + a chevron menu for alternate model
/// categories (the same fast/quality split the Changes-page strip offers).
class _AiResolveButton extends StatelessWidget {
  final String defaultCategory;
  final List<MapEntry<String, String>> alternates;
  final String Function(String) labelFor;
  final ValueChanged<String> onPick;
  const _AiResolveButton({
    required this.defaultCategory,
    required this.alternates,
    required this.labelFor,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _WindowButton(
        label: context.t.changes.conflictResolution.resolveWithAi,
        accent: t.stateConflicted,
        onTap: () => onPick(defaultCategory),
      ),
      if (alternates.isNotEmpty)
        PopupMenuButton<String>(
          tooltip: context.t.changes.conflictResolution.otherModel,
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          color: t.bg1,
          onSelected: onPick,
          itemBuilder: (_) => [
            for (final e in alternates)
              PopupMenuItem<String>(
                value: e.key,
                child: Text(
                    context.t.changes.conflictResolution
                        .withModel(model: labelFor(e.key)),
                    style: TextStyle(color: t.textNormal, fontSize: 12)),
              ),
          ],
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(Icons.expand_more,
                size: 16, color: t.stateConflicted.withValues(alpha: 0.7)),
          ),
        ),
    ]);
  }
}
