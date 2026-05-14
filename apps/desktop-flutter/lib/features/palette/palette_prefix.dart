import '../../app/ai_activity_state.dart';
import '../../app/external_tools_state.dart';
import '../../backend/external_tools.dart';
import '../../backend/logos_git.dart';
import '../../backend/system_paths.dart';
import 'palette_entry.dart';
import 'palette_registry.dart';

class PrefixContext {
  final String? repoPath;
  final List<String> recentPaths;
  final PaletteCallbacks? callbacks;
  final LogosGit? engine;
  final ExternalToolsState? tools;
  final AiActivityState? aiActivity;

  const PrefixContext({
    this.repoPath,
    this.recentPaths = const [],
    this.callbacks,
    this.engine,
    this.tools,
    this.aiActivity,
  });
}

abstract class PalettePrefix {
  String get trigger;
  String get hint;

  bool matches(String query) =>
      query.toLowerCase().startsWith(trigger);

  String extractBody(String query) =>
      query.substring(trigger.length).trim();

  List<PaletteEntry> buildEntries(String body, PrefixContext ctx);
}

// ── ask: ────────────────────────────────────────────────────────────

class AskPrefix extends PalettePrefix {
  @override
  String get trigger => 'ask:';
  @override
  String get hint => 'ask: [question]';

  @override
  List<PaletteEntry> buildEntries(String body, PrefixContext ctx) {
    if (body.isEmpty || ctx.callbacks == null || ctx.aiActivity == null) {
      return [];
    }
    final ai = ctx.aiActivity!;
    final cb = ctx.callbacks!;
    final active = ctx.repoPath;

    final repos = <String>[];
    if (active != null) repos.add(active);
    for (final p in ctx.recentPaths) {
      if (p != active) repos.add(p);
    }

    return repos.map((rp) {
      final name = rp.split('/').last.split('\\').last;
      return PaletteEntry(
        id: 'prefix.ask.$rp',
        label: 'Ask $name: $body',
        category: PaletteCategory.action,
        actionType: PaletteActionType.execute,
        chipLabel: 'AI',
        chipTone: ChipTone.chromatic1,
        tags: rp != active ? const {EntryTag.repoChild} : const {},
        onExecute: () {
          if (rp != active) cb.onRepoSwitch(rp);
          ai.requestDebugWithQuery(rp, body);
          cb.onModeChanged(0);
        },
      );
    }).toList();
  }
}

// ── near: ───────────────────────────────────────────────────────────

class NearPrefix extends PalettePrefix {
  @override
  String get trigger => 'near:';
  @override
  String get hint => 'near: [file]';

  @override
  List<PaletteEntry> buildEntries(String body, PrefixContext ctx) {
    if (body.isEmpty || ctx.engine == null) return [];
    final engine = ctx.engine!;

    final seed = _resolveFile(body, engine);
    if (seed == null) return [];

    final scores = engine.relatedTo(seed, limit: 12);
    return scores.map((s) {
      final name = s.path.split('/').last;
      return PaletteEntry(
        id: 'prefix.near.${s.path}',
        label: name,
        subtitle: '${s.path} · φ=${s.phi.toStringAsFixed(3)}',
        category: PaletteCategory.file,
        actionType: PaletteActionType.execute,
        chipLabel: 'NEAR',
        chipTone: ChipTone.chromatic1,
        refPath: s.path,
      );
    }).toList();
  }

  String? _resolveFile(String query, LogosGit engine) {
    final q = query.toLowerCase();
    for (final path in engine.nodePaths) {
      if (path.toLowerCase().contains(q)) return path;
    }
    return null;
  }
}

// ── who: ────────────────────────────────────────────────────────────

class WhoPrefix extends PalettePrefix {
  @override
  String get trigger => 'who:';
  @override
  String get hint => 'who: [file]';

  @override
  List<PaletteEntry> buildEntries(String body, PrefixContext ctx) {
    if (body.isEmpty || ctx.engine == null) return [];
    final engine = ctx.engine!;
    final q = body.toLowerCase();

    final entries = <PaletteEntry>[];
    for (final path in engine.nodePaths) {
      if (!path.toLowerCase().contains(q)) continue;
      final reviewers = engine.stats.reviewersByPath[path];
      final touches = engine.stats.touches[path] ?? 0;
      final name = path.split('/').last;

      if (reviewers != null && reviewers.isNotEmpty) {
        entries.add(PaletteEntry(
          id: 'prefix.who.reviewers.$path',
          label: '$name — ${reviewers.join(', ')}',
          subtitle: '$path · ${reviewers.length} reviewers · $touches touches',
          category: PaletteCategory.file,
          actionType: PaletteActionType.execute,
          chipLabel: 'WHO',
          chipTone: ChipTone.chromatic2,
          refPath: path,
        ));
      } else if (touches > 0) {
        entries.add(PaletteEntry(
          id: 'prefix.who.touches.$path',
          label: '$name — $touches touches',
          subtitle: '$path · no reviewers recorded',
          category: PaletteCategory.file,
          actionType: PaletteActionType.execute,
          chipLabel: 'WHO',
          chipTone: ChipTone.muted,
          refPath: path,
        ));
      }
      if (entries.length >= 10) break;
    }
    return entries;
  }
}

// ── log: ────────────────────────────────────────────────────────────

class LogPrefix extends PalettePrefix {
  @override
  String get trigger => 'log:';
  @override
  String get hint => 'log: [message]';

  @override
  List<PaletteEntry> buildEntries(String body, PrefixContext ctx) {
    // Returns empty — the actual search is async.
    // The prefix signals to PaletteState that ONLY commit search
    // should run, not branches/files/stashes/tags.
    return [];
  }
}

// ── run: ────────────────────────────────────────────────────────────

class RunPrefix extends PalettePrefix {
  @override
  String get trigger => 'run:';
  @override
  String get hint => 'run: [tool]';

  @override
  List<PaletteEntry> buildEntries(String body, PrefixContext ctx) {
    if (ctx.tools == null ||
        !ctx.tools!.isLoaded ||
        ctx.repoPath == null) return [];
    final q = body.toLowerCase();
    final repoPath = ctx.repoPath!;

    return ctx.tools!.tools
        .where((t) =>
            t.label.toLowerCase().contains(q) ||
            t.executable.toLowerCase().contains(q) ||
            q.isEmpty)
        .take(10)
        .map((tool) => PaletteEntry(
              id: 'prefix.run.${tool.id}',
              label: tool.displayLabel,
              subtitle: '${tool.executable} ${tool.args.join(' ')}',
              category: PaletteCategory.action,
              actionType: PaletteActionType.execute,
              chipLabel: tool.mode == ToolLaunchMode.newTerminal
                  ? 'TERM'
                  : 'GUI',
              onExecute: () async {
                final args = tool.resolveArgs(repoPath);
                try {
                  switch (tool.mode) {
                    case ToolLaunchMode.newTerminal:
                      await runInTerminal(
                        executable: tool.executable,
                        args: args,
                        workingDirectory: repoPath,
                      );
                    case ToolLaunchMode.detached:
                      await runDetached(
                        executable: tool.executable,
                        args: args,
                        workingDirectory: repoPath,
                      );
                  }
                } catch (_) {}
              },
            ))
        .toList();
  }
}

List<PalettePrefix> buildPrefixes({
  required AiActivityState aiActivity,
  required ExternalToolsState tools,
  required LogosGit? engine,
}) {
  return [
    AskPrefix(),
    NearPrefix(),
    WhoPrefix(),
    LogPrefix(),
    RunPrefix(),
  ];
}
