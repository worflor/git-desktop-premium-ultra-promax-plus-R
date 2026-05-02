// User-configured external tools — the entries surfaced by the
// "Open with…" submenu on a project row. Each tool is a name + an
// argv recipe + a launch mode. The recipe substitutes `{path}` with
// the project's absolute path at fire time, and routes through
// either a fresh terminal session (interactive tools — `claude`,
// `python`, custom shells) or a detached process spawn (GUI
// launchers — `code`, `cursor`).
//
// Persistence lives in `AppSettingsSnapshot.externalTools`; the
// app-state ChangeNotifier wrapping it is `ExternalToolsState`.
//
// Security: argv-based dispatch. `executable` and `args` go to
// `Process.start` as a list, so spaces / quotes / metacharacters
// in either the args or the substituted `{path}` need no escaping
// — there is no shell parsing anywhere in the launch path.

import 'dart:math' as math;

/// How a tool should be launched. Drives the platform-specific path
/// in `system_paths.dart`.
enum ToolLaunchMode {
  /// Spawn a new terminal window, run the command in it. The terminal
  /// stays open after the command exits — good for interactive tools
  /// like `claude` (which start a REPL the user wants to keep typing
  /// into) or arbitrary shells.
  newTerminal,

  /// Spawn the process detached from the app, no terminal window.
  /// Good for GUI launchers (`code`, `cursor`, `subl`) that fork
  /// their own window — a console flash-in/flash-out from
  /// `newTerminal` mode would feel wrong for these.
  detached;

  /// Round-trip a string back to the enum, falling back when the
  /// stored value is corrupt or from a future schema. Mirrors the
  /// `_normalizeXxx` helpers in `settings_store.dart`.
  static ToolLaunchMode fromString(String? raw) {
    switch (raw) {
      case 'newTerminal':
        return ToolLaunchMode.newTerminal;
      case 'detached':
        return ToolLaunchMode.detached;
      default:
        return ToolLaunchMode.newTerminal;
    }
  }
}

/// A single external tool entry.
class ExternalTool {
  /// Stable id — survives label / executable edits so menu bindings
  /// and reorder operations don't lose the row's identity. Generated
  /// once at create time; never mutated.
  final String id;

  /// User-facing label shown in the context menu and the settings
  /// editor. Empty allowed during creation; the UI substitutes the
  /// executable as a placeholder if so.
  final String label;

  /// PATH-resolved program to invoke. e.g. `claude`, `code`, `cursor`.
  /// Absolute paths also work but lock the config to a specific
  /// machine; we don't recommend them in the UI.
  final String executable;

  /// argv slots after the executable. `{path}` placeholders are
  /// substituted with the project's absolute path at launch time.
  /// One placeholder per arg slot keeps the substitution syntactic
  /// (no shell parsing); a path with spaces becomes one argument
  /// because it occupies one slot, not because of quoting.
  final List<String> args;

  /// How to launch — see [ToolLaunchMode] doc.
  final ToolLaunchMode mode;

  const ExternalTool({
    required this.id,
    required this.label,
    required this.executable,
    required this.args,
    required this.mode,
  });

  /// Display label with sensible fallback when the user hasn't set
  /// one yet. The executable is the most informative fallback (it's
  /// the verb the user actually invokes).
  String get displayLabel {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty) return trimmed;
    final exec = executable.trim();
    return exec.isEmpty ? 'tool' : exec;
  }

  /// Substitute `{path}` placeholders. Argv-level substitution: each
  /// arg slot is rewritten independently, so a path with spaces or
  /// metacharacters becomes one argument (because it occupies one
  /// slot) without any escaping.
  List<String> resolveArgs(String projectPath) {
    return [
      for (final a in args) a.replaceAll('{path}', projectPath),
    ];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'executable': executable,
        'args': args,
        'mode': mode.name,
      };

  /// Parse a single tool from JSON. Tolerates missing fields the same
  /// way [AppSettingsSnapshot.fromJson] does — drop garbage, fall
  /// back to safe defaults. Returns null when the entry is too
  /// malformed to be useful (no executable).
  static ExternalTool? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final label = raw['label'];
    final executable = raw['executable'];
    final argsRaw = raw['args'];
    final mode = raw['mode'];
    if (executable is! String || executable.trim().isEmpty) return null;
    return ExternalTool(
      id: id is String && id.trim().isNotEmpty ? id : _newId(),
      label: label is String ? label : '',
      executable: executable.trim(),
      args: argsRaw is List
          ? [for (final a in argsRaw) if (a is String) a]
          : const [],
      mode: ToolLaunchMode.fromString(mode is String ? mode : null),
    );
  }

  ExternalTool copyWith({
    String? label,
    String? executable,
    List<String>? args,
    ToolLaunchMode? mode,
  }) {
    return ExternalTool(
      id: id,
      label: label ?? this.label,
      executable: executable ?? this.executable,
      args: args ?? this.args,
      mode: mode ?? this.mode,
    );
  }

  /// Generate a fresh stable id. Not cryptographically random — just
  /// needs to avoid collisions in a list of < ~100 tools per user.
  /// Time-prefixed + random suffix keeps add-order partially encoded.
  static String _newId() {
    final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final r = math.Random();
    final suffix =
        List.generate(4, (_) => r.nextInt(36).toRadixString(36)).join();
    return 'tool_${ts}_$suffix';
  }

  /// Public constructor for newly-created tools where the caller
  /// doesn't already have an id. Convenience shim around the
  /// const constructor.
  factory ExternalTool.create({
    required String label,
    required String executable,
    List<String> args = const ['{path}'],
    ToolLaunchMode mode = ToolLaunchMode.newTerminal,
  }) {
    return ExternalTool(
      id: _newId(),
      label: label,
      executable: executable,
      args: args,
      mode: mode,
    );
  }
}

/// Metadata for a preset offered as a one-click "Add" chip in the
/// settings UI. The label is what the chip says; the executable is
/// what we probe on PATH so we only render chips for tools the user
/// has installed; the factory constructs the seeded tool entry.
///
/// Curated to cover the most-common cases without becoming a
/// sprawling registry. Order in [ExternalToolPresets.all] is the
/// display order in the chip row, grouped: AI assistants → editors
/// → git/dev TUIs → browser/web — so the user's eye lands on the
/// register they want first.
/// Category for grouping presets on the settings shelf.
enum ExternalToolCategory { ai, editors, explore, gitOps }

class ExternalToolPreset {
  final String label;
  final String executable;
  final ExternalToolCategory category;
  final ExternalTool Function() build;

  const ExternalToolPreset({
    required this.label,
    required this.executable,
    required this.category,
    required this.build,
  });
}

/// Built-in presets surfaced in the settings UI as one-click adds.
/// Each entry is the *starting point* for a tool — the user can
/// edit any field after adding it.
class ExternalToolPresets {
  ExternalToolPresets._();

  /// Anthropic's Claude CLI — opens a Claude Code session at the
  /// project path. Interactive REPL → newTerminal mode keeps the
  /// console open.
  static ExternalTool claude() => ExternalTool.create(
        label: 'Claude',
        executable: 'claude',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Aider — AI pair programmer. Operates on the cwd, so we don't
  /// pass `{path}`; the working directory set by the launcher is
  /// enough.
  static ExternalTool aider() => ExternalTool.create(
        label: 'Aider',
        executable: 'aider',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// VS Code. The CLI launcher forks the editor window and exits,
  /// so detached mode is correct (no terminal flash).
  static ExternalTool vscode() => ExternalTool.create(
        label: 'VS Code',
        executable: 'code',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Cursor. Same launch shape as VS Code.
  static ExternalTool cursor() => ExternalTool.create(
        label: 'Cursor',
        executable: 'cursor',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Zed editor. Same launch shape as VS Code / Cursor — the CLI
  /// forks the GUI window.
  static ExternalTool zed() => ExternalTool.create(
        label: 'Zed',
        executable: 'zed',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Sublime Text. The CLI is `subl`; same detached pattern.
  static ExternalTool sublime() => ExternalTool.create(
        label: 'Sublime',
        executable: 'subl',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// LazyGit — TUI git interface.
  static ExternalTool lazygit() => ExternalTool.create(
        label: 'LazyGit',
        executable: 'lazygit',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Additional AI CLI tools ──────────────────────────────────

  /// OpenAI Codex CLI agent.
  static ExternalTool codex() => ExternalTool.create(
        label: 'Codex',
        executable: 'codex',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Google Gemini CLI.
  static ExternalTool gemini() => ExternalTool.create(
        label: 'Gemini',
        executable: 'gemini',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// OpenCode — open-source AI coding agent.
  static ExternalTool opencode() => ExternalTool.create(
        label: 'OpenCode',
        executable: 'opencode',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Additional editors ───────────────────────────────────────

  /// Windsurf (Codeium) — AI-first editor.
  static ExternalTool windsurf() => ExternalTool.create(
        label: 'Windsurf',
        executable: 'windsurf',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// JetBrains IntelliJ IDEA.
  static ExternalTool idea() => ExternalTool.create(
        label: 'IntelliJ',
        executable: 'idea',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Neovim — terminal editor.
  static ExternalTool nvim() => ExternalTool.create(
        label: 'Neovim',
        executable: 'nvim',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Helix — modern terminal editor.
  static ExternalTool helix() => ExternalTool.create(
        label: 'Helix',
        executable: 'hx',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Terminals / utilities ────────────────────────────────────

  /// Windows Terminal — opens a shell at the project path.
  static ExternalTool windowsTerminal() => ExternalTool.create(
        label: 'Terminal',
        executable: 'wt',
        args: const ['-d', '{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// GitHub CLI — opens the repo in the browser.
  static ExternalTool ghBrowse() => ExternalTool.create(
        label: 'GitHub',
        executable: 'gh',
        args: const ['browse'],
        mode: ToolLaunchMode.detached,
      );

  // ── Git power-user TUIs ───────────────────────────────────────

  /// Tig — TUI git log/blame/diff viewer. Read-focused.
  static ExternalTool tig() => ExternalTool.create(
        label: 'Tig',
        executable: 'tig',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// GitUI — modern Rust TUI git interface.
  static ExternalTool gitui() => ExternalTool.create(
        label: 'GitUI',
        executable: 'gitui',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Analysis / workflow ──────────────────────────────────────

  /// Tokei — lines of code / language breakdown.
  static ExternalTool tokei() => ExternalTool.create(
        label: 'Tokei',
        executable: 'tokei',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Just — modern command runner. Shows the justfile's recipes.
  static ExternalTool just() => ExternalTool.create(
        label: 'Just',
        executable: 'just',
        args: const ['--list'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Docker Compose — spin up the project's containers.
  static ExternalTool docker() => ExternalTool.create(
        label: 'Docker',
        executable: 'docker',
        args: const ['compose', 'up'],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── File exploration / analysis ───────────────────────────────

  /// Broot — smart tree explorer with fuzzy search.
  static ExternalTool broot() => ExternalTool.create(
        label: 'Broot',
        executable: 'broot',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Yazi — blazing fast TUI file manager.
  static ExternalTool yazi() => ExternalTool.create(
        label: 'Yazi',
        executable: 'yazi',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Glow — render README.md beautifully in terminal.
  static ExternalTool glow() => ExternalTool.create(
        label: 'Glow',
        executable: 'glow',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Dust — disk usage tree visualizer.
  static ExternalTool dust() => ExternalTool.create(
        label: 'Dust',
        executable: 'dust',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── CI / build / orchestration ──────────────────────────────

  /// Act — run GitHub Actions locally.
  static ExternalTool act() => ExternalTool.create(
        label: 'Act',
        executable: 'act',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Make — classic build tool.
  static ExternalTool make() => ExternalTool.create(
        label: 'Make',
        executable: 'make',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Task — Go Task runner (modern make alternative).
  static ExternalTool taskRunner() => ExternalTool.create(
        label: 'Task',
        executable: 'task',
        args: const ['--list'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// K9s — Kubernetes TUI.
  static ExternalTool k9s() => ExternalTool.create(
        label: 'K9s',
        executable: 'k9s',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Eldritch git operations ───────────────────────────────────
  // Raw git commands that reveal hidden repo knowledge or do
  // powerful single-command operations. Executable is `git` itself;
  // args are the arcane subcommand + flags.

  /// Who built this? Contributor leaderboard by commit count.
  static ExternalTool contributors() => ExternalTool.create(
        label: 'Contributors',
        executable: 'git',
        args: const ['shortlog', '-sn', '--all'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Visual branch topology — THE wizard view of repo structure.
  static ExternalTool branchMap() => ExternalTool.create(
        label: 'Branch Map',
        executable: 'git',
        args: const ['log', '--oneline', '--graph', '--all', '--decorate', '-40'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// What happened recently? Last week's work in one glance.
  static ExternalTool thisWeek() => ExternalTool.create(
        label: 'This Week',
        executable: 'git',
        args: const ['log', '--since=1 week ago', '--oneline', '--all'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Is this repo healthy? Full integrity check.
  static ExternalTool integrity() => ExternalTool.create(
        label: 'Integrity',
        executable: 'git',
        args: const ['fsck', '--full'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Show me everything that ever happened. Recovery archaeology.
  static ExternalTool reflog() => ExternalTool.create(
        label: 'Reflog',
        executable: 'git',
        args: const ['reflog', '--all', '--date=relative'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// What was deleted? Ghost files — everything that was removed.
  static ExternalTool ghosts() => ExternalTool.create(
        label: 'Ghosts',
        executable: 'git',
        args: const ['log', '--all', '--diff-filter=D', '--name-only', '--pretty=format:--- %h %s'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Nuclear cleanup — aggressive garbage collection + prune.
  static ExternalTool cleanup() => ExternalTool.create(
        label: 'Cleanup',
        executable: 'git',
        args: const ['gc', '--aggressive', '--prune=now'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Empty preset — what "Add custom tool" produces.
  static ExternalTool blank() => ExternalTool.create(
        label: '',
        executable: '',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// All curated detectable presets, in display order.
  static List<ExternalToolPreset> get all => [
        // AI assistants
        ExternalToolPreset(label: '+ Claude', executable: 'claude', category: ExternalToolCategory.ai, build: claude),
        ExternalToolPreset(label: '+ Codex', executable: 'codex', category: ExternalToolCategory.ai, build: codex),
        ExternalToolPreset(label: '+ Gemini', executable: 'gemini', category: ExternalToolCategory.ai, build: gemini),
        ExternalToolPreset(label: '+ OpenCode', executable: 'opencode', category: ExternalToolCategory.ai, build: opencode),
        ExternalToolPreset(label: '+ Aider', executable: 'aider', category: ExternalToolCategory.ai, build: aider),
        // Editors
        ExternalToolPreset(label: '+ VS Code', executable: 'code', category: ExternalToolCategory.editors, build: vscode),
        ExternalToolPreset(label: '+ Cursor', executable: 'cursor', category: ExternalToolCategory.editors, build: cursor),
        ExternalToolPreset(label: '+ Windsurf', executable: 'windsurf', category: ExternalToolCategory.editors, build: windsurf),
        ExternalToolPreset(label: '+ Zed', executable: 'zed', category: ExternalToolCategory.editors, build: zed),
        ExternalToolPreset(label: '+ IntelliJ', executable: 'idea', category: ExternalToolCategory.editors, build: idea),
        ExternalToolPreset(label: '+ Sublime', executable: 'subl', category: ExternalToolCategory.editors, build: sublime),
        ExternalToolPreset(label: '+ Neovim', executable: 'nvim', category: ExternalToolCategory.editors, build: nvim),
        ExternalToolPreset(label: '+ Helix', executable: 'hx', category: ExternalToolCategory.editors, build: helix),
        // Explore — file browsers, analysis, git TUIs, terminals
        ExternalToolPreset(label: '+ LazyGit', executable: 'lazygit', category: ExternalToolCategory.explore, build: lazygit),
        ExternalToolPreset(label: '+ Tig', executable: 'tig', category: ExternalToolCategory.explore, build: tig),
        ExternalToolPreset(label: '+ GitUI', executable: 'gitui', category: ExternalToolCategory.explore, build: gitui),
        ExternalToolPreset(label: '+ Broot', executable: 'broot', category: ExternalToolCategory.explore, build: broot),
        ExternalToolPreset(label: '+ Yazi', executable: 'yazi', category: ExternalToolCategory.explore, build: yazi),
        ExternalToolPreset(label: '+ Glow', executable: 'glow', category: ExternalToolCategory.explore, build: glow),
        ExternalToolPreset(label: '+ Dust', executable: 'dust', category: ExternalToolCategory.explore, build: dust),
        ExternalToolPreset(label: '+ Tokei', executable: 'tokei', category: ExternalToolCategory.explore, build: tokei),
        ExternalToolPreset(label: '+ Terminal', executable: 'wt', category: ExternalToolCategory.explore, build: windowsTerminal),
        ExternalToolPreset(label: '+ GitHub', executable: 'gh', category: ExternalToolCategory.explore, build: ghBrowse),
        // CI / build / orchestration
        ExternalToolPreset(label: '+ Just', executable: 'just', category: ExternalToolCategory.explore, build: just),
        ExternalToolPreset(label: '+ Task', executable: 'task', category: ExternalToolCategory.explore, build: taskRunner),
        ExternalToolPreset(label: '+ Make', executable: 'make', category: ExternalToolCategory.explore, build: make),
        ExternalToolPreset(label: '+ Act', executable: 'act', category: ExternalToolCategory.explore, build: act),
        ExternalToolPreset(label: '+ Docker', executable: 'docker', category: ExternalToolCategory.explore, build: docker),
        ExternalToolPreset(label: '+ K9s', executable: 'k9s', category: ExternalToolCategory.explore, build: k9s),
        // Git operations
        ExternalToolPreset(label: '+ Contributors', executable: 'git', category: ExternalToolCategory.gitOps, build: contributors),
        ExternalToolPreset(label: '+ Branch Map', executable: 'git', category: ExternalToolCategory.gitOps, build: branchMap),
        ExternalToolPreset(label: '+ This Week', executable: 'git', category: ExternalToolCategory.gitOps, build: thisWeek),
        ExternalToolPreset(label: '+ Integrity', executable: 'git', category: ExternalToolCategory.gitOps, build: integrity),
        ExternalToolPreset(label: '+ Reflog', executable: 'git', category: ExternalToolCategory.gitOps, build: reflog),
        ExternalToolPreset(label: '+ Ghosts', executable: 'git', category: ExternalToolCategory.gitOps, build: ghosts),
        ExternalToolPreset(label: '+ Cleanup', executable: 'git', category: ExternalToolCategory.gitOps, build: cleanup),
      ];

  /// All executable names worth probing on PATH — derived from
  /// [all]. The detection backend uses this as its candidate set.
  static List<String> get detectableExecutables =>
      [for (final p in all) p.executable];
}
