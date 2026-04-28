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
class ExternalToolPreset {
  /// Display label for the "+" chip — e.g. "Claude", "LazyGit".
  final String label;

  /// PATH-resolved executable. Detection probes this name; the
  /// preset only renders when the OS finds it.
  final String executable;

  /// Factory that produces a fresh `ExternalTool` seeded with the
  /// preset's defaults (label, args, launch mode). Always returns a
  /// new instance with a fresh id — safe to call multiple times.
  final ExternalTool Function() build;

  const ExternalToolPreset({
    required this.label,
    required this.executable,
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

  /// LazyGit — TUI git interface. Operates on the cwd, no args
  /// needed. Massive time-saver for users who prefer keyboard-
  /// driven git over Manifold's mouse-driven panels for certain
  /// flows (rebase, cherry-pick, interactive staging).
  static ExternalTool lazygit() => ExternalTool.create(
        label: 'LazyGit',
        executable: 'lazygit',
        args: const [],
        mode: ToolLaunchMode.newTerminal,
      );

  /// Empty preset — what "Add custom tool" produces. The settings
  /// editor lets the user fill in the fields after.
  static ExternalTool blank() => ExternalTool.create(
        label: '',
        executable: '',
        args: const ['{path}'],
        mode: ToolLaunchMode.newTerminal,
      );

  /// All curated detectable presets, in display order. Excludes the
  /// "custom" preset, which is rendered separately as an always-on
  /// escape hatch.
  static List<ExternalToolPreset> get all => [
        // AI assistants first — the highest-leverage, most-novel
        // tools and the user's stated focus.
        ExternalToolPreset(label: '+ Claude', executable: 'claude', build: claude),
        ExternalToolPreset(label: '+ Aider', executable: 'aider', build: aider),
        // Editors. VS Code and Cursor before Zed/Sublime because
        // they're the modal majority share.
        ExternalToolPreset(label: '+ VS Code', executable: 'code', build: vscode),
        ExternalToolPreset(label: '+ Cursor', executable: 'cursor', build: cursor),
        ExternalToolPreset(label: '+ Zed', executable: 'zed', build: zed),
        ExternalToolPreset(label: '+ Sublime', executable: 'subl', build: sublime),
        // Git / dev power-tool: TUI git frontend. Time-saver for
        // anyone who lives in lazygit.
        ExternalToolPreset(label: '+ LazyGit', executable: 'lazygit', build: lazygit),
      ];

  /// All executable names worth probing on PATH — derived from
  /// [all]. The detection backend uses this as its candidate set.
  static List<String> get detectableExecutables =>
      [for (final p in all) p.executable];
}
