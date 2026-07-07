// Side-effect-free classification of a `git merge-tree --write-tree` probe.
//
// Kept in its own dependency-light library so the classifier is a pure
// function the tests can exercise without spawning git and without dragging
// in the whole branches-page widget graph. The UI layer (branches_page.dart)
// runs the probe through the hardened exec layer and hands the raw
// exit/stdout/stderr here for interpretation.

/// The outcome of a pre-merge conflict probe. [conflictingPaths] is the set
/// of paths that would conflict (empty when mergeable or when the probe
/// itself could not resolve).
class MergePreflight {
  final bool mergeable;
  final List<String> conflictingPaths;

  /// False when the preflight command itself could not run (git < 2.38,
  /// process error, etc.). Callers should surface a notice rather than
  /// treating the absence of conflict paths as a clean result.
  final bool available;

  /// True only when [available] is false AND the failure was specifically an
  /// unrecognised `merge-tree --write-tree` option/subcommand — i.e. the git
  /// binary predates 2.38. Other failures (unreachable refs, lock contention)
  /// leave this false so the UI shows a generic notice, not a wrong version
  /// diagnosis.
  final bool versionUnsupported;
  const MergePreflight({
    required this.mergeable,
    required this.conflictingPaths,
    this.available = true,
    this.versionUnsupported = false,
  });
}

/// Does [stderr] name an unknown option/subcommand — the signature of a git
/// too old to support `merge-tree --write-tree` (2.38+)? Kept narrow: only
/// this class of failure earns the "git 2.38+ required" diagnosis. Other
/// non-zero exits (unreachable refs, index.lock, etc.) are just "unavailable".
bool mergeTreeStderrIsUnknownOption(String stderr) {
  final s = stderr.toLowerCase();
  return s.contains('unknown option') ||
      s.contains('unknown switch') ||
      s.contains('usage:') ||
      (s.contains('--write-tree') &&
          (s.contains('unknown') || s.contains('unrecognized')));
}

/// Pure classifier for `git merge-tree --write-tree --name-only <base> <head>`.
///
///   exit 0  → clean merge (tree SHA on stdout).
///   exit 1  → conflicts; tree SHA on line 1, conflicting paths thereafter.
///   other   → unavailable; [MergePreflight.versionUnsupported] is set only
///             when stderr shows the option is unknown (git < 2.38).
MergePreflight classifyMergeTreeProbe(
    int exitCode, String stdout, String stderr) {
  if (exitCode == 0) {
    return const MergePreflight(mergeable: true, conflictingPaths: []);
  }
  if (exitCode == 1) {
    final lines = stdout.split('\n');
    final paths = <String>[
      for (var i = 1; i < lines.length; i++)
        if (lines[i].trim().isNotEmpty) lines[i].trim(),
    ];
    return MergePreflight(mergeable: false, conflictingPaths: paths);
  }
  return MergePreflight(
    mergeable: false,
    conflictingPaths: const [],
    available: false,
    versionUnsupported: mergeTreeStderrIsUnknownOption(stderr),
  );
}
