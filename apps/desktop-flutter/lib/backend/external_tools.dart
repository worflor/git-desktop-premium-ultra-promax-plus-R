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
enum ExternalToolCategory { ai, editors, explore, ops, gitOps }

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

  /// Amp — Sourcegraph AI coding agent.
  static ExternalTool amp() => ExternalTool.create(
        label: 'Amp',
        executable: 'amp',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Cline — AI coding agent (VS Code extension CLI).
  static ExternalTool cline() => ExternalTool.create(
        label: 'Cline',
        executable: 'cline',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// GitHub Copilot CLI.
  static ExternalTool copilot() => ExternalTool.create(
        label: 'Copilot',
        executable: 'github-copilot-cli',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Goose — Block's AI coding agent.
  static ExternalTool goose() => ExternalTool.create(
        label: 'Goose',
        executable: 'goose',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Amazon Q Developer CLI.
  static ExternalTool amazonQ() => ExternalTool.create(
        label: 'Amazon Q',
        executable: 'q',
        args: const ['chat'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Warp — AI-native terminal.
  static ExternalTool warp() => ExternalTool.create(
        label: 'Warp',
        executable: 'warp',
        args: const [],
        mode: ToolLaunchMode.detached,
      );

  /// Ollama — local LLM runner.
  static ExternalTool ollama() => ExternalTool.create(
        label: 'Ollama',
        executable: 'ollama',
        args: const ['run', 'llama3'],
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

  /// Emacs.
  static ExternalTool emacs() => ExternalTool.create(
        label: 'Emacs',
        executable: 'emacs',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Vim — terminal editor.
  static ExternalTool vim() => ExternalTool.create(
        label: 'Vim',
        executable: 'vim',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// JetBrains Fleet.
  static ExternalTool fleet() => ExternalTool.create(
        label: 'Fleet',
        executable: 'fleet',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Lapce — Rust-native editor.
  static ExternalTool lapce() => ExternalTool.create(
        label: 'Lapce',
        executable: 'lapce',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  // ── Git GUIs ────────────────────────────────────────────────

  /// GitHub Desktop.
  static ExternalTool githubDesktop() => ExternalTool.create(
        label: 'GitHub Desktop',
        executable: 'github',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// GitKraken.
  static ExternalTool gitkraken() => ExternalTool.create(
        label: 'GitKraken',
        executable: 'gitkraken',
        args: const ['-p', '{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Fork — git GUI.
  static ExternalTool fork() => ExternalTool.create(
        label: 'Fork',
        executable: 'fork',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Sourcetree.
  static ExternalTool sourcetree() => ExternalTool.create(
        label: 'Sourcetree',
        executable: 'stree',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  /// Tower — git GUI.
  static ExternalTool tower() => ExternalTool.create(
        label: 'Tower',
        executable: 'gittower',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
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

  /// lf — terminal file manager.
  static ExternalTool lf() => ExternalTool.create(
        label: 'lf',
        executable: 'lf',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// nnn — minimal TUI file manager.
  static ExternalTool nnn() => ExternalTool.create(
        label: 'nnn',
        executable: 'nnn',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Ranger — Python TUI file manager.
  static ExternalTool ranger() => ExternalTool.create(
        label: 'Ranger',
        executable: 'ranger',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Delta — beautiful git diffs in terminal.
  static ExternalTool delta() => ExternalTool.create(
        label: 'Delta',
        executable: 'delta',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Difftastic — structural diff tool.
  static ExternalTool difftastic() => ExternalTool.create(
        label: 'Difftastic',
        executable: 'difft',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Antigravity — the real one. Opens xkcd 353.
  static ExternalTool antigravity() => ExternalTool.create(
        label: 'Antigravity',
        executable: 'python',
        args: const ['-m', 'antigravity'],
        mode: ToolLaunchMode.detached,
      );

  /// Onefetch — git repo info card (languages, LOC, license).
  static ExternalTool onefetch() => ExternalTool.create(
        label: 'Onefetch',
        executable: 'onefetch',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// scc — fast SLOC counter with complexity estimates.
  static ExternalTool scc() => ExternalTool.create(
        label: 'scc',
        executable: 'scc',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Hyperfine — statistical command benchmarking.
  static ExternalTool hyperfine() => ExternalTool.create(
        label: 'Hyperfine',
        executable: 'hyperfine',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// ast-grep — structural code search/lint via AST patterns.
  static ExternalTool astGrep() => ExternalTool.create(
        label: 'ast-grep',
        executable: 'sg',
        args: const ['scan'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// serpl — TUI project-wide search and replace.
  static ExternalTool serpl() => ExternalTool.create(
        label: 'serpl',
        executable: 'serpl',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// D2 — text-to-diagram renderer.
  static ExternalTool d2() => ExternalTool.create(
        label: 'D2',
        executable: 'd2',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Dev environment / workflow ──────────────────────────────

  /// mise — unified dev tool version manager.
  static ExternalTool mise() => ExternalTool.create(
        label: 'mise',
        executable: 'mise',
        args: const ['install'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Watchexec — run commands on file change, respects .gitignore.
  static ExternalTool watchexec() => ExternalTool.create(
        label: 'Watchexec',
        executable: 'watchexec',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// LazyDocker — TUI for Docker containers/images/volumes.
  static ExternalTool lazydocker() => ExternalTool.create(
        label: 'LazyDocker',
        executable: 'lazydocker',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Zellij — modern terminal multiplexer.
  static ExternalTool zellij() => ExternalTool.create(
        label: 'Zellij',
        executable: 'zellij',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// git-cliff — changelog generator from conventional commits.
  static ExternalTool gitCliff() => ExternalTool.create(
        label: 'git-cliff',
        executable: 'git-cliff',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Jujutsu — next-gen VCS, works on existing .git repos.
  static ExternalTool jujutsu() => ExternalTool.create(
        label: 'Jujutsu',
        executable: 'jj',
        args: const ['status'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Posting — TUI API client with project-local request files.
  static ExternalTool posting() => ExternalTool.create(
        label: 'Posting',
        executable: 'posting',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// DevContainers CLI — build/run dev containers.
  static ExternalTool devcontainer() => ExternalTool.create(
        label: 'DevContainer',
        executable: 'devcontainer',
        args: const ['up', '--workspace-folder', '{path}'],
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

  /// Stern — Kubernetes log tailing.
  static ExternalTool stern() => ExternalTool.create(
        label: 'Stern',
        executable: 'stern',
        args: const ['.'],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── API / testing ──────────────────────────────────────────

  /// HTTPie — human-friendly HTTP client.
  static ExternalTool httpie() => ExternalTool.create(
        label: 'HTTPie',
        executable: 'http',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Hurl — run HTTP requests from .hurl files in the repo.
  static ExternalTool hurl() => ExternalTool.create(
        label: 'Hurl',
        executable: 'hurl',
        args: const ['--test', '.'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Bruno — API client (GUI, opens project collection).
  static ExternalTool bruno() => ExternalTool.create(
        label: 'Bruno',
        executable: 'bruno',
        args: const ['{path}'],
        mode: ToolLaunchMode.detached,
      );

  // ── Database ───────────────────────────────────────────────

  /// usql — universal SQL CLI (postgres, mysql, sqlite, etc).
  static ExternalTool usql() => ExternalTool.create(
        label: 'usql',
        executable: 'usql',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// pgcli — Postgres CLI with autocomplete.
  static ExternalTool pgcli() => ExternalTool.create(
        label: 'pgcli',
        executable: 'pgcli',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Security ───────────────────────────────────────────────

  /// Trivy — vulnerability scanner.
  static ExternalTool trivy() => ExternalTool.create(
        label: 'Trivy',
        executable: 'trivy',
        args: const ['fs', '{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Grype — container/filesystem vulnerability scanner.
  static ExternalTool grype() => ExternalTool.create(
        label: 'Grype',
        executable: 'grype',
        args: const ['dir:{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  // ── Infrastructure ─────────────────────────────────────────

  /// Terraform.
  static ExternalTool terraform() => ExternalTool.create(
        label: 'Terraform',
        executable: 'terraform',
        args: const ['plan'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Pulumi.
  static ExternalTool pulumi() => ExternalTool.create(
        label: 'Pulumi',
        executable: 'pulumi',
        args: const ['preview'],
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
        ExternalToolPreset(label: '+ Amp', executable: 'amp', category: ExternalToolCategory.ai, build: amp),
        ExternalToolPreset(label: '+ Cline', executable: 'cline', category: ExternalToolCategory.ai, build: cline),
        ExternalToolPreset(label: '+ Copilot', executable: 'github-copilot-cli', category: ExternalToolCategory.ai, build: copilot),
        ExternalToolPreset(label: '+ Goose', executable: 'goose', category: ExternalToolCategory.ai, build: goose),
        ExternalToolPreset(label: '+ Amazon Q', executable: 'q', category: ExternalToolCategory.ai, build: amazonQ),
        ExternalToolPreset(label: '+ Warp', executable: 'warp', category: ExternalToolCategory.ai, build: warp),
        ExternalToolPreset(label: '+ Ollama', executable: 'ollama', category: ExternalToolCategory.ai, build: ollama),
        // Editors
        ExternalToolPreset(label: '+ VS Code', executable: 'code', category: ExternalToolCategory.editors, build: vscode),
        ExternalToolPreset(label: '+ Cursor', executable: 'cursor', category: ExternalToolCategory.editors, build: cursor),
        ExternalToolPreset(label: '+ Windsurf', executable: 'windsurf', category: ExternalToolCategory.editors, build: windsurf),
        ExternalToolPreset(label: '+ Zed', executable: 'zed', category: ExternalToolCategory.editors, build: zed),
        ExternalToolPreset(label: '+ IntelliJ', executable: 'idea', category: ExternalToolCategory.editors, build: idea),
        ExternalToolPreset(label: '+ Sublime', executable: 'subl', category: ExternalToolCategory.editors, build: sublime),
        ExternalToolPreset(label: '+ Neovim', executable: 'nvim', category: ExternalToolCategory.editors, build: nvim),
        ExternalToolPreset(label: '+ Helix', executable: 'hx', category: ExternalToolCategory.editors, build: helix),
        ExternalToolPreset(label: '+ Emacs', executable: 'emacs', category: ExternalToolCategory.editors, build: emacs),
        ExternalToolPreset(label: '+ Vim', executable: 'vim', category: ExternalToolCategory.editors, build: vim),
        ExternalToolPreset(label: '+ Fleet', executable: 'fleet', category: ExternalToolCategory.editors, build: fleet),
        ExternalToolPreset(label: '+ Lapce', executable: 'lapce', category: ExternalToolCategory.editors, build: lapce),
        // Git GUIs
        ExternalToolPreset(label: '+ GitHub Desktop', executable: 'github', category: ExternalToolCategory.explore, build: githubDesktop),
        ExternalToolPreset(label: '+ GitKraken', executable: 'gitkraken', category: ExternalToolCategory.explore, build: gitkraken),
        ExternalToolPreset(label: '+ Fork', executable: 'fork', category: ExternalToolCategory.explore, build: fork),
        ExternalToolPreset(label: '+ Sourcetree', executable: 'stree', category: ExternalToolCategory.explore, build: sourcetree),
        ExternalToolPreset(label: '+ Tower', executable: 'gittower', category: ExternalToolCategory.explore, build: tower),
        // Explore — file browsers, analysis, git TUIs
        ExternalToolPreset(label: '+ LazyGit', executable: 'lazygit', category: ExternalToolCategory.explore, build: lazygit),
        ExternalToolPreset(label: '+ Tig', executable: 'tig', category: ExternalToolCategory.explore, build: tig),
        ExternalToolPreset(label: '+ GitUI', executable: 'gitui', category: ExternalToolCategory.explore, build: gitui),
        ExternalToolPreset(label: '+ Broot', executable: 'broot', category: ExternalToolCategory.explore, build: broot),
        ExternalToolPreset(label: '+ Yazi', executable: 'yazi', category: ExternalToolCategory.explore, build: yazi),
        ExternalToolPreset(label: '+ Ranger', executable: 'ranger', category: ExternalToolCategory.explore, build: ranger),
        ExternalToolPreset(label: '+ lf', executable: 'lf', category: ExternalToolCategory.explore, build: lf),
        ExternalToolPreset(label: '+ nnn', executable: 'nnn', category: ExternalToolCategory.explore, build: nnn),
        ExternalToolPreset(label: '+ Glow', executable: 'glow', category: ExternalToolCategory.explore, build: glow),
        ExternalToolPreset(label: '+ Dust', executable: 'dust', category: ExternalToolCategory.explore, build: dust),
        ExternalToolPreset(label: '+ Tokei', executable: 'tokei', category: ExternalToolCategory.explore, build: tokei),
        ExternalToolPreset(label: '+ Delta', executable: 'delta', category: ExternalToolCategory.explore, build: delta),
        ExternalToolPreset(label: '+ Difftastic', executable: 'difft', category: ExternalToolCategory.explore, build: difftastic),
        ExternalToolPreset(label: '+ Terminal', executable: 'wt', category: ExternalToolCategory.explore, build: windowsTerminal),
        ExternalToolPreset(label: '+ GitHub', executable: 'gh', category: ExternalToolCategory.explore, build: ghBrowse),
        ExternalToolPreset(label: '+ Onefetch', executable: 'onefetch', category: ExternalToolCategory.explore, build: onefetch),
        ExternalToolPreset(label: '+ scc', executable: 'scc', category: ExternalToolCategory.explore, build: scc),
        ExternalToolPreset(label: '+ ast-grep', executable: 'sg', category: ExternalToolCategory.explore, build: astGrep),
        ExternalToolPreset(label: '+ serpl', executable: 'serpl', category: ExternalToolCategory.explore, build: serpl),
        ExternalToolPreset(label: '+ D2', executable: 'd2', category: ExternalToolCategory.explore, build: d2),
        ExternalToolPreset(label: '+ Hyperfine', executable: 'hyperfine', category: ExternalToolCategory.explore, build: hyperfine),
        ExternalToolPreset(label: '+ Antigravity', executable: 'python', category: ExternalToolCategory.explore, build: antigravity),
        ExternalToolPreset(label: '+ Jujutsu', executable: 'jj', category: ExternalToolCategory.explore, build: jujutsu),
        // Ops — build, CI, infra, security, API, DB
        ExternalToolPreset(label: '+ Just', executable: 'just', category: ExternalToolCategory.ops, build: just),
        ExternalToolPreset(label: '+ Task', executable: 'task', category: ExternalToolCategory.ops, build: taskRunner),
        ExternalToolPreset(label: '+ Make', executable: 'make', category: ExternalToolCategory.ops, build: make),
        ExternalToolPreset(label: '+ Act', executable: 'act', category: ExternalToolCategory.ops, build: act),
        ExternalToolPreset(label: '+ Docker', executable: 'docker', category: ExternalToolCategory.ops, build: docker),
        ExternalToolPreset(label: '+ K9s', executable: 'k9s', category: ExternalToolCategory.ops, build: k9s),
        ExternalToolPreset(label: '+ Stern', executable: 'stern', category: ExternalToolCategory.ops, build: stern),
        ExternalToolPreset(label: '+ Terraform', executable: 'terraform', category: ExternalToolCategory.ops, build: terraform),
        ExternalToolPreset(label: '+ Pulumi', executable: 'pulumi', category: ExternalToolCategory.ops, build: pulumi),
        ExternalToolPreset(label: '+ Trivy', executable: 'trivy', category: ExternalToolCategory.ops, build: trivy),
        ExternalToolPreset(label: '+ Grype', executable: 'grype', category: ExternalToolCategory.ops, build: grype),
        ExternalToolPreset(label: '+ HTTPie', executable: 'http', category: ExternalToolCategory.ops, build: httpie),
        ExternalToolPreset(label: '+ Hurl', executable: 'hurl', category: ExternalToolCategory.ops, build: hurl),
        ExternalToolPreset(label: '+ Bruno', executable: 'bruno', category: ExternalToolCategory.ops, build: bruno),
        ExternalToolPreset(label: '+ LazyDocker', executable: 'lazydocker', category: ExternalToolCategory.ops, build: lazydocker),
        ExternalToolPreset(label: '+ DevContainer', executable: 'devcontainer', category: ExternalToolCategory.ops, build: devcontainer),
        ExternalToolPreset(label: '+ Watchexec', executable: 'watchexec', category: ExternalToolCategory.ops, build: watchexec),
        ExternalToolPreset(label: '+ mise', executable: 'mise', category: ExternalToolCategory.ops, build: mise),
        ExternalToolPreset(label: '+ Zellij', executable: 'zellij', category: ExternalToolCategory.ops, build: zellij),
        ExternalToolPreset(label: '+ git-cliff', executable: 'git-cliff', category: ExternalToolCategory.ops, build: gitCliff),
        ExternalToolPreset(label: '+ Posting', executable: 'posting', category: ExternalToolCategory.ops, build: posting),
        ExternalToolPreset(label: '+ usql', executable: 'usql', category: ExternalToolCategory.ops, build: usql),
        ExternalToolPreset(label: '+ pgcli', executable: 'pgcli', category: ExternalToolCategory.ops, build: pgcli),
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
