import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../ui/context_menu.dart';
import '../../ui/control_chrome.dart';
import '../../ui/form_controls.dart';
import '../../ui/material_surface.dart';
import '../../ui/status_view.dart';
import '../../ui/motion.dart';
import '../../ui/tokens.dart';
import '../../backend/git.dart';
import '../../backend/gh.dart';
import '../../backend/git_result.dart';
import '../../backend/dtos.dart';
import '../../backend/file_coupling.dart';
import '../../backend/logos_git.dart';
import '../../app/repository_state.dart';
import '../../app/file_coupling_state.dart';
import '../../app/logos_git_state.dart';
import '../diff/diff_models.dart';
import '../diff/diff_shell.dart' show DiffLineView;
import '../../components/icons/app_icons.dart';
import '../../diagnostics/diagnostics_state.dart';

class BranchesPage extends StatefulWidget {
  const BranchesPage({super.key});
  @override
  State<BranchesPage> createState() => _BranchesPageState();
}

/// The three lenses on this tab. They share the same row grammar but
/// surface different metadata about the same conceptual space — your
/// repo's worklines.
enum _BranchesLens { branches, prs, issues }

class _BranchesPageState extends State<BranchesPage> {
  final Stopwatch _mountedAt = Stopwatch()..start();
  List<BranchInfo> _branches = [];
  List<TagEntryData> _tags = [];
  bool _loading = false;
  String? _error;
  String? _lastRepo;
  String? _hoveredTag;

  final _newBranchCtrl = TextEditingController();
  bool _actionRunning = false;
  String? _actionError;

  // Lens state ------------------------------------------------------------
  _BranchesLens _lens = _BranchesLens.branches;
  // PR cache. Loaded lazily on first PRs-lens activation per repo, then
  // refreshed manually via the ✦ glyph.
  List<PullRequestSummary>? _prs;
  bool _prsLoading = false;
  String? _prsError;
  // Issue cache, same lifecycle.
  List<IssueSummary>? _issues;
  bool _issuesLoading = false;
  String? _issuesError;
  // Inline-expand selection — at most one PR or issue open at a time.
  int? _expandedPrNumber;
  int? _expandedIssueNumber;
  // Per-PR check cache, lazily populated when a PR is expanded.
  final Map<int, List<CheckSummary>> _prChecks = {};
  final Set<int> _prChecksLoading = {};
  // Per-PR detail cache (body, files, comments, diff). Same shape as
  // checks: lazy load on expand, drop on repo switch.
  final Map<int, PullRequestDetail> _prDetails = {};
  final Set<int> _prDetailsLoading = {};
  // Per-issue detail cache.
  final Map<int, IssueDetail> _issueDetails = {};
  final Set<int> _issueDetailsLoading = {};
  // Cached gh availability — probed once per repo open.
  GhStatus? _ghStatus;
  // Logged-in user's GitHub login. Used to evaluate the MINE filter and
  // to skip the "assign me" action for issues you're already assigned to.
  String _viewerLogin = '';

  // Filter state per lens. Empty = no filter; presence of a name = active.
  final Set<String> _prFilters = <String>{};
  final Set<String> _issueFilters = <String>{};
  // Search query per lens. Empty = no filter.
  String _prSearch = '';
  String _issueSearch = '';
  // Search field controllers; created lazily when the field appears.
  final TextEditingController _prSearchCtrl = TextEditingController();
  final TextEditingController _issueSearchCtrl = TextEditingController();

  // Keyboard navigation focus indices, per lens. Null = nothing focused.
  int? _focusedPrIndex;
  int? _focusedIssueIndex;
  final FocusNode _lensFocusNode = FocusNode(debugLabel: 'BranchesPage.lens');

  // Action-in-flight indicators, so the row can render its progress
  // capsule and refuse double-clicks. Keyed by PR or issue number.
  final Set<int> _actionInFlight = <int>{};

  // Keyboard help overlay visibility.
  bool _showKeyboardHelp = false;

  // Per-PR active file pill (the file whose diff is rendered in the
  // expanded view). Defaults to the first file if not yet picked.
  final Map<int, String> _activeFileByPr = {};

  // File-pills layout mode for the PR detail view. Two states:
  //   false (default) — horizontal scroll, narrow row
  //   true            — wrap, all files visible at once
  // Persisted to SharedPreferences (NOT exposed in settings UI by
  // design — it's a power-user preference discovered by clicking the
  // FILES section header). Single key: `branches.pr_files_wrap`.
  static const _kFilePillsWrapKey = 'branches.pr_files_wrap';
  bool _filePillsWrap = false;

  Future<void> _loadFilePillsWrapPref() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_kFilePillsWrapKey) ?? false;
    if (mounted && v != _filePillsWrap) {
      setState(() => _filePillsWrap = v);
    }
  }

  Future<void> _toggleFilePillsWrap() async {
    final next = !_filePillsWrap;
    setState(() => _filePillsWrap = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFilePillsWrapKey, next);
  }

  // RESONANCE AURORA — file path currently under the mouse, scoped
  // to the FILES strip in an expanded PR. When set, neighbor pills
  // (Jaccard ≥ 0.4) light up briefly in their cluster color: the
  // coupling matrix's invisible structure becomes visible *only on
  // intent* (you ask by hovering, the codebase answers by exhaling).
  // ValueNotifier so per-pill hover doesn't rebuild the strip.
  final ValueNotifier<String?> _auroraSourceFile = ValueNotifier<String?>(null);

  // PR number currently under the mouse, for the mutual-collision
  // highlight. Hovering any PR row lights up every OTHER PR it
  // collides with, so the maintainer's eye sees the dependency graph
  // without clicking a thing. ValueNotifier so per-row hover changes
  // don't rebuild the whole list — only siblings consult the value.
  final ValueNotifier<int?> _hoveredPrNumber = ValueNotifier<int?>(null);
  // Cached collision map — invalidated when _prDetails changes. The
  // map is O(P²) but at realistic open-PR counts (<50) negligible;
  // recomputing per build is fine, but caching avoids work on every
  // hover-rebuild.
  Map<int, Set<int>>? _cachedCollisionMap;
  int _prDetailsRev = 0;
  // RECENT TOUCHERS + per-file thermal heat per PR. One scan, two
  // signals — see scanFileSignals() in git.dart. Loaded lazily on
  // expand. Pure local git; transferable to any host.
  final Map<int, FileSignals> _prFileSignals = {};
  final Set<int> _prFileSignalsLoading = <int>{};

  // TOUCHED-SINCE-YOU-LOOKED — local timestamp per PR-id of when the
  // viewer last opened that PR's detail. Persisted to SharedPreferences
  // as ISO-string-keyed JSON. The row gets a small unread dot when
  // `pr.updatedAt > lastSeen[number]`.
  static const _kPrLastSeenKey = 'branches.pr_last_seen_v1';
  Map<int, DateTime> _prLastSeen = {};

  Future<void> _loadPrLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrLastSeenKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final out = <int, DateTime>{};
      for (final e in j.entries) {
        final n = int.tryParse(e.key);
        final ts = e.value is String
            ? DateTime.tryParse(e.value as String)
            : null;
        if (n != null && ts != null) out[n] = ts;
      }
      if (mounted) setState(() => _prLastSeen = out);
    } catch (_) {/* ignore corrupt blob */}
  }

  Future<void> _markPrSeen(int number) async {
    final now = DateTime.now();
    setState(() => _prLastSeen[number] = now);
    await _persistPrLastSeen();
  }

  /// Inverse of [_markPrSeen]: drops this PR's last-seen record so
  /// `_isUnread` flips back to true. Used by the right-click
  /// "Mark as unread" affordance — lets reviewers manually re-surface
  /// a PR they've already opened ("I'll look at this tomorrow").
  Future<void> _unmarkPrSeen(int number) async {
    if (!_prLastSeen.containsKey(number)) return;
    setState(() => _prLastSeen.remove(number));
    await _persistPrLastSeen();
  }

  Future<void> _persistPrLastSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final j = <String, String>{
      for (final e in _prLastSeen.entries) '${e.key}': e.value.toIso8601String()
    };
    await prefs.setString(_kPrLastSeenKey, jsonEncode(j));
  }

  /// Returns true when `pr.updatedAt` is newer than the viewer's
  /// last-seen timestamp for that PR. Drives the unread dot.
  bool _isUnread(PullRequestSummary pr) {
    final last = _prLastSeen[pr.number];
    // No record = the viewer has never opened this PR's detail. Treat
    // as unread so the dot DOES appear on truly-fresh-to-you PRs;
    // otherwise an inbox you've never touched has no dots and the
    // signal is invisible. The dot disappears the moment you expand.
    if (last == null) return true;
    return pr.updatedAt.isAfter(last);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      DiagnosticsState.instance.recordUiTiming(
        event: 'branches.page.first-paint',
        phase: 'mount',
        durationMs: _mountedAt.elapsedMicroseconds / 1000,
      );
    });
    _loadFilePillsWrapPref();
    _loadPrLastSeen();
  }

  @override
  void dispose() {
    _newBranchCtrl.dispose();
    _prSearchCtrl.dispose();
    _issueSearchCtrl.dispose();
    _lensFocusNode.dispose();
    _hoveredPrNumber.dispose();
    _auroraSourceFile.dispose();
    super.dispose();
  }

  Future<void> _load(String repo) async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
    });
    // git branch + git tag are independent — run them in parallel
    // instead of sequentially so the cold path is one round-trip
    // instead of two.
    final results = await Future.wait([listBranches(repo), listTags(repo)]);
    final bResult = results[0] as GitResult<List<BranchInfo>>;
    final tResult = results[1] as GitResult<List<TagEntryData>>;
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (bResult.ok) {
        _branches = bResult.data!;
      } else {
        _error = bResult.error;
      }
      if (tResult.ok) {
        _tags = tResult.data!;
      }
    });
    stopwatch.stop();
    await DiagnosticsState.instance.recordUiTiming(
      event: 'branches.snapshot.load',
      phase: 'interaction',
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      ok: bResult.ok && tResult.ok,
      errorCode: bResult.ok && tResult.ok ? null : 'branches.load_failed',
    );
    // Fire-and-forget background prefetch of PRs + Issues + their per-row
    // detail. Modeled on the history tab's `unawaited(_prefetchAllDetails())`
    // pattern: render the list right now, populate caches in the background
    // so subsequent lens switches and row expands hit warm caches and don't
    // spinner. Survives mid-flight repo switches via the `_lastRepo` guard
    // inside each fetch's setState.
    if (mounted) {
      unawaited(_prefetchAll(repo));
    }
  }

  /// Eagerly populate PR + Issue lists AND per-row details, in the
  /// background. Cheap to call when a lens is already loaded — the
  /// inner `_ensure*` checks short-circuit on cached entries.
  Future<void> _prefetchAll(String repo) async {
    // Probe gh once. If unavailable, skip the whole prefetch — every
    // gh call would return the same "not installed/authed" state and
    // the user would see those notices when they switched lenses
    // anyway.
    _ghStatus ??= await ghStatus();
    if (!_ghStatus!.usable) return;
    if (_viewerLogin.isEmpty) {
      _viewerLogin = await whoami();
    }
    // Run the two list fetches in parallel — they're independent.
    await Future.wait([
      if (_prs == null && !_prsLoading) _fetchPullRequests(repo),
      if (_issues == null && !_issuesLoading) _fetchIssues(repo),
    ]);
    if (!mounted || _lastRepo != repo) return;
    // Once the lists are in, warm the per-row caches in parallel
    // (bounded). PR detail load = `gh pr view` + `gh pr diff` + checks
    // = 3 process spawns each. With bounded concurrency we cap the
    // burst on `gh` and the OS process table.
    final prs = _prs ?? const <PullRequestSummary>[];
    final issues = _issues ?? const <IssueSummary>[];
    await Future.wait([
      if (prs.isNotEmpty) _prefetchPrDetails(repo, prs),
      if (issues.isNotEmpty) _prefetchIssueDetails(repo, issues),
    ]);
  }

  Future<void> _prefetchPrDetails(
      String repo, List<PullRequestSummary> prs) async {
    await _bounded<void>(
      [
        for (final pr in prs)
          () async {
            if (!mounted || _lastRepo != repo) return;
            // Detail (body + files + diff + comments) and checks fetch
            // in parallel for each PR — they don't depend on each other.
            await Future.wait([
              _ensurePrDetailLoaded(repo, pr.number),
              _ensureChecksLoaded(repo, pr.number),
            ]);
          },
      ],
      maxConcurrent: 4,
    );
  }

  Future<void> _prefetchIssueDetails(
      String repo, List<IssueSummary> issues) async {
    await _bounded<void>(
      [
        for (final issue in issues)
          () async {
            if (!mounted || _lastRepo != repo) return;
            await _ensureIssueDetailLoaded(repo, issue.number);
          },
      ],
      maxConcurrent: 4,
    );
  }

  /// Run [tasks] with at most [maxConcurrent] in flight at a time.
  /// Errors per task are swallowed — prefetch is best-effort, and a
  /// transient gh failure on one row shouldn't kill the warm-up of
  /// every other row.
  Future<void> _bounded<T>(
    List<Future<T> Function()> tasks, {
    int maxConcurrent = 4,
  }) async {
    var idx = 0;
    Future<void> worker() async {
      while (true) {
        final i = idx++;
        if (i >= tasks.length) return;
        try {
          await tasks[i]();
        } catch (_) {/* best-effort prefetch */}
      }
    }

    await Future.wait(List.generate(maxConcurrent, (_) => worker()));
  }

  Future<void> _checkout(String repo, String name) async {
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await checkoutBranch(repo, name);
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    await _load(repo);
    if (!mounted) return;
    await context.read<RepositoryState>().refreshStatus();
  }

  /// Deletes [name] in [repo]. Returns the outcome so the caller (the
  /// branch row) can morph its trash button into a force-confirm
  /// affordance instead of bubbling git's "not fully merged" stderr
  /// up to the create-branch panel.
  Future<_DeleteBranchOutcome> _deleteBranch(
    String repo,
    String name, {
    bool force = false,
  }) async {
    setState(() => _actionRunning = true);
    final r = await deleteBranch(repo, name, force: force);
    if (!mounted) return const _DeleteBranchOutcome.error('cancelled');
    setState(() => _actionRunning = false);
    if (!r.ok) {
      final raw = r.error ?? '';
      // First-tap safe delete bounced because git considers the branch
      // unmerged. Don't surface an error — tell the row to arm for force.
      if (!force && raw.toLowerCase().contains('not fully merged')) {
        return const _DeleteBranchOutcome.needsForce();
      }
      return _DeleteBranchOutcome.error(_humanizeDeleteError(raw));
    }
    await _load(repo);
    return const _DeleteBranchOutcome.ok();
  }

  /// Strips git's `error:` prefix and `hint:` lines, leaving only the
  /// human-readable first sentence.
  static String _humanizeDeleteError(String raw) {
    final firstLine = raw.split('\n').first.trim();
    if (firstLine.toLowerCase().startsWith('error:')) {
      return firstLine.substring(6).trim();
    }
    return firstLine.isEmpty ? 'delete failed' : firstLine;
  }

  Future<void> _deleteTag(String repo, String name) async {
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await deleteTag(repo, name);
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    await _load(repo);
  }

  // ── Lens activation / fetch ─────────────────────────────────────────

  /// Switch lens. Lazily fires a fetch the first time PRs/Issues are
  /// shown; subsequent switches are instant against the cache.
  void _switchLens(_BranchesLens next, String repoPath) {
    if (_lens == next) return;
    setState(() => _lens = next);
    if (next == _BranchesLens.prs) {
      // Issues live in the right-hand sidebar of the PR view now —
      // kick both fetches in parallel on lens activation so the
      // panel populates without waiting on the prefetch heuristic.
      if (_prs == null && !_prsLoading) _fetchPullRequests(repoPath);
      if (_issues == null && !_issuesLoading) _fetchIssues(repoPath);
    } else if (next == _BranchesLens.issues &&
        _issues == null &&
        !_issuesLoading) {
      _fetchIssues(repoPath);
    }
  }

  Future<void> _fetchPullRequests(String repoPath) async {
    _ghStatus ??= await ghStatus();
    if (!_ghStatus!.usable) {
      if (!mounted) return;
      setState(() {
        _prs = const [];
        _prsError = null;
      });
      return;
    }
    if (_viewerLogin.isEmpty) {
      _viewerLogin = await whoami();
    }
    setState(() {
      _prsLoading = true;
      _prsError = null;
    });
    final r = await listPullRequests(repoPath);
    if (!mounted) return;
    setState(() {
      _prsLoading = false;
      if (r.ok) {
        _prs = r.data!;
        // Smart default: if the viewer authored or was asked to review
        // any of the open PRs, pre-select the MINE filter so the lens
        // opens on what's relevant. Skips when the viewer has nothing
        // here — empty filter shows everything.
        if (_prFilters.isEmpty &&
            _viewerLogin.isNotEmpty &&
            _prs!.any((pr) => _prMatchesMine(pr))) {
          _prFilters.add('MINE');
        }
      } else {
        _prsError = r.error;
        _prs ??= const [];
      }
    });
  }

  Future<void> _fetchIssues(String repoPath) async {
    _ghStatus ??= await ghStatus();
    if (!_ghStatus!.usable) {
      if (!mounted) return;
      setState(() {
        _issues = const [];
        _issuesError = null;
      });
      return;
    }
    setState(() {
      _issuesLoading = true;
      _issuesError = null;
    });
    final r = await listIssues(repoPath);
    if (!mounted) return;
    setState(() {
      _issuesLoading = false;
      if (r.ok) {
        _issues = r.data!;
      } else {
        _issuesError = r.error;
        _issues ??= const [];
      }
    });
  }

  Future<void> _refreshActiveLens(String repoPath) async {
    switch (_lens) {
      case _BranchesLens.branches:
        await _load(repoPath);
        break;
      case _BranchesLens.prs:
        await _fetchPullRequests(repoPath);
        break;
      case _BranchesLens.issues:
        await _fetchIssues(repoPath);
        break;
    }
  }

  /// Right-click on a collapsed PR row. Reuses the shared app context
  /// menu so the grammar matches the changes page's file menu — same
  /// visual language, same hover/destructive styles. "Download as
  /// .patch" fetches the PR detail if it isn't already cached before
  /// handing off to [_exportPrAsPatch].
  void _showPrContextMenu(
    BuildContext context,
    Offset globalPos,
    PullRequestSummary pr,
    String repoPath,
  ) {
    final unread = _isUnread(pr);
    final sections = <List<AppContextMenuItem>>[
      [
        // ⭐ Unique to this app: take the PR's cached diff, open it in
        // the patch preview so the user sees CONFLICTS-WITH-YOU /
        // WILL FIGHT / resonance against their CURRENT working tree
        // BEFORE they commit to `gh pr checkout`. Pre-flight for any PR.
        AppContextMenuItem(
          icon: Icons.science_outlined,
          label: 'Apply locally (preview)…',
          onTap: () async {
            var detail = _prDetails[pr.number];
            if (detail == null || detail.diff.isEmpty) {
              await _ensurePrDetailLoaded(repoPath, pr.number);
              if (!mounted) return;
              detail = _prDetails[pr.number];
            }
            if (detail == null || detail.diff.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not load PR diff.')),
              );
              return;
            }
            if (!mounted) return;
            await _openPatchPreview(
              repoPath,
              detail.diff,
              sourceLabel: 'PR #${pr.number}: ${pr.title}',
            );
          },
        ),
        AppContextMenuItem(
          icon: Icons.download_done_outlined,
          label: 'Checkout this PR',
          onTap: () => _checkoutPr(repoPath, pr.number),
        ),
      ],
      [
        AppContextMenuItem(
          icon: Icons.file_download_outlined,
          label: 'Download as .patch',
          onTap: () async {
            var detail = _prDetails[pr.number];
            if (detail == null || detail.diff.isEmpty) {
              await _ensurePrDetailLoaded(repoPath, pr.number);
              if (!mounted) return;
              detail = _prDetails[pr.number];
            }
            if (detail == null || detail.diff.isEmpty) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Could not load PR diff.')),
              );
              return;
            }
            if (!mounted) return;
            await _exportPrAsPatch(context, pr, detail);
          },
        ),
        AppContextMenuItem(
          icon: Icons.content_copy_outlined,
          label: 'Copy branch name',
          onTap: () async {
            await Clipboard.setData(ClipboardData(text: pr.headRef));
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied "${pr.headRef}"')),
            );
          },
        ),
      ],
      [
        AppContextMenuItem(
          icon: unread
              ? Icons.mark_email_read_outlined
              : Icons.mark_email_unread_outlined,
          label: unread ? 'Mark as read' : 'Mark as unread',
          onTap: () =>
              unread ? _markPrSeen(pr.number) : _unmarkPrSeen(pr.number),
        ),
      ],
    ];
    showAppContextMenu(context, globalPos, sections);
  }

  /// Patch-loop entry point. Opens a tiny menu next to the `+ patch`
  /// ribbon affordance offering two sources:
  ///   - from file…      (FilePicker → read bytes)
  ///   - from clipboard  (Clipboard.getData)
  /// Both route through [_openPatchPreview] so the downstream surface
  /// is identical regardless of source.
  Future<void> _importPatch(String repoPath) async {
    final picked = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (ctx) => const _PatchSourceMenu(),
    );
    if (picked == null || !mounted) return;
    try {
      if (picked == 'file') {
        final res = await FilePicker.platform.pickFiles(
          dialogTitle: 'Open patch (.patch / .diff)',
          type: FileType.custom,
          allowedExtensions: const ['patch', 'diff', 'txt'],
          withData: true,
        );
        if (res == null || res.files.isEmpty) return;
        final f = res.files.first;
        String text;
        if (f.bytes != null) {
          text = utf8.decode(f.bytes!, allowMalformed: true);
        } else if (f.path != null) {
          text = await File(f.path!).readAsString();
        } else {
          return;
        }
        if (!mounted) return;
        await _openPatchPreview(repoPath, text, sourceLabel: f.name);
      } else if (picked == 'clipboard') {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text?.trim() ?? '';
        if (text.isEmpty) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Clipboard has no text.')),
          );
          return;
        }
        if (!mounted) return;
        await _openPatchPreview(repoPath, text,
            sourceLabel: 'clipboard.patch');
      }
    } catch (e) {
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: 'patch.import',
        errorCode: 'patch.import_failed',
        message: e.toString(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open patch: $e')),
      );
    }
  }

  /// Opens the patch preview overlay for [rawPatch]. Performs every
  /// derivation up-front — a patch is treated as a peer to a PR, so it
  /// carries the same signals: dry-run cleanness, conflicts with local
  /// dirty work, will-fight against open PRs, coupling/resonance on
  /// file pills, ghost pills for forecast neighbors. The dialog itself
  /// is a dumb render of this pre-computed state.
  Future<void> _openPatchPreview(
    String repoPath,
    String rawPatch, {
    required String sourceLabel,
  }) async {
    final lines = rawPatch.length < 32 * 1024
        ? parseUnifiedDiff(rawPatch)
        : await compute(parseUnifiedDiff, rawPatch);
    final parsed = <String, List<ParsedLine>>{};
    for (final l in lines) {
      final key = l.filePath;
      if (key == null) continue;
      (parsed[key] ??= <ParsedLine>[]).add(l);
    }
    if (parsed.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Patch is empty or unparseable.')),
      );
      return;
    }

    // Synthesize PrFile for each bucket so we can reuse _FilePillStrip,
    // resonance forecast, and cluster computation unchanged.
    final prFiles = <PrFile>[];
    for (final entry in parsed.entries) {
      var adds = 0, dels = 0;
      for (final l in entry.value) {
        if (l.kind == LineKind.added) adds++;
        else if (l.kind == LineKind.deleted) dels++;
      }
      prFiles.add(PrFile(path: entry.key, additions: adds, deletions: dels));
    }

    // Dry-run check: does this patch apply to the working tree as-is?
    final check = await applyPatch(
      repoPath,
      rawPatch,
      cached: false,
      dryRun: true,
      telemetryLabel: 'git.patch_check',
    );
    if (!mounted) return;

    // CONFLICTS-WITH-YOU — intersect patch paths with uncommitted paths.
    final status = context.read<RepositoryState>().status;
    final dirty = <String>{
      for (final f in status?.files ?? const <RepositoryStatusFile>[])
        f.path,
    };
    final patchPaths = prFiles.map((f) => f.path).toSet();
    final conflictingPaths = patchPaths.intersection(dirty);

    // WILL FIGHT — intersect patch paths with each open PR's file list.
    final fightTitles = <int, String>{};
    final fightShared = <int, Set<String>>{};
    final fightOrder = <int>[];
    for (final pr in _prs ?? const <PullRequestSummary>[]) {
      if (pr.state != 'OPEN') continue;
      final detail = _prDetails[pr.number];
      if (detail == null) continue;
      final shared = <String>{
        for (final f in detail.files)
          if (patchPaths.contains(f.path)) f.path,
      };
      if (shared.isEmpty) continue;
      fightTitles[pr.number] = pr.title;
      fightShared[pr.number] = shared;
      fightOrder.add(pr.number);
    }
    fightOrder.sort((a, b) =>
        fightShared[b]!.length.compareTo(fightShared[a]!.length));

    final couplingMatrix =
        context.read<FileCouplingState>().matrixFor(repoPath);
    final auroraSource = ValueNotifier<String?>(null);

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (ctx) => _PatchPreviewDialog(
        sourceLabel: sourceLabel,
        rawPatch: rawPatch,
        prFiles: prFiles,
        filesByPath: parsed,
        dryRunOk: check.ok,
        dryRunError: check.ok ? null : (check.error ?? 'apply --check failed'),
        conflictingPaths: conflictingPaths,
        fightTitles: fightTitles,
        fightShared: fightShared,
        fightOrder: fightOrder,
        couplingMatrix: couplingMatrix,
        auroraSource: auroraSource,
        filePillsWrap: _filePillsWrap,
        onApply: ({required bool threeWay, required bool reverse}) async {
          final r = await applyPatch(
            repoPath,
            rawPatch,
            cached: false,
            threeWay: threeWay,
            reverse: reverse,
            telemetryLabel: reverse
                ? 'git.patch_apply_reverse'
                : threeWay
                    ? 'git.patch_apply_3way'
                    : 'git.patch_apply',
          );
          if (r.ok && mounted) {
            await context.read<RepositoryState>().refreshStatus();
          }
          return r;
        },
      ),
    );
    auroraSource.dispose();
  }

  Future<void> _ensureChecksLoaded(String repoPath, int prNumber) async {
    if (_prChecks.containsKey(prNumber) ||
        _prChecksLoading.contains(prNumber)) {
      return;
    }
    setState(() => _prChecksLoading.add(prNumber));
    final r = await listChecks(repoPath, prNumber);
    if (!mounted) return;
    setState(() {
      _prChecksLoading.remove(prNumber);
      if (r.ok) {
        _prChecks[prNumber] = r.data!;
      } else {
        // Cache an empty list so the row stops spinning; the UI shows
        // "no checks reported" which is honest when checks aren't set up
        // OR when gh failed to fetch them (rare; checks-list rarely errors
        // hard). The error message stays in stderr / telemetry.
        _prChecks[prNumber] = const [];
      }
    });
  }

  // ── Locally-derived signals (the workline graph) ────────────────────

  /// Files in [prFiles] that the user currently has uncommitted work in
  /// (staged or unstaged). Pure local computation — answers "will
  /// merging this PR collide with my work?" before the merge button is
  /// pressed. No GitHub round-trip; uses the working-tree status that
  /// `RepositoryState` already keeps warm.
  Set<String> _conflictingPaths(
    List<PrFile> prFiles,
    RepositoryStatus? status,
  ) {
    if (status == null || prFiles.isEmpty) return const {};
    final dirty = status.files
        .where((f) => f.staged.isNotEmpty || f.unstaged.isNotEmpty)
        .map((f) => f.path)
        .toSet();
    if (dirty.isEmpty) return const {};
    final out = <String>{};
    for (final f in prFiles) {
      if (dirty.contains(f.path)) out.add(f.path);
    }
    return out;
  }

  /// Walk every cached PR body and pull out issue numbers it references
  /// via `closes/fixes/resolves #N`, `addresses #N`, or bare `#N`. Builds
  /// a `Map<issueNumber, Set<prNumber>>` so issue rows can render an
  /// "← addressed by PR #M" backlink without firing a single API call.
  /// O(visible PRs) on each rebuild — cheap; bodies are short strings.
  Map<int, Set<int>> _issueBacklinksFromPrs() {
    final out = <int, Set<int>>{};
    final closingRe = RegExp(
        r'\b(?:closes?|closed|fixes|fixed|resolves?|resolved|addresses?|refs?|references?)\s+#(\d+)',
        caseSensitive: false);
    final bareRe = RegExp(r'(?:^|[^\w/])#(\d+)\b');
    for (final entry in _prDetails.entries) {
      final body = entry.value.body;
      final found = <int>{};
      for (final m in closingRe.allMatches(body)) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null) found.add(n);
      }
      for (final m in bareRe.allMatches(body)) {
        final n = int.tryParse(m.group(1) ?? '');
        if (n != null) found.add(n);
      }
      for (final n in found) {
        (out[n] ??= <int>{}).add(entry.key);
      }
    }
    return out;
  }

  /// Pairwise PR-collision map: for each open PR, the set of OTHER
  /// open PRs whose changed-file lists intersect with it. Pure local
  /// computation across cached PR detail (`_prDetails[*].files`). The
  /// signal a maintainer kills for: "if I land #142 first, #138 will
  /// need a rebase." Only counts pairs where BOTH PRs have detail
  /// loaded; before prefetch finishes the map is partial — fine, fills
  /// in as data lands. O(P²) on PR count; trivial at realistic
  /// open-PR sizes.
  Map<int, Set<int>> _prCollisionMap() {
    if (_cachedCollisionMap != null) return _cachedCollisionMap!;
    final map = <int, Set<int>>{};
    final entries = _prDetails.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      final aNum = entries[i].key;
      final aFiles = entries[i].value.files.map((f) => f.path).toSet();
      if (aFiles.isEmpty) continue;
      for (var j = i + 1; j < entries.length; j++) {
        final bNum = entries[j].key;
        final bFiles = entries[j].value.files.map((f) => f.path).toSet();
        if (bFiles.isEmpty) continue;
        if (aFiles.intersection(bFiles).isNotEmpty) {
          (map[aNum] ??= <int>{}).add(bNum);
          (map[bNum] ??= <int>{}).add(aNum);
        }
      }
    }
    _cachedCollisionMap = map;
    return map;
  }

  /// File overlap between two specific PRs — used by the WILL FIGHT
  /// section to surface "you'll fight #138 over 3 files" rather than
  /// just naming the count of colliding PRs.
  Set<String> _sharedFiles(int a, int b) {
    final aFiles = _prDetails[a]?.files.map((f) => f.path).toSet();
    final bFiles = _prDetails[b]?.files.map((f) => f.path).toSet();
    if (aFiles == null || bFiles == null) return const {};
    return aFiles.intersection(bFiles);
  }

  /// Invalidate caches keyed off `_prDetails` content. Called from
  /// every site that mutates `_prDetails` so derived maps re-compute
  /// the next time they're asked.
  void _invalidatePrDerivations() {
    _cachedCollisionMap = null;
    _prDetailsRev++;
  }

  /// True when this PR's branch is the working tree's current head —
  /// "you're on this PR right now". Computed from `RepositoryStatus`
  /// (already kept warm). Free signal that elevates the matching row
  /// without any new fetch.
  bool _isCheckedOut(PullRequestSummary pr, RepositoryStatus? status) {
    if (status == null) return false;
    return status.branch == pr.headRef;
  }

  /// True when the viewer is explicitly listed as a pending reviewer
  /// on this PR. Used to surface "this is waiting on YOU" as an
  /// atmospheric row halo, not a label.
  bool _awaitingMyReview(PullRequestSummary pr) {
    if (_viewerLogin.isEmpty) return false;
    return pr.reviewers
        .any((r) => r.login == _viewerLogin && r.state == 'PENDING');
  }

  /// What was the LAST thing that happened on this PR? Synthesizes a
  /// single `TailEvent` from cached comments + reviews + checks +
  /// updatedAt. Drives the conversation-tail glyph at the end of the
  /// metric line so a glance answers "what's current here?" without
  /// opening anything.
  TailEvent? _conversationTail(PullRequestSummary pr) {
    final detail = _prDetails[pr.number];
    final candidates = <TailEvent>[];
    if (detail != null) {
      // Comments and reviews already merged into detail.comments by
      // pullRequestDetail; the prefix tag (`[approved]` etc) tells us
      // whether it was a review or a top-level comment.
      for (final c in detail.comments) {
        final isReview = c.body.startsWith('[');
        candidates.add(TailEvent(
          kind: isReview ? 'review' : 'comment',
          actor: c.authorLogin,
          at: c.createdAt,
          state: isReview ? _extractReviewTag(c.body) : '',
        ));
      }
    }
    final checks = _prChecks[pr.number];
    if (checks != null) {
      for (final c in checks) {
        if (c.duration == null) continue;
        // We don't have the absolute completion time; approximate as
        // pr.updatedAt for ordering. Cheap stand-in — when present we
        // mostly want it to compete with comments only when freshly
        // failing.
        final completedHint =
            c.conclusion == 'fail' || c.conclusion == 'failure'
                ? pr.updatedAt
                : pr.updatedAt.subtract(const Duration(hours: 1));
        candidates.add(TailEvent(
          kind: 'check',
          actor: '',
          at: completedHint,
          state: c.conclusion ?? '',
        ));
      }
    }
    // Author-push proxy: pr.updatedAt is the most-recent-anything on
    // the PR. If no comment/review at that exact moment, treat as a
    // push from the author.
    candidates.add(TailEvent(
      kind: 'push',
      actor: pr.authorLogin,
      at: pr.updatedAt,
    ));
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.at.compareTo(a.at));
    return candidates.first;
  }

  String _extractReviewTag(String body) {
    final m = RegExp(r'^\[([^\]]+)\]').firstMatch(body);
    if (m == null) return '';
    return m.group(1) ?? '';
  }

  /// Surface the viewer's own review state distinctly from the
  /// anonymous reviewer-dots vocabulary. Returns one of:
  ///   * '' (viewer is not a reviewer / has no opinion yet)
  ///   * 'pending' (asked to review, hasn't reviewed)
  ///   * 'approved' (still current — no PR activity since)
  ///   * 'approved-stale' (PR pushed/changed since the approval)
  ///   * 'changes_requested'
  ///   * 'commented'
  String _myReviewStateFor(PullRequestSummary pr) {
    if (_viewerLogin.isEmpty) return '';
    final mine = pr.reviewers
        .firstWhere((r) => r.login == _viewerLogin,
            orElse: () => const PrReviewer(login: '', state: ''));
    if (mine.login.isEmpty) return '';
    final state = mine.state;
    if (state == 'PENDING') return 'pending';
    if (state == 'CHANGES_REQUESTED') return 'changes_requested';
    if (state == 'COMMENTED') return 'commented';
    if (state == 'APPROVED') return 'approved';
    return '';
  }

  /// Per-reviewer queue depth: number of currently-open PRs where
  /// they're a PENDING reviewer (asked but haven't reviewed). The
  /// "@bob is buried" signal — mirror of the author queue badge.
  /// Cheap: walks `_prs` once.
  Map<String, int> _reviewerQueueDepth() {
    final out = <String, int>{};
    for (final pr in _prs ?? const <PullRequestSummary>[]) {
      for (final r in pr.reviewers) {
        if (r.state == 'PENDING') {
          out[r.login] = (out[r.login] ?? 0) + 1;
        }
      }
    }
    return out;
  }

  /// MERGED-PR override-scar detection. Returns true when a closed-
  /// state PR was merged (`state == 'MERGED'`) but had a failing or
  /// pending check at the time, OR was merged without any APPROVED
  /// review. Heuristic from cached PR detail; flags rare-but-real
  /// "this got pushed through anyway" merges. Triage gold for SRE.
  bool _hasOverrideScar(PullRequestSummary pr) {
    if (pr.state != 'MERGED') return false;
    final checks = _prChecks[pr.number] ?? const <CheckSummary>[];
    final hasFailingCheck = checks.any((c) =>
        c.conclusion == 'fail' ||
        c.conclusion == 'failure' ||
        c.conclusion == 'timed_out' ||
        c.conclusion == 'action_required');
    final hasApprovedReview =
        pr.reviewers.any((r) => r.state == 'APPROVED');
    return hasFailingCheck || !hasApprovedReview;
  }

  /// Inverse direction: given a PR's body, list issue numbers it
  /// closes/refs. Used in the expanded PR view's LINKS section.
  Set<int> _issuesReferencedBy(int prNumber) {
    final detail = _prDetails[prNumber];
    if (detail == null) return const {};
    final out = <int>{};
    final re = RegExp(
        r'\b(?:closes?|closed|fixes|fixed|resolves?|resolved|addresses?|refs?|references?)\s+#(\d+)',
        caseSensitive: false);
    for (final m in re.allMatches(detail.body)) {
      final n = int.tryParse(m.group(1) ?? '');
      if (n != null) out.add(n);
    }
    return out;
  }

  // ── Filtering / search pipelines ────────────────────────────────────

  bool _prMatchesMine(PullRequestSummary pr) {
    if (_viewerLogin.isEmpty) return false;
    if (pr.authorLogin == _viewerLogin) return true;
    if (pr.assignees.contains(_viewerLogin)) return true;
    if (pr.reviewers.any((r) => r.login == _viewerLogin)) return true;
    return false;
  }

  bool _prMatchesFilters(PullRequestSummary pr) {
    if (_prFilters.contains('MINE') && !_prMatchesMine(pr)) return false;
    if (_prFilters.contains('DRAFTS') && !pr.isDraft) return false;
    if (_prFilters.contains('REVIEW NEEDED')) {
      // PRs awaiting your review specifically. Match either an explicit
      // review-request on you, or a "REVIEW_REQUIRED" decision when the
      // viewer is also a reviewer.
      final youOnDeck = pr.reviewers.any(
          (r) => r.login == _viewerLogin && r.state == 'PENDING');
      if (!youOnDeck) return false;
    }
    if (_prSearch.isNotEmpty) {
      final q = _prSearch.toLowerCase();
      final hay = '${pr.title} ${pr.headRef} ${pr.authorLogin} '
              '${pr.labels.join(' ')}'
          .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  bool _issueMatchesFilters(IssueSummary issue) {
    if (_issueFilters.contains('MINE')) {
      final mine = issue.authorLogin == _viewerLogin ||
          issue.assignees.contains(_viewerLogin);
      if (!mine) return false;
    }
    if (_issueFilters.contains('UNASSIGNED') && issue.assignees.isNotEmpty) {
      return false;
    }
    if (_issueFilters.contains('BUGS') &&
        !issue.labels.any((l) => l.toLowerCase().contains('bug'))) {
      return false;
    }
    if (_issueSearch.isNotEmpty) {
      final q = _issueSearch.toLowerCase();
      final hay = '${issue.title} ${issue.authorLogin} '
              '${issue.labels.join(' ')}'
          .toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  // ── Detail loading ──────────────────────────────────────────────────

  /// Two modes:
  ///   * full=true (default; user expanded a PR) — fetches body, files,
  ///     comments AND `gh pr diff`. The diff alone can be megabytes
  ///     and parses in a worker isolate to keep the UI responsive.
  ///   * full=false (background prefetch) — skips the diff fetch +
  ///     parse entirely. Body / files / comments still warm the cache,
  ///     so when the user expands the PR the metadata is instant; only
  ///     the diff section then needs to load. Stops the prefetch from
  ///     piling up many concurrent megabyte-scale parses, which was
  ///     the actual freeze.
  Future<void> _ensurePrDetailLoaded(
    String repoPath,
    int prNumber, {
    bool full = true,
  }) async {
    final cached = _prDetails[prNumber];
    if (_prDetailsLoading.contains(prNumber)) return;
    // If we've cached metadata-only and the caller wants the full
    // version, drop the cache so we re-fetch with the diff this time.
    if (cached != null && (!full || cached.diff.isNotEmpty)) return;
    setState(() => _prDetailsLoading.add(prNumber));
    final r = await pullRequestDetail(repoPath, prNumber, includeDiff: full);
    if (!mounted) return;
    setState(() {
      _prDetailsLoading.remove(prNumber);
      if (r.ok) {
        _prDetails[prNumber] = r.data!;
        if (r.data!.files.isNotEmpty &&
            !_activeFileByPr.containsKey(prNumber)) {
          _activeFileByPr[prNumber] = r.data!.files.first.path;
        }
        _invalidatePrDerivations();
      }
    });
  }

  /// One git scan per file → both authors AND thermal heat.
  /// Capped to the top-12 most-changed files so sprawling PRs don't
  /// issue 100+ git logs.
  Future<void> _ensurePrFileSignalsLoaded(
      String repoPath, int prNumber) async {
    if (_prFileSignals.containsKey(prNumber) ||
        _prFileSignalsLoading.contains(prNumber)) return;
    final detail = _prDetails[prNumber];
    if (detail == null || detail.files.isEmpty) return;
    final paths = ([...detail.files]
          ..sort((a, b) =>
              (b.additions + b.deletions).compareTo(a.additions + a.deletions)))
        .take(12)
        .map((f) => f.path)
        .toList();
    setState(() => _prFileSignalsLoading.add(prNumber));
    final r = await scanFileSignals(repoPath, paths);
    if (!mounted) return;
    setState(() {
      _prFileSignalsLoading.remove(prNumber);
      _prFileSignals[prNumber] = r.ok ? r.data! : FileSignals.empty;
    });
  }

  Future<void> _ensureIssueDetailLoaded(
      String repoPath, int issueNumber) async {
    if (_issueDetails.containsKey(issueNumber) ||
        _issueDetailsLoading.contains(issueNumber)) {
      return;
    }
    setState(() => _issueDetailsLoading.add(issueNumber));
    final r = await issueDetail(repoPath, issueNumber);
    if (!mounted) return;
    setState(() {
      _issueDetailsLoading.remove(issueNumber);
      if (r.ok) {
        _issueDetails[issueNumber] = r.data!;
      }
    });
  }

  // ── Action handlers ─────────────────────────────────────────────────

  Future<void> _runPrAction(
    String repoPath,
    int number,
    Future<GitResult<void>> Function() op, {
    bool refreshSummary = true,
    bool refreshDetail = true,
  }) async {
    if (_actionInFlight.contains(number)) return;
    setState(() => _actionInFlight.add(number));
    final r = await op();
    if (!mounted) return;
    setState(() => _actionInFlight.remove(number));
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    // Per-row refresh: re-fetch JUST this PR's summary + detail in
    // parallel rather than re-running `gh pr list`. For a repo with
    // many open PRs that's roughly a 50× saving on action latency,
    // and the in-place patch keeps the focused-row index stable so
    // the user doesn't lose their place after merge / approve / etc.
    final fetches = <Future<void>>[];
    if (refreshDetail) {
      _prDetails.remove(number);
      _prChecks.remove(number);
      _invalidatePrDerivations();
      fetches.add(_ensurePrDetailLoaded(repoPath, number));
      fetches.add(_ensureChecksLoaded(repoPath, number));
    }
    if (refreshSummary) {
      fetches.add(_refreshPrSummary(repoPath, number));
    }
    await Future.wait(fetches);
  }

  /// Patch the cached summary for a single PR (vs full list refetch).
  /// If the action closed/merged the PR and it's no longer "open", the
  /// row stays in `_prs` reflecting its new state — we don't surgically
  /// remove because the user may want to see "just merged" feedback.
  /// Next manual ✦ refresh trims it.
  Future<void> _refreshPrSummary(String repoPath, int number) async {
    final r = await getPullRequestSummary(repoPath, number);
    if (!mounted || !r.ok || _prs == null) return;
    final updated = r.data!;
    final i = _prs!.indexWhere((p) => p.number == number);
    if (i < 0) return;
    setState(() {
      _prs![i] = updated;
    });
  }

  Future<void> _runIssueAction(
    String repoPath,
    int number,
    Future<GitResult<void>> Function() op, {
    bool refreshSummary = true,
    bool refreshDetail = true,
  }) async {
    if (_actionInFlight.contains(number)) return;
    setState(() => _actionInFlight.add(number));
    final r = await op();
    if (!mounted) return;
    setState(() => _actionInFlight.remove(number));
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    final fetches = <Future<void>>[];
    if (refreshDetail) {
      _issueDetails.remove(number);
      fetches.add(_ensureIssueDetailLoaded(repoPath, number));
    }
    if (refreshSummary) {
      fetches.add(_refreshIssueSummary(repoPath, number));
    }
    await Future.wait(fetches);
  }

  Future<void> _refreshIssueSummary(String repoPath, int number) async {
    final r = await getIssueSummary(repoPath, number);
    if (!mounted || !r.ok || _issues == null) return;
    final updated = r.data!;
    final i = _issues!.indexWhere((it) => it.number == number);
    if (i < 0) return;
    setState(() {
      _issues![i] = updated;
    });
  }

  Future<void> _checkoutPr(String repoPath, int number) async {
    await _runPrAction(repoPath, number, () => checkoutPullRequest(repoPath, number),
        refreshDetail: false);
    if (!mounted) return;
    // Spatial migration cue: pull a fresh branches list so the new
    // checkout reflects in the BRANCHES lens count + when the user
    // taps over to that lens, it's already there.
    await _load(repoPath);
    if (!mounted) return;
    await context.read<RepositoryState>().refreshStatus();
  }

  // ── Keyboard navigation ─────────────────────────────────────────────

  KeyEventResult _onLensKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repoPath = _lastRepo;
    if (repoPath == null) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.slash) {
      // Shift+/ on most layouts emits `?`. Treat it as the help toggle;
      // bare `/` focuses the search field via its own FocusNode.
      if (HardwareKeyboard.instance.isShiftPressed) {
        setState(() => _showKeyboardHelp = !_showKeyboardHelp);
      } else {
        setState(() {});
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit1) {
      _switchLens(_BranchesLens.branches, repoPath);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.digit2) {
      _switchLens(_BranchesLens.prs, repoPath);
      return KeyEventResult.handled;
    }
    // `3` removed — issues are no longer a separate lens; they live
    // as a side panel inside the PR view.

    if (_lens == _BranchesLens.prs && _prs != null) {
      final visible = _prs!.where(_prMatchesFilters).toList();
      if (visible.isEmpty) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyJ ||
          key == LogicalKeyboardKey.arrowDown) {
        setState(() => _focusedPrIndex =
            ((_focusedPrIndex ?? -1) + 1).clamp(0, visible.length - 1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyK ||
          key == LogicalKeyboardKey.arrowUp) {
        setState(() => _focusedPrIndex =
            ((_focusedPrIndex ?? visible.length) - 1)
                .clamp(0, visible.length - 1));
        return KeyEventResult.handled;
      }
      if (_focusedPrIndex != null) {
        final pr = visible[_focusedPrIndex!];
        if (key == LogicalKeyboardKey.enter) {
          setState(() {
            _expandedPrNumber =
                _expandedPrNumber == pr.number ? null : pr.number;
          });
          if (_expandedPrNumber != null) {
            _ensureChecksLoaded(repoPath, pr.number);
            _ensurePrDetailLoaded(repoPath, pr.number)
                .then((_) => _ensurePrFileSignalsLoaded(repoPath, pr.number));
          }
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyC) {
          _checkoutPr(repoPath, pr.number);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyA) {
          _runPrAction(repoPath, pr.number,
              () => submitPrReview(repoPath, pr.number, event: 'approve'));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyR) {
          _runPrAction(
              repoPath,
              pr.number,
              () => submitPrReview(repoPath, pr.number,
                  event: 'request-changes',
                  body: '(requested changes from Manifold)'));
          return KeyEventResult.handled;
        }
      }
    } else if (_lens == _BranchesLens.issues && _issues != null) {
      final visible = _issues!.where(_issueMatchesFilters).toList();
      if (visible.isEmpty) return KeyEventResult.ignored;
      if (key == LogicalKeyboardKey.keyJ ||
          key == LogicalKeyboardKey.arrowDown) {
        setState(() => _focusedIssueIndex =
            ((_focusedIssueIndex ?? -1) + 1).clamp(0, visible.length - 1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyK ||
          key == LogicalKeyboardKey.arrowUp) {
        setState(() => _focusedIssueIndex =
            ((_focusedIssueIndex ?? visible.length) - 1)
                .clamp(0, visible.length - 1));
        return KeyEventResult.handled;
      }
      if (_focusedIssueIndex != null) {
        final issue = visible[_focusedIssueIndex!];
        if (key == LogicalKeyboardKey.enter) {
          setState(() {
            _expandedIssueNumber =
                _expandedIssueNumber == issue.number ? null : issue.number;
          });
          if (_expandedIssueNumber != null) {
            _ensureIssueDetailLoaded(repoPath, issue.number);
          }
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _createBranch(String repo) async {
    final name = _newBranchCtrl.text.trim();
    if (name.isEmpty || _actionRunning) return;
    setState(() {
      _actionRunning = true;
      _actionError = null;
    });
    final r = await createBranch(repo, name, from: 'HEAD');
    if (!mounted) return;
    setState(() => _actionRunning = false);
    if (!r.ok) {
      setState(() => _actionError = r.error);
      return;
    }
    _newBranchCtrl.clear();
    await _load(repo);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final repo = context.watch<RepositoryState>();
    final repoPath = repo.activePath;

    if (repoPath == null) {
      return const AppStatusView.noRepository();
    }

    if (_lastRepo != repoPath) {
      _lastRepo = repoPath;
      _newBranchCtrl.clear();
      _actionError = null;
      _actionRunning = false;
      // Drop lens caches on repo switch so the new repo doesn't briefly
      // show the previous repo's PRs/issues. ghStatus is also re-probed
      // because a repo without a remote may not work even when gh is
      // installed and authed for the global user.
      _prs = null;
      _issues = null;
      _prChecks.clear();
      _prChecksLoading.clear();
      _prDetails.clear();
      _prDetailsLoading.clear();
      _invalidatePrDerivations();
      _hoveredPrNumber.value = null;
      _issueDetails.clear();
      _issueDetailsLoading.clear();
      _activeFileByPr.clear();
      _actionInFlight.clear();
      _prFileSignals.clear();
      _prFileSignalsLoading.clear();
      _expandedPrNumber = null;
      _expandedIssueNumber = null;
      _focusedPrIndex = null;
      _focusedIssueIndex = null;
      _prFilters.clear();
      _issueFilters.clear();
      _prSearch = '';
      _issueSearch = '';
      _prSearchCtrl.clear();
      _issueSearchCtrl.clear();
      _ghStatus = null;
      _viewerLogin = '';
      _prsError = null;
      _issuesError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load(repoPath));
    }

    if (_loading && _branches.isEmpty) {
      return const AppStatusView.loading(
        title: 'Loading branches',
        message: 'Reading local branches and tags.',
      );
    }

    if (_error != null && _branches.isEmpty) {
      return AppStatusView.error(
        title: 'Branches unavailable',
        message: _error!,
      );
    }

    return Focus(
      focusNode: _lensFocusNode,
      autofocus: true,
      onKeyEvent: _onLensKey,
      child: Stack(children: [
        Column(children: [
      // Lens ribbon — three modes share this tab.
      _LensRibbon(
        active: _lens,
        branchCount: _branches.length,
        prCount: _prs?.length,
        issueCount: _issues?.length,
        refreshing: _loading || _prsLoading || _issuesLoading,
        onChanged: (lens) => _switchLens(lens, repoPath),
        onRefresh: () => _refreshActiveLens(repoPath),
        onToggleHelp: () =>
            setState(() => _showKeyboardHelp = !_showKeyboardHelp),
        onImportPatch: () => _importPatch(repoPath),
      ),
      // Filter row — appears only on PR/Issue lenses; pills latch on
      // click. Search box on the same line.
      if (_lens == _BranchesLens.prs)
        _FilterRow(
          searchCtrl: _prSearchCtrl,
          searchHint: 'filter pull requests…',
          onSearchChanged: (v) => setState(() => _prSearch = v),
          pills: [
            (
              'MINE',
              _prs == null
                  ? null
                  : _prs!.where(_prMatchesMine).length,
              _prFilters.contains('MINE'),
            ),
            ('DRAFTS', null, _prFilters.contains('DRAFTS')),
            (
              'REVIEW NEEDED',
              null,
              _prFilters.contains('REVIEW NEEDED'),
            ),
          ],
          onTogglePill: (label) {
            setState(() {
              if (_prFilters.contains(label)) {
                _prFilters.remove(label);
              } else {
                _prFilters.add(label);
              }
              _focusedPrIndex = null;
            });
          },
        ),
      if (_lens == _BranchesLens.issues)
        _FilterRow(
          searchCtrl: _issueSearchCtrl,
          searchHint: 'filter issues…',
          onSearchChanged: (v) => setState(() => _issueSearch = v),
          pills: [
            ('MINE', null, _issueFilters.contains('MINE')),
            ('UNASSIGNED', null, _issueFilters.contains('UNASSIGNED')),
            ('BUGS', null, _issueFilters.contains('BUGS')),
          ],
          onTogglePill: (label) {
            setState(() {
              if (_issueFilters.contains(label)) {
                _issueFilters.remove(label);
              } else {
                _issueFilters.add(label);
              }
              _focusedIssueIndex = null;
            });
          },
        ),

      if (_lens == _BranchesLens.branches && _error != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!,
              style: TextStyle(color: t.stateConflicted, fontSize: 11)),
        ),

      // Body — switched by lens. AnimatedSwitcher fades between lenses
      // using the active theme's motion shader (snappy / fluid /
      // elastic), so the transition feels native to each theme. The
      // morph between specific row identities (branches that have PRs
      // → PR rows in place) is a v2 enrichment; for v1 a clean fade
      // already sells the lens metaphor while keeping the per-lens
      // surfaces unrelated in code.
      Expanded(
        child: AnimatedSwitcher(
          duration: context.motion(context.surfaceShader.duration),
          switchInCurve: context.surfaceShader.safeCurve,
          switchOutCurve: context.surfaceShader.safeCurve,
          child: KeyedSubtree(
            key: ValueKey(_lens),
            child: switch (_lens) {
              _BranchesLens.branches => _buildBranchesBody(t, repoPath),
              _BranchesLens.prs => _buildPullRequestsBody(t, repoPath),
              _BranchesLens.issues => _buildIssuesBody(t, repoPath),
            },
          ),
        ),
      ),
        ]),
        // Keyboard help overlay — translucent veneer that slides over
        // the lens body. Dismisses on any pointer-down or `?` toggle.
        if (_showKeyboardHelp)
          Positioned.fill(
            child: _KeyboardHelpOverlay(
              onDismiss: () => setState(() => _showKeyboardHelp = false),
            ),
          ),
      ]),
    );
  }

  Widget _buildBranchesBody(AppTokens t, String repoPath) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Left: branch list + tags
        Expanded(
            child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Branch list (the lens ribbon already says "BRANCHES" —
            // a second "Repository Branches" header here was redundant
            // chrome).
            ...(_branches.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _BranchCard(
                    branch: b,
                    tokens: t,
                    actionRunning: _actionRunning,
                    onCheckout:
                        b.current ? null : () => _checkout(repoPath, b.name),
                    onDelete: b.current
                        ? null
                        : ({bool force = false}) =>
                            _deleteBranch(repoPath, b.name, force: force),
                  ),
                ))),

            // Tags section
            if (_tags.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
                child: Row(children: [
                  Expanded(
                      child: Divider(
                          color: t.chromeBorder.withValues(alpha: 0.15),
                          height: 1,
                          thickness: 1)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(children: [
                      AppIcon(name: 'tag', size: 12, color: t.textMuted),
                      const SizedBox(width: 6),
                      Text('Tags',
                          style: TextStyle(
                              color: t.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.08)),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: t.chromeBorder.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${_tags.length}',
                            style: TextStyle(
                                color: t.textMuted,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ),
                    ]),
                  ),
                  Expanded(
                      child: Divider(
                          color: t.chromeBorder.withValues(alpha: 0.15),
                          height: 1,
                          thickness: 1)),
                ]),
              ),
              ...(_tags.map((tag) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _TagCard(
                      tag: tag,
                      tokens: t,
                      hovered: _hoveredTag == tag.name,
                      actionRunning: _actionRunning,
                      onHoverChange: (v) =>
                          setState(() => _hoveredTag = v ? tag.name : null),
                      onDelete: () => _deleteTag(repoPath, tag.name),
                    ),
                  ))),
            ],
            if (_tags.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                    child: Text('No tags yet',
                        style: TextStyle(color: t.textMuted, fontSize: 11))),
              ),
          ]),
        )),

        // Right: Create Branch sidebar (240px)
        MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: 0,
          border: Border(
            left: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
          ),
          elevated: false,
          width: 240,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Create New Branch',
                        style: TextStyle(
                            color: t.textStrong,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    // Branch name input
                    Focus(
                      onKeyEvent: (node, event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter) {
                          _createBranch(repoPath);
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AppTextField(
                        controller: _newBranchCtrl,
                        height: 34,
                        fontSize: 12,
                        hintText: 'Branch name (e.g. feature/auth)',
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Create button
                    SizedBox(
                      height: 26,
                      child: _ChromeButton(
                        label: 'Create branch from HEAD',
                        enabled: !(_newBranchCtrl.text.trim().isEmpty ||
                            _actionRunning),
                        onPressed: (_newBranchCtrl.text.trim().isEmpty ||
                                _actionRunning)
                            ? null
                            : () => _createBranch(repoPath),
                      ),
                    ),
                    // Action error
                    if (_actionError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: t.stateConflicted.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(
                                context.surfaceShader.geometry.pillRadius),
                            border: Border.all(
                                color: t.stateConflicted.withValues(alpha: 0.2)),
                          ),
                          child: Text(_actionError!,
                              style: TextStyle(
                                  color: t.stateConflicted, fontSize: 11)),
                        ),
                      ),
                  ]),
            ),
          ]),
        ),
      ]);
  }

  // ── PRs lens body ───────────────────────────────────────────────────

  Widget _buildPullRequestsBody(AppTokens t, String repoPath) {
    final status = _ghStatus;
    if (_prsLoading && (_prs == null || _prs!.isEmpty)) {
      return _LensLoadingNotice(label: 'Reading pull requests…');
    }
    if (status != null && !status.usable) {
      return _GhMissingNotice(status: status);
    }
    final allPrs = _prs ?? const <PullRequestSummary>[];
    if (allPrs.isEmpty) {
      return _LensEmptyNotice(
        primary: 'No open pull requests',
        secondary: _prsError ?? 'Open one from a branch and it lands here.',
      );
    }
    final prs = allPrs.where(_prMatchesFilters).toList();
    final mainColumn = prs.isEmpty
        ? _LensEmptyNotice(
            primary: 'No PRs match these filters',
            secondary: 'Toggle filters off in the row above.',
          )
        // Deliberately NOT a ListView.builder. Each expanded PR row
        // embeds a same-axis scrollable (the diff), and nesting two
        // ListViews on the same axis fights the gesture arena. The
        // SingleChildScrollView owns scrolling here so the inner diff
        // can scroll cleanly. Cost: PR rows build eagerly; fine at
        // realistic open-PR counts (<50).
        : SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _bucketedPrChildren(repoPath, prs, t),
            ),
          );
    // Issues sidebar — same structural slot as the branches view's
    // "Create New Branch" panel. Slides away when a PR is expanded so
    // the focused PR claims full width; comes back when the PR
    // collapses. AnimatedSize via the theme shader so the transition
    // matches the rest of the surface.
    final showIssuesPanel = _expandedPrNumber == null;
    final shader = context.surfaceShader;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: mainColumn),
        AnimatedSize(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          alignment: Alignment.centerLeft,
          child: showIssuesPanel
              ? _buildIssuesSidePanel(t, repoPath)
              : const SizedBox(width: 0, height: 0),
        ),
      ],
    );
  }

  /// Issues sidebar — lives inside the PR view, mirrors the branches
  /// view's right-hand sidebar. Header carries the count + filter
  /// pills; body is a vertical list of cached issues using the same
  /// `_IssueRow` widget so cross-links / actions / markdown comments
  /// all carry through unchanged.
  Widget _buildIssuesSidePanel(AppTokens t, String repoPath) {
    final allIssues = _issues ?? const <IssueSummary>[];
    final issues = allIssues.where(_issueMatchesFilters).toList();
    return MaterialSurface(
      tone: AppMaterialTone.surface1,
      radius: 0,
      border: Border(
        left: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
      ),
      elevated: false,
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Sidebar header — small editorial label + monospace count.
          // Filter pills sit on the line below to keep the title row
          // breathable in the narrow panel.
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: t.chromeBorder.withValues(alpha: 0.15),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'ISSUES',
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${issues.length}',
                      style: TextStyle(
                        color: t.textMuted.withValues(alpha: 0.85),
                        fontSize: 10,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        letterSpacing: 0.4,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 6),
                // Compact filter row inside the panel.
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final pill in const ['MINE', 'UNASSIGNED', 'BUGS'])
                      _FilterPillWidget(
                        label: pill,
                        count: null,
                        isActive: _issueFilters.contains(pill),
                        onTap: () => setState(() {
                          if (_issueFilters.contains(pill)) {
                            _issueFilters.remove(pill);
                          } else {
                            _issueFilters.add(pill);
                          }
                          _focusedIssueIndex = null;
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Body — empty / loading / list, mirroring the main lens
          // empty states but compact for the narrow panel.
          Expanded(
            child: _buildIssuesPanelBody(t, repoPath, issues, allIssues),
          ),
        ],
      ),
    );
  }

  Widget _buildIssuesPanelBody(
    AppTokens t,
    String repoPath,
    List<IssueSummary> filtered,
    List<IssueSummary> all,
  ) {
    if (_ghStatus != null && !_ghStatus!.usable) {
      return _GhMissingNotice(status: _ghStatus!);
    }
    if (_issuesLoading && (_issues == null || _issues!.isEmpty)) {
      return _LensLoadingNotice(label: 'reading issues…');
    }
    if (all.isEmpty) {
      return _LensEmptyNotice(
        primary: 'No open issues',
        secondary: _issuesError ?? '+ new for tracking work and bugs.',
      );
    }
    if (filtered.isEmpty) {
      return _LensEmptyNotice(
        primary: 'Nothing matches',
        secondary: 'Toggle filters off above.',
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < filtered.length; i++)
            _buildIssueRow(repoPath, filtered, i),
        ],
      ),
    );
  }

  /// Sort PRs by `updatedAt` (newest first) and insert thin section
  /// dividers grouping them into aging buckets — `fresh / this week /
  /// older`. Pure visual structure: same rows, but the eye scans the
  /// list as a triage queue. No mode change, no filter. Applies only
  /// when there are enough PRs to make grouping meaningful (>= 4).
  List<Widget> _bucketedPrChildren(
    String repoPath,
    List<PullRequestSummary> prs,
    AppTokens t,
  ) {
    if (prs.length < 4) {
      return [
        for (var i = 0; i < prs.length; i++) _buildPrRow(repoPath, prs, i),
      ];
    }
    final sorted = [...prs]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final now = DateTime.now();
    final fresh = <PullRequestSummary>[];
    final week = <PullRequestSummary>[];
    final older = <PullRequestSummary>[];
    final stalled = <PullRequestSummary>[];
    for (final pr in sorted) {
      final age = now.difference(pr.updatedAt);
      // STALLED — old AND has at least one PENDING reviewer (someone
      // owes a response). The OLDER bucket lies because it counts
      // PRs that simply haven't been touched lately as equal to PRs
      // that are *blocked*. STALLED separates "actually rotting" from
      // "old but progressing." Manager's most-wanted signal.
      final hasPendingReviewer =
          pr.reviewers.any((r) => r.state == 'PENDING');
      if (age.inHours < 24) {
        fresh.add(pr);
      } else if (age.inDays < 7) {
        week.add(pr);
      } else if (age.inDays >= 5 && hasPendingReviewer) {
        stalled.add(pr);
      } else {
        older.add(pr);
      }
    }
    final out = <Widget>[];
    void emitBucket(String label, List<PullRequestSummary> bucket,
        {bool tone = false}) {
      if (bucket.isEmpty) return;
      out.add(_BucketDivider(
        label: label,
        count: bucket.length,
        toneAlarm: tone,
      ));
      for (var i = 0; i < bucket.length; i++) {
        // Resolve original index via reference identity so action
        // handlers still target the right entry in `prs`.
        final origIdx = prs.indexOf(bucket[i]);
        out.add(_buildPrRow(repoPath, prs, origIdx));
      }
    }
    emitBucket('FRESH', fresh);
    emitBucket('THIS WEEK', week);
    emitBucket('STALLED', stalled, tone: true);
    emitBucket('OLDER', older);
    return out;
  }

  Widget _buildPrRow(
      String repoPath, List<PullRequestSummary> prs, int i) {
    final pr = prs[i];
        final expanded = _expandedPrNumber == pr.number;
        final matrix = context
            .watch<FileCouplingState>()
            .matrixFor(repoPath);
        // Local-only signals: working-tree status (for conflict pill)
        // and issues this PR closes (for the LINKS section).
        final repoStatus = context.watch<RepositoryState>().status;
        final detail = _prDetails[pr.number];
        final conflicts = detail == null
            ? const <String>{}
            : _conflictingPaths(detail.files, repoStatus);
        final closesIssues = _issuesReferencedBy(pr.number);
        // Heavy-PR-day signals — derived locally, no extra fetch.
        final collisions =
            _prCollisionMap()[pr.number] ?? const <int>{};
        final isCheckedOut = _isCheckedOut(pr, repoStatus);
        final awaitingMyReview = _awaitingMyReview(pr);
        // Author-queue badge: how many other open PRs share this
        // author. Visualized inline next to their name so a reviewer
        // sees "this contributor is overloaded" instantly.
        final authorQueueCount = (_prs ?? const <PullRequestSummary>[])
            .where((p) => p.authorLogin == pr.authorLogin)
            .length;
        return _PullRequestRow(
          pr: pr,
          viewerLogin: _viewerLogin,
          expanded: expanded,
          focused: _focusedPrIndex == i,
          checks: _prChecks[pr.number],
          checksLoading: _prChecksLoading.contains(pr.number),
          detail: detail,
          detailLoading: _prDetailsLoading.contains(pr.number),
          activeFilePath: _activeFileByPr[pr.number],
          actionInFlight: _actionInFlight.contains(pr.number),
          couplingMatrix: matrix,
          conflictingPaths: conflicts,
          closesIssues: closesIssues,
          collidesWithPrs: collisions,
          collisionTitles: {
            for (final n in collisions)
              n: (_prs ?? const <PullRequestSummary>[])
                      .firstWhere(
                        (p) => p.number == n,
                        orElse: () => pr,
                      )
                      .title,
          },
          collisionSharedFiles: {
            for (final n in collisions) n: _sharedFiles(pr.number, n),
          },
          isCheckedOut: isCheckedOut,
          awaitingMyReview: awaitingMyReview,
          authorQueueCount: authorQueueCount,
          tail: _conversationTail(pr),
          myReviewState: _myReviewStateFor(pr),
          reviewerQueueDepth: _reviewerQueueDepth(),
          hasOverrideScar: _hasOverrideScar(pr),
          fileSignals: _prFileSignals[pr.number],
          fileSignalsLoading: _prFileSignalsLoading.contains(pr.number),
          isUnread: _isUnread(pr),
          filePillsWrap: _filePillsWrap,
          onToggleFilePillsWrap: _toggleFilePillsWrap,
          auroraSourceFile: _auroraSourceFile,
          hoveredPrNotifier: _hoveredPrNumber,
          onJumpToPr: (otherNumber) {
            setState(() {
              _expandedPrNumber = otherNumber;
              _focusedPrIndex =
                  prs.indexWhere((p) => p.number == otherNumber);
            });
            _ensurePrDetailLoaded(repoPath, otherNumber);
            _ensureChecksLoaded(repoPath, otherNumber);
          },
          onJumpToIssue: (issueNumber) {
            // Cross-lens jump: switch to ISSUES, expand the linked one.
            setState(() {
              _lens = _BranchesLens.issues;
              _expandedIssueNumber = issueNumber;
              _expandedPrNumber = null;
            });
            _ensureIssueDetailLoaded(repoPath, issueNumber);
          },
          onTap: () {
            setState(() {
              _expandedPrNumber = expanded ? null : pr.number;
              _focusedPrIndex = i;
            });
            if (!expanded) {
              _ensureChecksLoaded(repoPath, pr.number);
              _ensurePrDetailLoaded(repoPath, pr.number)
                  .then((_) => _ensurePrFileSignalsLoaded(
                      repoPath, pr.number));
              _markPrSeen(pr.number);
            }
          },
          onSelectFile: (path) =>
              setState(() => _activeFileByPr[pr.number] = path),
          onSubmitReview: (event, body) => _runPrAction(
              repoPath,
              pr.number,
              () => submitPrReview(repoPath, pr.number,
                  event: event, body: body)),
          onCheckout: () => _checkoutPr(repoPath, pr.number),
          onMerge: (method, deleteBranch) => _runPrAction(
              repoPath,
              pr.number,
              () => mergePullRequest(repoPath, pr.number,
                  method: method, deleteBranch: deleteBranch)),
          onSecondaryTap: (pos) => _showPrContextMenu(context, pos, pr, repoPath),
        );
  }

  // ── Issues lens body ────────────────────────────────────────────────

  Widget _buildIssuesBody(AppTokens t, String repoPath) {
    final status = _ghStatus;
    if (_issuesLoading && (_issues == null || _issues!.isEmpty)) {
      return _LensLoadingNotice(label: 'Reading issues…');
    }
    if (status != null && !status.usable) {
      return _GhMissingNotice(status: status);
    }
    final allIssues = _issues ?? const <IssueSummary>[];
    if (allIssues.isEmpty) {
      return _LensEmptyNotice(
        primary: 'No open issues',
        secondary: _issuesError ?? 'Track work and bugs without leaving the app.',
      );
    }
    final issues = allIssues.where(_issueMatchesFilters).toList();
    if (issues.isEmpty) {
      return _LensEmptyNotice(
        primary: 'No issues match these filters',
        secondary: 'Toggle filters off in the row above.',
      );
    }
    // Same rationale as `_buildPullRequestsBody`: avoid same-axis
    // scrollable nesting so issue rows that embed scrollable content
    // (reply textfields, future inline diffs) don't fight the parent.
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < issues.length; i++)
            _buildIssueRow(repoPath, issues, i),
        ],
      ),
    );
  }

  Widget _buildIssueRow(
      String repoPath, List<IssueSummary> issues, int i) {
    final issue = issues[i];
    final expanded = _expandedIssueNumber == issue.number;
    // Compute backlinks once per build (cheap; iterates cached PR
    // bodies). When a PR's body says `closes #N`, surface it here as
    // "← addressed by PR #M". Click jumps cross-lens.
    final backlinks = _issueBacklinksFromPrs();
    final addressingPrNumbers = backlinks[issue.number] ?? const <int>{};
    final addressingPrs = (_prs ?? const <PullRequestSummary>[])
        .where((p) => addressingPrNumbers.contains(p.number))
        .toList();
    return _IssueRow(
      issue: issue,
      viewerLogin: _viewerLogin,
      expanded: expanded,
      focused: _focusedIssueIndex == i,
      detail: _issueDetails[issue.number],
      detailLoading: _issueDetailsLoading.contains(issue.number),
      actionInFlight: _actionInFlight.contains(issue.number),
      addressingPrs: addressingPrs,
      onJumpToPr: (prNumber) {
        setState(() {
          _lens = _BranchesLens.prs;
          _expandedPrNumber = prNumber;
          _expandedIssueNumber = null;
        });
        _ensurePrDetailLoaded(repoPath, prNumber);
        _ensureChecksLoaded(repoPath, prNumber);
      },
      onTap: () {
        setState(() {
          _expandedIssueNumber = expanded ? null : issue.number;
          _focusedIssueIndex = i;
        });
        if (!expanded) {
          _ensureIssueDetailLoaded(repoPath, issue.number);
        }
      },
      onAssignSelf: () => _runIssueAction(repoPath, issue.number,
          () => assignSelfToIssue(repoPath, issue.number)),
      onClose: () => _runIssueAction(
          repoPath, issue.number, () => closeIssue(repoPath, issue.number)),
      onComment: (body) => _runIssueAction(repoPath, issue.number,
          () => commentOnIssue(repoPath, issue.number, body)),
      onAddLabel: (label) => _runIssueAction(repoPath, issue.number,
          () => addIssueLabel(repoPath, issue.number, label)),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Lens ribbon
// ────────────────────────────────────────────────────────────────────────

class _LensRibbon extends StatelessWidget {
  final _BranchesLens active;
  final int branchCount;
  final int? prCount;
  final int? issueCount;
  final bool refreshing;
  final ValueChanged<_BranchesLens> onChanged;
  final VoidCallback onRefresh;
  final VoidCallback onToggleHelp;
  final VoidCallback? onImportPatch;

  const _LensRibbon({
    required this.active,
    required this.branchCount,
    required this.prCount,
    required this.issueCount,
    required this.refreshing,
    required this.onChanged,
    required this.onRefresh,
    required this.onToggleHelp,
    this.onImportPatch,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // ISSUES segment dropped — issues now live as a side panel inside
    // the PR view (the way the branches view has a Create New Branch
    // sidebar). Single source of truth for "open intent on the
    // remote" + structural cohesion across the whole tab.
    final segments = [
      ('BRANCHES', branchCount, _BranchesLens.branches),
      ('PRs', prCount, _BranchesLens.prs),
    ];
    return MaterialSurface(
      tone: AppMaterialTone.surface1,
      radius: 0,
      border: Border(
        bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.15)),
      ),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
      child: SizedBox(
        height: 36,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final seg in segments)
              _LensRibbonSegment(
                label: seg.$1,
                count: seg.$2,
                isActive: active == seg.$3,
                onTap: () => onChanged(seg.$3),
              ),
            const Spacer(),
            // Keyboard help glyph — `?` opens the shortcut overlay.
            // Subdued by default; deliberate twin of the refresh glyph
            // (same right-edge gravity, same muted weight).
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggleHelp,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 8),
                  child: Text('?',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 13,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w800,
                      )),
                ),
              ),
            ),
            if (active == _BranchesLens.prs && onImportPatch != null)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onImportPatch,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 8),
                    child: Text('+ patch',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        )),
                  ),
                ),
              ),
            _RefreshGlyph(active: refreshing, onTap: onRefresh),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Filter row — pills + search box, sits under the lens ribbon
// ────────────────────────────────────────────────────────────────────────

/// (label, optional active-count, isActive)
typedef _FilterPill = (String, int?, bool);

class _FilterRow extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String searchHint;
  final ValueChanged<String> onSearchChanged;
  final List<_FilterPill> pills;
  final ValueChanged<String> onTogglePill;

  const _FilterRow({
    required this.searchCtrl,
    required this.searchHint,
    required this.onSearchChanged,
    required this.pills,
    required this.onTogglePill,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MaterialSurface(
      tone: AppMaterialTone.surface0,
      radius: 0,
      border: Border(
        bottom: BorderSide(color: t.chromeBorder.withValues(alpha: 0.1)),
      ),
      elevated: false,
      padding: const EdgeInsets.fromLTRB(16, 6, 12, 6),
      child: Row(
        children: [
          // Search box. `/` focuses it (handled at the lens level, then
          // delegated by the field's own focus). Tiny, monospace, no
          // chrome — disappears into the surface when empty.
          Icon(Icons.search, size: 13, color: t.textMuted),
          const SizedBox(width: 6),
          SizedBox(
            width: 220,
            child: TextField(
              controller: searchCtrl,
              onChanged: onSearchChanged,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                border: InputBorder.none,
                hintText: searchHint,
                hintStyle: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.65),
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          for (final pill in pills)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _FilterPillWidget(
                label: pill.$1,
                count: pill.$2,
                isActive: pill.$3,
                onTap: () => onTogglePill(pill.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterPillWidget extends StatefulWidget {
  final String label;
  final int? count;
  final bool isActive;
  final VoidCallback onTap;
  const _FilterPillWidget({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_FilterPillWidget> createState() => _FilterPillWidgetState();
}

class _FilterPillWidgetState extends State<_FilterPillWidget> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final accent = t.accentBright;
    final bg = widget.isActive
        ? accent.withValues(alpha: _pressed ? 0.28 : 0.18)
        : (_hovered
            ? t.chromeBorder.withValues(alpha: 0.18)
            : t.chromeBorder.withValues(alpha: 0));
    final border = widget.isActive
        ? accent.withValues(alpha: 0.55)
        : t.chromeBorder.withValues(alpha: 0.35);
    final fg = widget.isActive ? accent : t.textMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: border, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Latch indicator — filled circle when active, ring when
              // not. Subtle but the tactile detail matters.
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isActive ? accent : accent.withValues(alpha: 0),
                  border: Border.all(
                    color: widget.isActive ? accent : t.textMuted,
                    width: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: fg,
                  fontSize: 9.5,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              if (widget.count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    color: fg.withValues(alpha: 0.75),
                    fontSize: 9,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Keyboard help overlay
// ────────────────────────────────────────────────────────────────────────

class _KeyboardHelpOverlay extends StatelessWidget {
  final VoidCallback onDismiss;
  const _KeyboardHelpOverlay({required this.onDismiss});

  static const _bindings = <(String, String)>[
    ('j  / k  / ↑ / ↓', 'navigate rows'),
    ('enter', 'expand / collapse focused row'),
    ('c', 'checkout focused PR locally'),
    ('a', 'approve · review'),
    ('r', 'request changes'),
    ('/', 'focus search'),
    ('1  ·  2', 'switch lens (branches · prs)'),
    ('?', 'toggle this overlay'),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDismiss(),
      child: AnimatedContainer(
        duration: context.motion(shader.duration),
        curve: shader.safeCurve,
        color: t.bg0.withValues(alpha: 0.78),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            margin: const EdgeInsets.all(32),
            padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.chromeBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'KEYBOARD',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 14),
                for (final b in _bindings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            b.$1,
                            style: TextStyle(
                              color: t.accentBright,
                              fontSize: 11,
                              fontFamily: 'JetBrainsMono',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            b.$2,
                            style: TextStyle(
                              color: t.textNormal,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 14),
                Text(
                  'press anywhere to dismiss',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LensRibbonSegment extends StatefulWidget {
  final String label;
  final int? count;
  final bool isActive;
  final VoidCallback onTap;

  const _LensRibbonSegment({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_LensRibbonSegment> createState() => _LensRibbonSegmentState();
}

class _LensRibbonSegmentState extends State<_LensRibbonSegment> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final accent = t.accentBright;
    final color = widget.isActive
        ? accent
        : (_hovered ? t.textStrong : t.textNormal);
    final shader = context.surfaceShader;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.only(right: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: widget.isActive
                          ? FontWeight.w700
                          : FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                    child: Text(widget.label),
                  ),
                  const SizedBox(width: 8),
                  AnimatedDefaultTextStyle(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    style: TextStyle(
                      color: widget.isActive
                          ? accent.withValues(alpha: 0.85)
                          : t.textMuted.withValues(alpha: 0.75),
                      fontSize: 10,
                      fontFamily: 'JetBrainsMono',
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 0.4,
                    ),
                    // `·` placeholder until counts have been fetched, so
                    // the segment width doesn't pop on first load.
                    child: Text(widget.count == null ? '·' : '${widget.count}'),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Active underline — animated bottom border. Width tracks
              // the segment's natural width above; we render a 2px line
              // that fades in/out per active state.
              AnimatedContainer(
                duration: context.motion(shader.duration),
                curve: shader.safeCurve,
                height: 2,
                width: widget.isActive ? 28 : 0,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RefreshGlyph extends StatefulWidget {
  final bool active;
  final VoidCallback onTap;
  const _RefreshGlyph({required this.active, required this.onTap});

  @override
  State<_RefreshGlyph> createState() => _RefreshGlyphState();
}

class _RefreshGlyphState extends State<_RefreshGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didUpdateWidget(covariant _RefreshGlyph old) {
    super.didUpdateWidget(old);
    // Spin while refreshing, stop where it lands when done — feels more
    // honest than a fade-out (the work was real, the glyph reports it).
    if (widget.active && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.active && _spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: RotationTransition(
            turns: _spin,
            child: Text(
              '✦',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// PR row — collapsed metric line + expanded workplace
// ────────────────────────────────────────────────────────────────────────

class _PullRequestRow extends StatefulWidget {
  final PullRequestSummary pr;
  final String viewerLogin;
  final bool expanded;
  final bool focused;
  final List<CheckSummary>? checks;
  final bool checksLoading;
  final PullRequestDetail? detail;
  final bool detailLoading;
  final String? activeFilePath;
  final bool actionInFlight;
  final FileCouplingMatrix? couplingMatrix;
  /// Files in the PR that the user currently has uncommitted changes
  /// in. Empty when no overlap. Drives the `⚠ touches N of yours` pill
  /// and the CONFLICTS-WITH-YOU expanded section.
  final Set<String> conflictingPaths;
  /// Issue numbers this PR's body says it closes/fixes/refs. Drives
  /// the LINKS section. Click an entry → cross-lens jump to issues.
  final Set<int> closesIssues;
  final ValueChanged<int> onJumpToIssue;
  /// Other open PRs whose changed files overlap this one. Visualized
  /// as a second hazard strip (orange tone) — distinct from the
  /// red personal-conflict strip — so a maintainer sees inter-PR
  /// merge order risk at a glance.
  final Set<int> collidesWithPrs;
  /// Title of each colliding PR (for the WILL FIGHT inline list and
  /// the strip's tooltip).
  final Map<int, String> collisionTitles;
  /// Shared file paths per colliding PR pair — drives "you'll fight
  /// #138 over 3 files" enumeration in the expanded view.
  final Map<int, Set<String>> collisionSharedFiles;
  /// Lens-level hovered PR notifier. When the value matches another
  /// row's number AND that row collides with this one, this row
  /// renders a sibling-highlight wash. Lets the user *see* the
  /// collision graph by sweeping the mouse across the list.
  final ValueNotifier<int?> hoveredPrNotifier;
  /// Jump cross-row — focus + expand a PR by number. Used by the
  /// inline WILL FIGHT chip clicks.
  final ValueChanged<int> onJumpToPr;
  /// True when the working tree is checked out on this PR's branch.
  /// Promotes the row's left rail to accentBright so "you're on this
  /// one right now" lights up without any new label.
  final bool isCheckedOut;
  /// True when the viewer is a pending reviewer on this PR. Subtle
  /// row-bg accent wash — atmospheric, not a label.
  final bool awaitingMyReview;
  /// How many other open PRs the same author has in flight. Surfaced
  /// inline next to their name when ≥ 2 — "this contributor is
  /// overloaded" signal for reviewers.
  final int authorQueueCount;
  /// Last action on this PR, synthesized from cached comments +
  /// reviews + checks. Drives the conversation-tail glyph at the end
  /// of the metric line so a glance answers "what's current?".
  final TailEvent? tail;
  /// Viewer's own review state. One of:
  /// '' (n/a) | 'pending' | 'approved' | 'changes_requested' |
  /// 'commented'. Renders a distinctive "you ✓" / "your review pending"
  /// pill so engagement vs fresh items separate visually.
  final String myReviewState;
  /// `@reviewer → N` map: how many open PRs each reviewer is pending
  /// on across the whole list. Used by `_PrHeader` to surface the
  /// most-loaded reviewer assigned to this PR as `← @reviewer (N)`,
  /// mirroring the author-queue badge.
  final Map<String, int> reviewerQueueDepth;
  /// True when this PR is MERGED and either had failing checks or no
  /// approved review at merge time. Renders an `⚠ MERGED RED` strip on
  /// the row — incident-mode signal for "who pushed this through?".
  final bool hasOverrideScar;
  /// One-scan-two-signals from local git history: per-author commit
  /// counts (drives PEOPLE section) AND per-file thermal heat (drives
  /// the ember glow on file pills). Null = not yet loaded; empty =
  /// loaded but no signal.
  final FileSignals? fileSignals;
  final bool fileSignalsLoading;
  /// True when `pr.updatedAt` has advanced past the viewer's last
  /// expansion of this PR. Drives the unread dot on the row header.
  final bool isUnread;
  final bool filePillsWrap;
  final VoidCallback onToggleFilePillsWrap;
  final ValueNotifier<String?> auroraSourceFile;
  final VoidCallback onTap;
  /// Right-click on the collapsed row surface. Fires with the global
  /// pointer position so the caller can anchor a context menu to it.
  final ValueChanged<Offset>? onSecondaryTap;
  final ValueChanged<String> onSelectFile;
  final void Function(String event, String body) onSubmitReview;
  final VoidCallback onCheckout;
  final void Function(String method, bool deleteBranch) onMerge;

  const _PullRequestRow({
    required this.pr,
    required this.viewerLogin,
    required this.expanded,
    required this.focused,
    required this.checks,
    required this.checksLoading,
    required this.detail,
    required this.detailLoading,
    required this.activeFilePath,
    required this.actionInFlight,
    required this.couplingMatrix,
    required this.conflictingPaths,
    required this.closesIssues,
    required this.onJumpToIssue,
    required this.collidesWithPrs,
    required this.collisionTitles,
    required this.collisionSharedFiles,
    required this.hoveredPrNotifier,
    required this.onJumpToPr,
    required this.isCheckedOut,
    required this.awaitingMyReview,
    required this.authorQueueCount,
    required this.tail,
    required this.myReviewState,
    required this.reviewerQueueDepth,
    required this.hasOverrideScar,
    required this.fileSignals,
    required this.fileSignalsLoading,
    required this.isUnread,
    required this.filePillsWrap,
    required this.onToggleFilePillsWrap,
    required this.auroraSourceFile,
    required this.onTap,
    this.onSecondaryTap,
    required this.onSelectFile,
    required this.onSubmitReview,
    required this.onCheckout,
    required this.onMerge,
  });

  @override
  State<_PullRequestRow> createState() => _PullRequestRowState();
}

class _PullRequestRowState extends State<_PullRequestRow> {
  bool _hovered = false;

  Color _stateColor(AppTokens t) {
    switch (widget.pr.state) {
      case 'OPEN':
        return widget.pr.isDraft ? t.textMuted : t.accentBright;
      case 'MERGED':
        return t.stateConflicted;
      case 'CLOSED':
        return t.stateDeleted;
      default:
        return t.textMuted;
    }
  }

  String _stateLabel() {
    if (widget.pr.state == 'OPEN' && widget.pr.isDraft) return 'DRAFT';
    return widget.pr.state;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final state = _stateColor(t);
    final railAlpha = widget.expanded || widget.focused
        ? 1.0
        : (_hovered ? 0.85 : 0.55);
    // The toggle GestureDetector wraps ONLY the header + metric line.
    // Wrapping the whole row (including the expanded content) put the
    // diff renderer's per-line GestureDetectors and the action toolbar
    // buttons in gesture-arena contention with the row's onTap, which
    // thrashed every interaction. Scoping the click target keeps the
    // header clickable for expand/collapse while leaving inner widgets
    // (review form, action buttons, diff scroll) sole owners of their
    // own pointer events.
    final hasConflict = widget.conflictingPaths.isNotEmpty;
    final hasCollisions = widget.collidesWithPrs.isNotEmpty;
    final closesCount = widget.closesIssues.length;
    // Active-branch + awaiting-review override the row's visual baseline.
    // - Active = the user is literally on this PR's branch right now;
    //   promote left rail to accentBright and bump alpha so the row
    //   reads as "current focus."
    // - Awaiting review = a subtle accent wash on the row bg so things
    //   waiting on YOU pop without a label.
    final railColor =
        widget.isCheckedOut ? t.accentBright : state;
    final reviewWash = widget.awaitingMyReview
        ? t.accentBright.withValues(alpha: 0.08)
        : t.accentBright.withValues(alpha: 0);
    return ValueListenableBuilder<int?>(
      valueListenable: widget.hoveredPrNotifier,
      builder: (context, hovered, _) {
        // Sibling-highlight: another row is hovered AND it collides
        // with us (or we ARE the hovered one — but that's already
        // handled by `_hovered`). Tinted in `stateConflicted` to
        // match the inter-PR collision strip, so the eye reads
        // "highlighted because of merge-order risk."
        final isSiblingOfHover = hovered != null &&
            hovered != widget.pr.number &&
            widget.collidesWithPrs.contains(hovered);
        return _buildRowFrame(
          context,
          t,
          state,
          shader,
          railAlpha,
          railColor,
          reviewWash,
          hasConflict,
          hasCollisions,
          closesCount,
          isSiblingOfHover,
        );
      },
    );
  }

  Widget _buildRowFrame(
    BuildContext context,
    AppTokens t,
    Color state,
    SurfaceMaterialShader shader,
    double railAlpha,
    Color railColor,
    Color reviewWash,
    bool hasConflict,
    bool hasCollisions,
    int closesCount,
    bool isSiblingOfHover,
  ) {
    return MouseRegion(
      onEnter: (_) {
        setState(() => _hovered = true);
        // Push our number onto the lens-level hovered notifier so any
        // other row that collides with us paints a sibling-highlight.
        widget.hoveredPrNotifier.value = widget.pr.number;
      },
      onExit: (_) {
        setState(() => _hovered = false);
        // Only clear if WE were the most recent hovered — a fast
        // mouse trail across rows shouldn't blip the highlight off
        // when the next row's onEnter has already fired.
        if (widget.hoveredPrNotifier.value == widget.pr.number) {
          widget.hoveredPrNotifier.value = null;
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        // Stack so atmospheric overlays (hazard strip, workline tab)
        // can hang off the row's edges without disturbing flow layout.
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: context.motion(shader.duration),
              curve: shader.safeCurve,
              padding: EdgeInsets.fromLTRB(
                12,
                10,
                closesCount > 0 ? 26 : 12,
                // Reserve room for one or two stacked hazard strips.
                (hasConflict && hasCollisions)
                    ? 16
                    : ((hasConflict || hasCollisions) ? 12 : 10),
              ),
              decoration: BoxDecoration(
                color: widget.expanded
                    ? t.surface1.withValues(alpha: 0.7)
                    : (_hovered || widget.focused
                        ? t.surface1.withValues(alpha: 0.45)
                        : (isSiblingOfHover
                            // Sibling-of-hovered-PR — the user's
                            // mouse is on a row that collides with
                            // us. Tint in collision-orange so the
                            // collision graph reads spatially.
                            ? t.stateConflicted.withValues(alpha: 0.12)
                            // Awaiting-review wash: subtle accent
                            // tint even at rest, so PRs blocking on
                            // YOU pop before any other state.
                            : reviewWash)),
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.cardRadius),
                border: Border(
                  left: BorderSide(
                    // railColor swaps to accentBright when the PR's
                    // branch is currently checked out — "you're on
                    // this PR right now" without a label.
                    color: railColor.withValues(
                        alpha: widget.isCheckedOut
                            ? 1.0
                            : railAlpha),
                    width: widget.focused ||
                            widget.expanded ||
                            widget.isCheckedOut
                        ? 4
                        : 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onTap,
                      onSecondaryTapDown: widget.onSecondaryTap == null
                          ? null
                          : (d) =>
                              widget.onSecondaryTap!(d.globalPosition),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _PrHeader(
                            pr: widget.pr,
                            stateColor: state,
                            label: _stateLabel(),
                            authorQueueCount: widget.authorQueueCount,
                            isCheckedOut: widget.isCheckedOut,
                            isUnread: widget.isUnread,
                            reviewerQueueDepth: widget.reviewerQueueDepth,
                          ),
                          const SizedBox(height: 4),
                          _PrMetricLine(
                            pr: widget.pr,
                            checks: widget.checks,
                            files: widget.detail?.files ?? const [],
                            conflictCount: widget.conflictingPaths.length,
                            closesIssueCount: widget.closesIssues.length,
                            tail: widget.tail,
                            myReviewState: widget.myReviewState,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.actionInFlight)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: _ActionProgressBar(color: t.accentBright),
                    ),
                  AnimatedSize(
                    duration: context.motion(shader.duration),
                    curve: shader.safeCurve,
                    alignment: Alignment.topCenter,
                    child: widget.expanded
                        ? _PrExpanded(
                            pr: widget.pr,
                            viewerLogin: widget.viewerLogin,
                            detail: widget.detail,
                            detailLoading: widget.detailLoading,
                            checks: widget.checks,
                            checksLoading: widget.checksLoading,
                            activeFilePath: widget.activeFilePath,
                            couplingMatrix: widget.couplingMatrix,
                            conflictingPaths: widget.conflictingPaths,
                            closesIssues: widget.closesIssues,
                            onJumpToIssue: widget.onJumpToIssue,
                            collidesWithPrs: widget.collidesWithPrs,
                            collisionTitles: widget.collisionTitles,
                            collisionSharedFiles: widget.collisionSharedFiles,
                            onJumpToPr: widget.onJumpToPr,
                            fileSignals: widget.fileSignals,
                            fileSignalsLoading: widget.fileSignalsLoading,
                            filePillsWrap: widget.filePillsWrap,
                            auroraSourceFile: widget.auroraSourceFile,
                            onToggleFilePillsWrap:
                                widget.onToggleFilePillsWrap,
                            onSelectFile: widget.onSelectFile,
                            onSubmitReview: widget.onSubmitReview,
                            onCheckout: widget.onCheckout,
                            onMerge: widget.onMerge,
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
            // OVERRIDE-SCAR — top-edge band on MERGED PRs that landed
            // with failing checks or no approved review. Different
            // edge from the collision strips so all three signal
            // types coexist visually. Incident-response triage
            // surface: "who pushed this through?" answered at a
            // glance when scrolling closed PRs after a bad deploy.
            if (widget.hasOverrideScar)
              Positioned(
                left: 4,
                right: 4,
                top: 0,
                child: Tooltip(
                  message: 'merged with failing checks or without an '
                      'approving review — investigate first under fire',
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(
                            context.surfaceShader.geometry.tinyRadius),
                        topRight: Radius.circular(
                            context.surfaceShader.geometry.tinyRadius),
                      ),
                      gradient: LinearGradient(
                        colors: [
                          t.stateConflicted.withValues(alpha: 0.0),
                          t.stateConflicted.withValues(alpha: 0.85),
                          t.stateConflicted.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            // Bottom-edge hazard strip(s) — atmospheric collision
            // signals. Two distinct tones for two distinct kinds of
            // collision:
            //   - red `stateDeleted`  = your local uncommitted work
            //     overlaps these files
            //   - orange `stateConflicted` = ANOTHER open PR also
            //     touches these files (merge order matters)
            // Both can coexist; orange stacks just above red so you
            // can see "this is dangerous personally AND for the team".
            if (hasConflict)
              Positioned(
                left: 4,
                right: 4,
                bottom: 0,
                child: _HazardStrip(
                  color: t.stateDeleted,
                  tooltip: '${widget.conflictingPaths.length} '
                      'file${widget.conflictingPaths.length == 1 ? '' : 's'}'
                      ' overlap your uncommitted work',
                ),
              ),
            if (hasCollisions)
              Positioned(
                left: 4,
                right: 4,
                bottom: hasConflict ? 4 : 0,
                child: _HazardStrip(
                  color: t.stateConflicted,
                  // Name the PRs + count of shared files per pair, so
                  // the tooltip is *actionable* — you know exactly
                  // who you'll fight, not just that you'll fight.
                  tooltip: widget.collidesWithPrs
                      .map((n) {
                        final shared = widget.collisionSharedFiles[n] ??
                            const <String>{};
                        return '#$n  '
                            '(${shared.length} '
                            'file${shared.length == 1 ? '' : 's'})';
                      })
                      .join('\n'),
                ),
              ),
            // Right-edge workline connector tab — angled slab carrying
            // the count of issues this PR closes. Click → cross-lens
            // jump (handled by the connector widget itself, which
            // calls onJumpToIssue on the only or the first linked
            // issue when tapped).
            if (closesCount > 0)
              Positioned(
                top: 8,
                bottom: widget.expanded ? null : 8,
                right: 0,
                child: _WorklineConnector(
                  count: closesCount,
                  direction: _WorklineDirection.outgoing,
                  color: t.accentBright,
                  onTap: () =>
                      widget.onJumpToIssue(widget.closesIssues.first),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrHeader extends StatelessWidget {
  final PullRequestSummary pr;
  final Color stateColor;
  final String label;
  /// Number of OPEN PRs the same author has in flight (this PR + others).
  /// Renders as `(N)` after the @login when ≥ 2.
  final int authorQueueCount;
  /// Renders a small `▶` glyph before the # when this PR's branch is the
  /// working tree's current head.
  final bool isCheckedOut;
  /// Renders a small unread-dot before the # when the PR has had
  /// activity since the viewer last expanded its detail.
  final bool isUnread;
  /// Per-reviewer queue depth across all open PRs. Used to surface
  /// "your reviewer is buried" — when the most-loaded PENDING
  /// reviewer assigned here has ≥ 3 other open requests, append
  /// `← @bob (5)` after the author/queue line. Mirror of the
  /// existing author-queue badge.
  final Map<String, int> reviewerQueueDepth;
  const _PrHeader({
    required this.pr,
    required this.stateColor,
    required this.label,
    required this.authorQueueCount,
    required this.isCheckedOut,
    required this.isUnread,
    required this.reviewerQueueDepth,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (isCheckedOut)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    '▶',
                    style: TextStyle(
                      color: t.accentBright,
                      fontSize: 9,
                      height: 1,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (isUnread)
                Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: t.accentBright,
                    ),
                  ),
                ),
              Text(
                '#${pr.number}',
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pr.title.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: t.textStrong,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 3),
              Builder(builder: (context) {
                // Surface the most-loaded PENDING reviewer assigned
                // to this PR. Threshold ≥ 3 so it only appears when
                // someone is *actually* buried — not for a normal
                // single-PR review request.
                MapEntry<String, int>? heaviest;
                for (final r in pr.reviewers) {
                  if (r.state != 'PENDING') continue;
                  final n = reviewerQueueDepth[r.login] ?? 0;
                  if (n < 3) continue;
                  if (heaviest == null || n > heaviest.value) {
                    heaviest = MapEntry(r.login, n);
                  }
                }
                return Text.rich(
                  TextSpan(
                    style: TextStyle(
                      color: t.textMuted,
                      fontSize: 10.5,
                      fontFamily: 'JetBrainsMono',
                      letterSpacing: 0.1,
                    ),
                    children: [
                      TextSpan(text: '${pr.headRef} → ${pr.baseRef} · '),
                      TextSpan(text: '@${pr.authorLogin}'),
                      if (authorQueueCount >= 2)
                        TextSpan(
                          text: ' ($authorQueueCount)',
                          style: TextStyle(
                            color: t.textMuted.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (heaviest != null) ...[
                        TextSpan(
                          text: '  ←  @${heaviest.key} (${heaviest.value})',
                          style: TextStyle(
                            // Reviewer queue uses stateConflicted
                            // (orange) so it visually distinguishes
                            // from author queue's neutral muted —
                            // "your reviewer is at risk" reads as
                            // mild alarm, not the same flavor as
                            // "this author is busy."
                            color:
                                t.stateConflicted.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              }),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(left: 8, top: 1),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: stateColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.badgeRadius),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: stateColor,
              fontSize: 9,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}

/// Aging-bucket section divider — hairline rule + small editorial
/// label + monospace count. Used inside the PR list to break the
/// stream into `fresh / this week / older` so the eye reads the queue
/// as triageable groups instead of one long chronological flow.
class _BucketDivider extends StatelessWidget {
  final String label;
  final int count;
  /// When true, the divider's label + rule render in the alarm
  /// (`stateConflicted`) tone — used for STALLED so the rotting
  /// pile reads at a glance as "needs attention," distinct from
  /// the neutral aging buckets.
  final bool toneAlarm;
  const _BucketDivider({
    required this.label,
    required this.count,
    this.toneAlarm = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final labelColor = toneAlarm
        ? t.stateConflicted.withValues(alpha: 0.85)
        : t.textMuted.withValues(alpha: 0.85);
    final ruleColor = toneAlarm
        ? t.stateConflicted.withValues(alpha: 0.4)
        : t.chromeBorder.withValues(alpha: 0.2);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(
              color: labelColor.withValues(alpha: 0.7),
              fontSize: 9,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: ruleColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// "My review state" pill — engagement-level state for the viewer
/// specifically, distinct from anonymous reviewer-dots. Tints by
/// state so the eye reads "I'm involved here AND in what way."
class _MyReviewPill extends StatelessWidget {
  final String state;
  const _MyReviewPill({required this.state});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (label, color) = switch (state) {
      'pending' => ('your review pending', t.accentBright),
      'approved' => ('you ✓', t.accentBright),
      'changes_requested' =>
        ('you ✗ requested changes', t.stateConflicted),
      'commented' => ('you commented', t.textNormal),
      _ => ('you', t.textMuted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(
            context.surfaceShader.geometry.badgeRadius),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9.5,
          fontFamily: 'JetBrainsMono',
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// Conversation-tail pill — single-glyph "what's currently true on
/// this PR?". A tiny kind-glyph + (optional) actor + relative time.
/// Drives the heavy-PR-day question "what should I look at" without
/// expanding anything.
class _ConversationTailPill extends StatelessWidget {
  final TailEvent? tail;
  final DateTime fallbackAt;
  final int conversationCount;
  const _ConversationTailPill({
    required this.tail,
    required this.fallbackAt,
    required this.conversationCount,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mono = TextStyle(
      color: t.textMuted,
      fontSize: 10,
      fontFamily: 'JetBrainsMono',
      letterSpacing: 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (tail == null) {
      return Text(_relativeTime(fallbackAt), style: mono);
    }
    final ev = tail!;
    final (glyph, color) = _glyphFor(t, ev);
    final actor = ev.actor.isNotEmpty ? ' @${ev.actor}' : '';
    // Conversation count only annotates when there's actual back-and-
    // forth (≥ 2 — a single comment doesn't make a conversation).
    // Reads as `💬 alice · 4h · 3` — last beat + total beats. One
    // block, two pieces of information.
    final convSuffix =
        conversationCount >= 2 ? ' · $conversationCount' : '';
    return Tooltip(
      message: switch (ev.kind) {
        'comment' => conversationCount >= 2
            ? '$conversationCount comments · last from author shown'
            : 'last comment',
        'review' => ev.state.isNotEmpty
            ? 'last review · ${ev.state.toLowerCase()}'
            : 'last review',
        'check' => 'last check · ${ev.state}',
        'push' => 'last commit',
        _ => 'last activity',
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            glyph,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            '$actor · ${_relativeTime(ev.at)}$convSuffix',
            style: mono,
          ),
        ],
      ),
    );
  }

  (String, Color) _glyphFor(AppTokens t, TailEvent e) {
    switch (e.kind) {
      case 'comment':
        return ('💬', t.textNormal);
      case 'review':
        if (e.state == 'CHANGES_REQUESTED') return ('✗', t.stateDeleted);
        if (e.state == 'APPROVED') return ('✓', t.accentBright);
        return ('●', t.textNormal);
      case 'check':
        if (e.state == 'fail' || e.state == 'failure') {
          return ('×', t.stateDeleted);
        }
        if (e.state == 'pass' || e.state == 'success') {
          return ('✓', t.accentBright);
        }
        return ('●', t.textMuted);
      case 'push':
        return ('↑', t.accentBright);
      default:
        return ('●', t.textMuted);
    }
  }
}

/// Bottom-edge hazard strip — hairline gradient that reads as part of
/// the row's chrome, not a label. Two callers stack two strips for
/// two distinct collision senses (you-vs-pr and pr-vs-pr).
class _HazardStrip extends StatelessWidget {
  final Color color;
  final String tooltip;
  const _HazardStrip({required this.color, required this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(
              context.surfaceShader.geometry.tinyRadius)),
          gradient: LinearGradient(
            colors: [
              color.withValues(alpha: 0.0),
              color.withValues(alpha: 0.65),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

/// Diff sparkline. Replaces `+N -M` text with a horizontal stacked bar
/// where each segment is a file in the PR. Segment width tracks the
/// file's churn share; a vertical green/red split inside each segment
/// shows that file's add vs delete proportion. Reads as the *shape*
/// of the change at a glance — eye finds where the mass is before the
/// brain reads anything. Falls back to a single bar when per-file
/// detail isn't cached yet.
class _DiffSparkline extends StatelessWidget {
  final PullRequestSummary pr;
  final List<PrFile> files;
  final Color addedColor;
  final Color deletedColor;
  final Color emptyColor;
  const _DiffSparkline({
    required this.pr,
    required this.files,
    required this.addedColor,
    required this.deletedColor,
    required this.emptyColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mono = TextStyle(
      color: t.textMuted,
      fontSize: 9,
      fontFamily: 'JetBrainsMono',
      letterSpacing: 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
      fontWeight: FontWeight.w700,
    );
    // Width budget: ~88 px caps the sparkline so it doesn't crowd the
    // metric line. Height intentionally tall enough (8 px) for the
    // green/red vertical split to read at glance distance.
    const barWidth = 88.0;
    const barHeight = 8.0;
    final hasFiles = files.isNotEmpty;
    final tooltipLines = hasFiles
        ? files.map((f) => '${f.path}  +${f.additions} -${f.deletions}')
        : ['${pr.changedFiles} '
            'file${pr.changedFiles == 1 ? '' : 's'}'];
    return Tooltip(
      message: tooltipLines.join('\n'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // The bar itself — a row of file segments, each a tiny green/
          // red column. A 1px white-line bottom track gives it a sense
          // of being a chart, not just a colored stripe.
          ClipRRect(
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.tinyRadius),
            child: SizedBox(
              width: barWidth,
              height: barHeight,
              child: hasFiles
                  ? CustomPaint(
                      painter: _DiffSparkPainter(
                        files: files,
                        addedColor: addedColor,
                        deletedColor: deletedColor,
                        emptyColor: emptyColor,
                      ),
                    )
                  : _SimpleSplitBar(
                      additions: pr.additions,
                      deletions: pr.deletions,
                      addedColor: addedColor,
                      deletedColor: deletedColor,
                      emptyColor: emptyColor,
                    ),
            ),
          ),
          const SizedBox(width: 6),
          // Tiny mono numerals to anchor the visual — pros want the
          // exact counts, the bar's the at-a-glance.
          Text('+${pr.additions}', style: mono.copyWith(color: addedColor)),
          const SizedBox(width: 2),
          Text('-${pr.deletions}',
              style: mono.copyWith(color: deletedColor)),
        ],
      ),
    );
  }
}

class _DiffSparkPainter extends CustomPainter {
  final List<PrFile> files;
  final Color addedColor;
  final Color deletedColor;
  final Color emptyColor;
  _DiffSparkPainter({
    required this.files,
    required this.addedColor,
    required this.deletedColor,
    required this.emptyColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final totals = files
        .map((f) => f.additions + f.deletions)
        .fold<int>(0, (a, b) => a + b)
        .clamp(1, 1 << 30);
    var x = 0.0;
    final paint = Paint();
    // Background — an empty track so files with zero changes still
    // sit visibly on a base line.
    paint.color = emptyColor;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
    for (final f in files) {
      final churn = f.additions + f.deletions;
      if (churn == 0) continue;
      final w = (churn / totals) * size.width;
      // Each segment splits vertically: top = additions share, bottom
      // = deletions share. So a file that's 80% adds shows mostly
      // green with a thin red bottom; a delete-heavy file shows the
      // opposite. The eye reads the *direction* of churn per file.
      final addRatio = f.additions / churn;
      final addH = size.height * addRatio;
      paint.color = addedColor;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, addH), paint);
      paint.color = deletedColor;
      canvas.drawRect(
          Rect.fromLTWH(x, addH, w, size.height - addH), paint);
      x += w;
      // 1px gap between segments so individual files read as
      // distinct rather than fusing into one stripe.
      paint.color = emptyColor.withValues(alpha: 0.0);
      x += 1;
    }
  }

  @override
  bool shouldRepaint(_DiffSparkPainter old) =>
      old.files != files ||
      old.addedColor != addedColor ||
      old.deletedColor != deletedColor;
}

class _SimpleSplitBar extends StatelessWidget {
  final int additions;
  final int deletions;
  final Color addedColor;
  final Color deletedColor;
  final Color emptyColor;
  const _SimpleSplitBar({
    required this.additions,
    required this.deletions,
    required this.addedColor,
    required this.deletedColor,
    required this.emptyColor,
  });

  @override
  Widget build(BuildContext context) {
    final total = (additions + deletions).clamp(1, 1 << 30);
    final addRatio = additions / total;
    return Row(
      children: [
        Expanded(
          flex: (addRatio * 1000).round(),
          child: Container(color: addedColor),
        ),
        Expanded(
          flex: ((1 - addRatio) * 1000).round(),
          child: Container(color: deletedColor),
        ),
      ],
    );
  }
}

enum _WorklineDirection { outgoing, incoming }

/// Right-edge connector tab carrying a workline-graph link count.
/// Outgoing = "this PR closes N issues" (rendered with a `→` chevron).
/// Incoming = "this issue is addressed by N PRs" (`←` chevron). The
/// shape is a slim trapezoid that breaks the row's right edge — reads
/// as a tab continuing off the row, hinting at the linked item beyond.
class _WorklineConnector extends StatefulWidget {
  final int count;
  final _WorklineDirection direction;
  final Color color;
  final VoidCallback onTap;
  const _WorklineConnector({
    required this.count,
    required this.direction,
    required this.color,
    required this.onTap,
  });
  @override
  State<_WorklineConnector> createState() => _WorklineConnectorState();
}

class _WorklineConnectorState extends State<_WorklineConnector> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final fg =
        _hovered ? t.textStrong : widget.color.withValues(alpha: 0.95);
    final bg = _hovered
        ? widget.color.withValues(alpha: 0.32)
        : widget.color.withValues(alpha: 0.18);
    final glyph = widget.direction == _WorklineDirection.outgoing
        ? '→'
        : '←';
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.direction == _WorklineDirection.outgoing
              ? 'closes ${widget.count} issue'
                  '${widget.count == 1 ? '' : 's'} — click to jump'
              : 'addressed by ${widget.count} PR'
                  '${widget.count == 1 ? '' : 's'} — click to jump',
          child: AnimatedContainer(
            duration: context.motion(shader.duration),
            curve: shader.safeCurve,
            width: 22,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(shader.geometry.pillRadius),
                bottomLeft: Radius.circular(shader.geometry.pillRadius),
              ),
              border: Border(
                left: BorderSide(
                  color: widget.color.withValues(alpha: 0.55),
                  width: 1,
                ),
                top: BorderSide(
                  color: widget.color.withValues(alpha: 0.45),
                  width: 1,
                ),
                bottom: BorderSide(
                  color: widget.color.withValues(alpha: 0.45),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  glyph,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    height: 1,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${widget.count}',
                  style: TextStyle(
                    color: fg,
                    fontSize: 9,
                    height: 1.2,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dense scan line: check dots, reviewer dots, diff stats, conv count,
/// updated time. Each metric block is hover-targetable independently;
/// hover surfaces a tooltip with the underlying detail.
class _PrMetricLine extends StatelessWidget {
  final PullRequestSummary pr;
  final List<CheckSummary>? checks;
  /// Per-file change list when detail is loaded. Drives the diff
  /// sparkline (each segment = one file). Empty list when detail
  /// isn't cached yet — sparkline renders a single proportional bar.
  final List<PrFile> files;
  /// Number of files in the PR overlapping the user's dirty work.
  /// Surfaced atmospherically as a hazard strip across the row's
  /// bottom edge, rendered by the parent — not a text pill here.
  /// Kept on the metric-line API so callers stay symmetric.
  final int conflictCount;
  /// Surfaced as a right-edge connector tab on the row, not as a
  /// text pill — see `_WorklineConnector`.
  final int closesIssueCount;
  /// Last action on this PR. Renders as the rightmost segment of
  /// the metric line — the "what's currently true" answer.
  final TailEvent? tail;
  /// Viewer's own review state — empty when n/a. Renders as a
  /// distinct pill so engagement separates from fresh items.
  final String myReviewState;
  const _PrMetricLine({
    required this.pr,
    required this.checks,
    required this.files,
    required this.conflictCount,
    required this.closesIssueCount,
    required this.tail,
    required this.myReviewState,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final mono = TextStyle(
      color: t.textMuted,
      fontSize: 10,
      fontFamily: 'JetBrainsMono',
      letterSpacing: 0.2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final blocks = <Widget>[];
    if (checks != null && checks!.isNotEmpty) {
      blocks.add(Tooltip(
        message: checks!
            .map((c) => '${_checkGlyph(c)}  ${c.name}')
            .join('\n'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final c in checks!.take(8))
              Padding(
                padding: const EdgeInsets.only(right: 1),
                child: Text(
                  _checkGlyph(c),
                  style: TextStyle(
                    color: _checkColor(t, c),
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 3),
            Text('checks', style: mono),
          ],
        ),
      ));
    }
    if (pr.reviewers.isNotEmpty) {
      blocks.add(Tooltip(
        message: pr.reviewers
            .map((r) => '${_reviewerGlyph(r.state)}  @${r.login}'
                ' · ${r.state.toLowerCase().replaceAll('_', ' ')}')
            .join('\n'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final r in pr.reviewers.take(6))
              Padding(
                padding: const EdgeInsets.only(right: 1),
                child: Text(
                  _reviewerGlyph(r.state),
                  style: TextStyle(
                    color: _reviewerColor(t, r.state),
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            const SizedBox(width: 3),
            Text('reviewers', style: mono),
          ],
        ),
      ));
    }
    if (pr.changedFiles > 0) {
      // Diff sparkline replaces `+N -M` text. Each segment = a file
      // in the PR; segment width tracks the file's churn, the green/
      // red vertical split tracks add vs delete share. Falls back to
      // a single proportional segment when per-file detail isn't yet
      // cached. This is the *shape* of the change at a glance —
      // reviewer sees where the mass is before reading anything.
      blocks.add(_DiffSparkline(
        pr: pr,
        files: files,
        addedColor: t.stateAdded,
        deletedColor: t.stateDeleted,
        emptyColor: t.chromeBorder.withValues(alpha: 0.35),
      ));
    }
    // Conversation count merged into the tail block — there's no
    // value in showing both `3 conv` AND `💬 alice · 4h` because the
    // tail IS the latest beat of the conversation. The count rides
    // along inside the tail pill (only when ≥ 1).
    if (pr.mergeable == 'CONFLICTING') {
      blocks.add(Text('conflicts',
          style: mono.copyWith(color: t.stateDeleted)));
    }
    // MY-REVIEW-STATE pill — distinct from anonymous reviewer dots.
    // Lights up when *I* have engaged with this PR, separating
    // "things I've touched" from fresh items.
    if (myReviewState.isNotEmpty) {
      blocks.add(_MyReviewPill(state: myReviewState));
    }
    // CONFLICT-WITH-ME and closes-issues are NOT rendered here as
    // text pills. They become atmospheric: the row's bottom-edge
    // hazard strip + a right-edge workline-connector tab. Move
    // signal from labels to spatial form.
    // CONVERSATION TAIL — rightmost segment, the "what's currently
    // true" answer in one glyph + actor + relative time. Replaces
    // the standalone updated-time text above.
    blocks.add(_ConversationTailPill(
      tail: tail,
      fallbackAt: pr.updatedAt,
      conversationCount: pr.conversationCount,
    ));

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: blocks,
    );
  }
}

class _ActionProgressBar extends StatefulWidget {
  final Color color;
  const _ActionProgressBar({required this.color});

  @override
  State<_ActionProgressBar> createState() => _ActionProgressBarState();
}

class _ActionProgressBarState extends State<_ActionProgressBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))
        ..repeat();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 2,
      child: AnimatedBuilder(
        animation: _ac,
        builder: (context, _) {
          return LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            // Sweeping bar — left edge tied to progress, fixed width.
            final left = (-w * 0.4) + (w * 1.4) * _ac.value;
            return Stack(
              children: [
                Container(color: widget.color.withValues(alpha: 0.08)),
                Positioned(
                  left: left,
                  top: 0,
                  bottom: 0,
                  width: w * 0.4,
                  child: Container(color: widget.color),
                ),
              ],
            );
          });
        },
      ),
    );
  }
}

/// Export a cached PR's diff as a `.patch` file via the native save dialog.
/// Uses the existing [formatPrAsPatch] serializer so the file roundtrips
/// cleanly through `git apply`. Silently no-ops if the user cancels.
Future<void> _exportPrAsPatch(
  BuildContext context,
  PullRequestSummary pr,
  PullRequestDetail detail,
) async {
  final suggested = 'pr-${pr.number}.patch';
  final patch = formatPrAsPatch(pr, detail);
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export PR #${pr.number} as .patch',
      fileName: suggested,
      type: FileType.custom,
      allowedExtensions: const ['patch', 'diff'],
    );
    if (path == null) return;
    await File(path).writeAsString(patch);
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export failed: $e')),
    );
  }
}

class _PrExpanded extends StatelessWidget {
  final PullRequestSummary pr;
  final String viewerLogin;
  final PullRequestDetail? detail;
  final bool detailLoading;
  final List<CheckSummary>? checks;
  final bool checksLoading;
  final String? activeFilePath;
  final FileCouplingMatrix? couplingMatrix;
  final Set<String> conflictingPaths;
  final Set<int> closesIssues;
  final ValueChanged<int> onJumpToIssue;
  final Set<int> collidesWithPrs;
  final Map<int, String> collisionTitles;
  final Map<int, Set<String>> collisionSharedFiles;
  final ValueChanged<int> onJumpToPr;
  final FileSignals? fileSignals;
  final bool fileSignalsLoading;
  /// File-pills layout: false = horizontal scroll, true = wrap.
  /// Persisted at the page level via SharedPreferences.
  final bool filePillsWrap;
  final VoidCallback onToggleFilePillsWrap;
  /// Lens-level "currently hovered file" notifier — drives the
  /// resonance aurora across pills.
  final ValueNotifier<String?> auroraSourceFile;
  final ValueChanged<String> onSelectFile;
  final void Function(String event, String body) onSubmitReview;
  final VoidCallback onCheckout;
  final void Function(String method, bool deleteBranch) onMerge;

  const _PrExpanded({
    required this.pr,
    required this.viewerLogin,
    required this.detail,
    required this.detailLoading,
    required this.checks,
    required this.checksLoading,
    required this.activeFilePath,
    required this.couplingMatrix,
    required this.conflictingPaths,
    required this.closesIssues,
    required this.onJumpToIssue,
    required this.collidesWithPrs,
    required this.collisionTitles,
    required this.collisionSharedFiles,
    required this.onJumpToPr,
    required this.fileSignals,
    required this.fileSignalsLoading,
    required this.filePillsWrap,
    required this.onToggleFilePillsWrap,
    required this.auroraSourceFile,
    required this.onSelectFile,
    required this.onSubmitReview,
    required this.onCheckout,
    required this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // CONFLICTS-WITH-YOU lands first when relevant — high-stakes
          // local signal that comes from data no other PR client has.
          // Pure derivation: PR's file list ∩ user's dirty paths.
          if (conflictingPaths.isNotEmpty) ...[
            _ConflictsWithYouSection(paths: conflictingPaths.toList()..sort()),
            const SizedBox(height: 14),
          ],
          // WILL FIGHT — inter-PR collision graph, expanded. Each
          // colliding PR is a row showing #N + title + shared file
          // count, click → focus jumps to that PR. The reviewer/
          // maintainer sees the full merge-order risk surface and can
          // act on it without leaving the row.
          if (collidesWithPrs.isNotEmpty) ...[
            _WillFightSection(
              prTitles: collisionTitles,
              sharedFiles: collisionSharedFiles,
              orderedNumbers: collidesWithPrs.toList()..sort(),
              onJumpToPr: onJumpToPr,
            ),
            const SizedBox(height: 14),
          ],
          // LINKS — the workline graph rendered as actionable jumps.
          // Issues this PR closes/refs; click to cross-lens-jump to the
          // issue with it expanded. Empty = standalone PR (no link).
          if (closesIssues.isNotEmpty) ...[
            _LinkedIssuesSection(
              issueNumbers: closesIssues.toList()..sort(),
              onJump: onJumpToIssue,
            ),
            const SizedBox(height: 14),
          ],
          // FILES section header carries the resonance pill AND a
          // clickable wrap/scroll toggle. The toggle persists via
          // SharedPreferences (NOT exposed in settings — discovered
          // by power users clicking the header). When wrapped, the
          // file pills below render as a wrap layout; when scrolled
          // (default), they're a horizontal strip.
          _FilesSectionHeader(
            files: detail?.files ?? const [],
            matrix: couplingMatrix,
            isWrapped: filePillsWrap,
            onToggleWrap: onToggleFilePillsWrap,
          ),
          const SizedBox(height: 6),
          if (detail == null && detailLoading)
            Text('reading files…',
                style: TextStyle(
                    color: t.textMuted,
                    fontSize: 11,
                    fontStyle: FontStyle.italic))
          else if (detail == null)
            Text('no detail available',
                style: TextStyle(color: t.textMuted, fontSize: 11))
          else if (detail!.files.isEmpty)
            Text('no files reported',
                style: TextStyle(color: t.textMuted, fontSize: 11))
          else
            _FilePillStrip(
              files: detail!.files,
              activePath: activeFilePath ?? detail!.files.first.path,
              clusterByPath: _computeClusters(detail!.files, couplingMatrix),
              heatByPath: fileSignals?.heatByPath ?? const {},
              ghostPaths: _resonanceForecast(
                detail!.files,
                couplingMatrix,
                engine: () {
                  final repo = context.read<RepositoryState>().activePath;
                  return repo == null
                      ? null
                      : context.read<LogosGitState>().engineFor(repo);
                }(),
              ),
              auroraSource: auroraSourceFile,
              couplingMatrix: couplingMatrix,
              onSelect: onSelectFile,
              wrapped: filePillsWrap,
            ),
          if (detail != null && detail!.files.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Pull the active file's cluster + stats from what we
            // already computed for the file pills so the diff header's
            // identity matches exactly. Defaults to the first file
            // when no pill is selected yet.
            Builder(builder: (ctx) {
              final activePath =
                  activeFilePath ?? detail!.files.first.path;
              final clusters = _computeClusters(detail!.files, couplingMatrix);
              final activeFile = detail!.files.firstWhere(
                (f) => f.path == activePath,
                orElse: () => detail!.files.first,
              );
              return _DiffView(
                // Key on file path so State (incl. expand toggle) is
                // recreated per file — each file judges its own
                // length independently.
                key: ValueKey(activePath),
                diffByFile: detail!.diffByFile,
                activeFilePath: activePath,
                clusterId: clusters[activePath],
                additions: activeFile.additions,
                deletions: activeFile.deletions,
              );
            }),
          ],
          const SizedBox(height: 16),
          _SectionLabel('REVIEW'),
          const SizedBox(height: 6),
          _ReviewForm(onSubmit: onSubmitReview),
          const SizedBox(height: 16),
          if (checks != null && checks!.isNotEmpty) ...[
            _SectionLabel('CHECKS'),
            const SizedBox(height: 6),
            for (final c in checks!) _CheckLine(check: c),
            const SizedBox(height: 14),
          ],
          // PEOPLE — single section that fuses two related ideas:
          //   * who's currently REVIEWING the PR (with their state)
          //   * who's most recently TOUCHED these files in git history
          // A reviewer who's also a recent toucher gets BOTH signals
          // on the same row ("they're reviewing AND they know it").
          // A toucher who isn't yet a reviewer renders muted as a
          // suggestion. Combined: "who is in the orbit of this code"
          // becomes one mental concept, not two.
          if (pr.reviewers.isNotEmpty ||
              (fileSignals != null && fileSignals!.authors.isNotEmpty) ||
              fileSignalsLoading) ...[
            _SectionLabel('PEOPLE'),
            const SizedBox(height: 6),
            _PeopleSection(
              reviewers: pr.reviewers,
              recentTouchers: fileSignals?.authors ?? const [],
              touchersLoading: fileSignalsLoading,
            ),
            const SizedBox(height: 14),
          ],
          if (detail != null && detail!.comments.isNotEmpty) ...[
            _SectionLabel('CONVERSATION'),
            const SizedBox(height: 6),
            // Full thread, sorted chronologically (oldest first). Mixes
            // top-level PR comments with review submission bodies,
            // tagged by their action ([approved], [requested changes]
            // etc) so the reader sees what was said AND in what role.
            for (final c in detail!.comments) _CommentBlock(comment: c),
            const SizedBox(height: 14),
          ],
          // Action gravity row.
          _PrActionToolbar(
            mergeable: pr.mergeable == 'MERGEABLE',
            onCheckout: onCheckout,
            onMerge: onMerge,
            stateOpen: pr.state == 'OPEN',
            canExportPatch: detail != null && detail!.diff.isNotEmpty,
            onExportPatch: detail != null && detail!.diff.isNotEmpty
                ? () => _exportPrAsPatch(context, pr, detail!)
                : null,
          ),
        ],
      ),
    );
  }
}

/// PEOPLE — fused reviewer + recent-toucher view. Each unique person
/// gets ONE row that carries:
///   * their reviewer state (✓ approved / ✗ changes / ◐ pending) when
///     they're a reviewer
///   * their commit count on the PR's files (when they're a recent
///     toucher), as a small `Nc` mono badge
///   * a "knows this code" tag when they're a toucher who isn't yet
///     a reviewer (suggestion)
/// Rows are sorted: active reviewers first (by state weight), then
/// suggested touchers by commit count desc.
class _PeopleSection extends StatelessWidget {
  final List<PrReviewer> reviewers;
  final List<({String email, int commits})> recentTouchers;
  final bool touchersLoading;
  const _PeopleSection({
    required this.reviewers,
    required this.recentTouchers,
    required this.touchersLoading,
  });

  String _stem(String email) {
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }

  // Commit-count map keyed by login-stem so reviewers can be enriched
  // with their commit history when present.
  Map<String, int> _commitCountsByLogin() {
    final out = <String, int>{};
    for (final a in recentTouchers) {
      out[_stem(a.email)] = a.commits;
    }
    return out;
  }

  // Sort weight for reviewer states — approved/changes-requested are
  // most actionable, then commented, then pending. Empty (non-
  // reviewer touchers) sort last.
  int _stateWeight(String state) {
    switch (state) {
      case 'CHANGES_REQUESTED':
        return 0;
      case 'APPROVED':
        return 1;
      case 'COMMENTED':
        return 2;
      case 'PENDING':
        return 3;
      default:
        return 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final commits = _commitCountsByLogin();
    // Build the unified people list. Reviewers first; then suggested
    // touchers who aren't already reviewers.
    final reviewerLogins = reviewers.map((r) => r.login).toSet();
    final entries = <_PersonEntry>[];
    for (final r in reviewers) {
      entries.add(_PersonEntry(
        login: r.login,
        state: r.state,
        commits: commits[r.login] ?? 0,
        isReviewer: true,
      ));
    }
    for (final a in recentTouchers) {
      final stem = _stem(a.email);
      if (reviewerLogins.contains(stem)) continue;
      entries.add(_PersonEntry(
        login: stem,
        state: '',
        commits: a.commits,
        isReviewer: false,
      ));
    }
    entries.sort((a, b) {
      final sw = _stateWeight(a.state).compareTo(_stateWeight(b.state));
      if (sw != 0) return sw;
      return b.commits.compareTo(a.commits);
    });
    if (entries.isEmpty && touchersLoading) {
      return Text(
        'reading git history…',
        style: TextStyle(
          color: t.textMuted,
          fontSize: 11,
          fontStyle: FontStyle.italic,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final e in entries) _PersonRow(entry: e),
      ],
    );
  }
}

class _PersonEntry {
  final String login;
  final String state;
  final int commits;
  final bool isReviewer;
  const _PersonEntry({
    required this.login,
    required this.state,
    required this.commits,
    required this.isReviewer,
  });
}

class _PersonRow extends StatelessWidget {
  final _PersonEntry entry;
  const _PersonRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          // State glyph slot — reviewer state if any, else a small
          // dot for "non-reviewer" so the column stays aligned.
          SizedBox(
            width: 14,
            child: Text(
              entry.isReviewer ? _reviewerGlyph(entry.state) : '·',
              style: TextStyle(
                color: entry.isReviewer
                    ? _reviewerColor(t, entry.state)
                    : t.textMuted.withValues(alpha: 0.55),
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '@${entry.login}',
            style: TextStyle(
              color: entry.isReviewer ? t.textNormal : t.textMuted,
              fontSize: 11,
              fontFamily: 'JetBrainsMono',
              fontWeight:
                  entry.isReviewer ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          const SizedBox(width: 8),
          if (entry.isReviewer && entry.state.isNotEmpty)
            Text(
              entry.state.toLowerCase().replaceAll('_', ' '),
              style: TextStyle(color: t.textMuted, fontSize: 10),
            ),
          if (!entry.isReviewer)
            Text(
              'knows this code',
              style: TextStyle(
                color: t.textMuted.withValues(alpha: 0.7),
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          const Spacer(),
          // Commit count rides the right edge as a small mono badge —
          // visible whether the person is a reviewer or a suggestion.
          // This is the local-git signal made native to the PEOPLE
          // grammar instead of living in its own section.
          if (entry.commits > 0)
            Tooltip(
              message: '${entry.commits} commit'
                  '${entry.commits == 1 ? '' : 's'} on these files '
                  'in the last year',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: t.chromeBorder.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(
                      context.surfaceShader.geometry.badgeRadius),
                ),
                child: Text(
                  '${entry.commits}c',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 9.5,
                    fontFamily: 'JetBrainsMono',
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Inter-PR collision section. Lists every OTHER open PR whose file
/// list overlaps this one, with title + shared file count, sorted by
/// number. Clicking a row focuses + expands that PR — so the
/// maintainer sweeps through the collision graph without leaving the
/// row. Visual treatment matches `_ConflictsWithYouSection` but in
/// `stateConflicted` orange (the "team-merge-order" color, distinct
/// from "your-personal" red).
class _WillFightSection extends StatelessWidget {
  final Map<int, String> prTitles;
  final Map<int, Set<String>> sharedFiles;
  final List<int> orderedNumbers;
  final ValueChanged<int> onJumpToPr;
  const _WillFightSection({
    required this.prTitles,
    required this.sharedFiles,
    required this.orderedNumbers,
    required this.onJumpToPr,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.stateConflicted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(
            context.surfaceShader.geometry.pillRadius),
        border: Border(
          left: BorderSide(
            color: t.stateConflicted.withValues(alpha: 0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WILL FIGHT',
            style: TextStyle(
              color: t.stateConflicted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          for (final n in orderedNumbers)
            _WillFightRow(
              number: n,
              title: prTitles[n] ?? '',
              shared: sharedFiles[n] ?? const <String>{},
              onTap: () => onJumpToPr(n),
            ),
          const SizedBox(height: 4),
          Text(
            'merging in the wrong order will force one of these to rebase',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _WillFightRow extends StatefulWidget {
  final int number;
  final String title;
  final Set<String> shared;
  final VoidCallback onTap;
  const _WillFightRow({
    required this.number,
    required this.title,
    required this.shared,
    required this.onTap,
  });
  @override
  State<_WillFightRow> createState() => _WillFightRowState();
}

class _WillFightRowState extends State<_WillFightRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(
            color: _hovered
                ? t.stateConflicted.withValues(alpha: 0.1)
                : t.stateConflicted.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(shader.geometry.badgeRadius),
          ),
          child: Tooltip(
            message: widget.shared.join('\n'),
            child: Row(
              children: [
                Text(
                  '↗ #${widget.number}',
                  style: TextStyle(
                    color: t.stateConflicted,
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _hovered ? t.textStrong : t.textNormal,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.shared.length} '
                  'file${widget.shared.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                    fontFeatures: const [FontFeature.tabularFigures()],
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Lists the files in this PR that the user has uncommitted changes
/// in. Read at a glance: "if you merge this, here's what your worktree
/// will fight." Each filename is mono so it scans cleanly.
class _ConflictsWithYouSection extends StatelessWidget {
  final List<String> paths;
  const _ConflictsWithYouSection({required this.paths});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.stateDeleted.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(
            context.surfaceShader.geometry.pillRadius),
        border: Border(
          left: BorderSide(
            color: t.stateDeleted.withValues(alpha: 0.7),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOUCHES YOUR LOCAL WORK',
            style: TextStyle(
              color: t.stateDeleted,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          for (final p in paths)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                p,
                style: TextStyle(
                  color: t.textNormal,
                  fontSize: 11,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'merging will likely conflict with your uncommitted changes',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// Issues this PR closes/refs as actionable chips. Click → cross-lens
/// jump to the ISSUES lens with the issue expanded. Makes the PR feel
/// connected to the open intent it's resolving.
class _LinkedIssuesSection extends StatelessWidget {
  final List<int> issueNumbers;
  final ValueChanged<int> onJump;
  const _LinkedIssuesSection({
    required this.issueNumbers,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'CLOSES',
          style: TextStyle(
            color: t.textMuted,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final n in issueNumbers)
              _IssueLinkChip(number: n, onTap: () => onJump(n)),
          ],
        ),
      ],
    );
  }
}

class _IssueLinkChip extends StatefulWidget {
  final int number;
  final VoidCallback onTap;
  const _IssueLinkChip({required this.number, required this.onTap});
  @override
  State<_IssueLinkChip> createState() => _IssueLinkChipState();
}

class _IssueLinkChipState extends State<_IssueLinkChip> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? t.accentBright.withValues(alpha: 0.18)
                : t.accentBright.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.pillRadius),
            border: Border.all(
                color: t.accentBright.withValues(alpha: 0.45), width: 1),
          ),
          child: Text(
            '↗ #${widget.number}',
            style: TextStyle(
              color: t.accentBright,
              fontSize: 10.5,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// PR backlink chip used inside the issue expand. Carries the PR's
/// state token so an issue reader sees "addressed by #142 (open)" or
/// "addressed by #131 (merged)" at a glance.
class _PrLinkChip extends StatefulWidget {
  final PullRequestSummary pr;
  final VoidCallback onTap;
  const _PrLinkChip({required this.pr, required this.onTap});
  @override
  State<_PrLinkChip> createState() => _PrLinkChipState();
}

class _PrLinkChipState extends State<_PrLinkChip> {
  bool _hovered = false;
  Color _stateColor(AppTokens t) {
    switch (widget.pr.state) {
      case 'OPEN':
        return widget.pr.isDraft ? t.textMuted : t.accentBright;
      case 'MERGED':
        return t.stateConflicted;
      case 'CLOSED':
        return t.stateDeleted;
      default:
        return t.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final state = _stateColor(t);
    final stateLabel = widget.pr.state == 'OPEN' && widget.pr.isDraft
        ? 'draft'
        : widget.pr.state.toLowerCase();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _hovered
                ? state.withValues(alpha: 0.18)
                : state.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(shader.geometry.pillRadius),
            border:
                Border.all(color: state.withValues(alpha: 0.45), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '↗ #${widget.pr.number}',
                style: TextStyle(
                  color: state,
                  fontSize: 10.5,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                stateLabel,
                style: TextStyle(
                  color: state.withValues(alpha: 0.75),
                  fontSize: 9.5,
                  fontFamily: 'JetBrainsMono',
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(
      label,
      style: TextStyle(
        color: t.textMuted,
        fontSize: 9,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.4,
      ),
    );
  }
}

/// Compute a cluster id per file via the coupling matrix's
/// `clusterFiles`. Returns an empty map when the matrix isn't ready
/// yet (file pills then render with no cluster tint, neutral chrome —
/// graceful degradation, same pattern as the changes-panel rail).
Map<String, int> _computeClusters(
  List<PrFile> files,
  FileCouplingMatrix? matrix,
) {
  if (matrix == null || files.length < 2) return const {};
  final paths = files.map((f) => f.path).toList();
  final clusters = clusterFiles(paths, matrix);
  return clusters.byPath;
}

/// RESONANCE FORECAST — surfaces files the PR almost-touched but missed.
/// Two paths:
///   • **engine-warm**: one weighted diffusion across the entire PR file
///     set (heat-kernel at t=1.0). Top-K neighbours by φ become the
///     ghost pills. This sees indirect couplings — a test that's tied
///     to module A via co-change with module B will surface even when
///     the PR only touches A. Uses the same [LogosGit] engine the
///     resonance pill reads from, so the two readings agree.
///   • **fallback**: max-pairwise Jaccard from the raw coupling matrix.
///     Same behaviour as before — graceful degradation when the engine
///     hasn't finished its first build.
///
/// In both cases we cap suggestions at [maxSuggestions] to keep the
/// strip readable.
Set<String> _resonanceForecast(
  List<PrFile> files,
  FileCouplingMatrix? matrix, {
  LogosGit? engine,
  double threshold = 0.4,
  int maxSuggestions = 5,
}) {
  if (files.isEmpty) return const {};
  final inPr = files.map((f) => f.path).toSet();

  if (engine != null) {
    // Diffuse from every PR file at unit weight; the kernel handles the
    // amplitude composition. t=1.0 is the commit-review default — close-
    // neighbour scope, doesn't reach across the whole repo.
    final weights = <String, double>{for (final p in inPr) p: 1.0};
    final scored = engine.diffuseWeighted(
      weights,
      t: 1.0,
      excludePaths: inPr,
    );
    if (scored.isEmpty) return const {};
    // Threshold against a fraction of the top score — engine φ values
    // aren't on the same scale as Jaccard, so a fixed 0.4 cutoff would
    // be meaningless. A relative gate keeps the ghost pills tight.
    final topPhi = scored.first.phi;
    final cutoff = topPhi * 0.25;
    return scored
        .where((s) => s.phi >= cutoff)
        .take(maxSuggestions)
        .map((s) => s.path)
        .toSet();
  }

  if (matrix == null) return const {};
  final scored = <String, double>{};
  for (final f in files) {
    final neighbors = matrix.jaccard[f.path] ?? const <String, double>{};
    for (final entry in neighbors.entries) {
      if (entry.value < threshold) continue;
      if (inPr.contains(entry.key)) continue;
      // Take the max score for any (PR file → neighbor) pair so a
      // file appearing as a strong neighbor of multiple PR files
      // doesn't double-count.
      final prev = scored[entry.key] ?? 0.0;
      if (entry.value > prev) scored[entry.key] = entry.value;
    }
  }
  final sorted = scored.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(maxSuggestions).map((e) => e.key).toSet();
}

/// FILES header — "resonance" pill that reads the average pairwise
/// coupling score across the PR's changed files and renders it as
/// 5 dots + a numeric readout. High = focused change (files that
/// historically move together); low = sprawling (files git history
/// has rarely seen co-touched).
class _FilesSectionHeader extends StatelessWidget {
  final List<PrFile> files;
  final FileCouplingMatrix? matrix;
  final bool isWrapped;
  final VoidCallback onToggleWrap;
  const _FilesSectionHeader({
    required this.files,
    required this.matrix,
    required this.isWrapped,
    required this.onToggleWrap,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Prefer LogosGit multi-axis coherence when the engine is warm — it
    // factors coupling AND frequency AND directory proximity AND
    // volatility, not just Jaccard. Graceful fallback to single-axis
    // matrix.coherenceFor() when the engine hasn't finished its first
    // build, so UI never stalls.
    final paths = files.map((f) => f.path);
    final repoPath = context.read<RepositoryState>().activePath;
    final engine = repoPath == null
        ? null
        : context.watch<LogosGitState>().engineFor(repoPath);
    final hasSignal =
        files.length >= 2 && (matrix != null || engine != null);
    final coherence = !hasSignal
        ? null
        : (engine != null
            ? engine.coherence(paths)
            : matrix!.coherenceFor(paths));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Clickable header — toggles wrap/scroll for the file pills
        // below. Tiny mode glyph after the label keeps the action
        // discoverable but quiet. State persists via SharedPreferences
        // (NOT in settings — power-user prefs that nobody needs to
        // see in a settings page).
        MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onToggleWrap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SectionLabel('FILES'),
                const SizedBox(width: 6),
                Text(
                  isWrapped ? '⇕' : '↔',
                  style: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.65),
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (coherence != null) ...[
          // Five filled-vs-empty dots based on coherence quintile —
          // same dot vocabulary as the check-status indicators so the
          // visual language stays consistent across the lens.
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 1),
              child: Text(
                coherence > (i / 5) ? '●' : '○',
                style: TextStyle(
                  color: coherence > (i / 5)
                      ? t.accentBright
                      : t.textMuted.withValues(alpha: 0.6),
                  fontSize: 10,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          const SizedBox(width: 6),
          Text(
            'resonance ${coherence.toStringAsFixed(2)}',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 9.5,
              fontFamily: 'JetBrainsMono',
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 0.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _FilePillStrip extends StatelessWidget {
  final List<PrFile> files;
  final String activePath;
  final Map<String, int> clusterByPath;
  final Map<String, double> heatByPath;
  final Set<String> ghostPaths;
  /// Lens-level "currently hovered file" notifier — drives the
  /// resonance aurora across pills.
  final ValueNotifier<String?> auroraSource;
  /// Coupling matrix used to compute neighbor brightness on hover.
  final FileCouplingMatrix? couplingMatrix;
  final ValueChanged<String> onSelect;
  final bool wrapped;
  const _FilePillStrip({
    required this.files,
    required this.activePath,
    required this.clusterByPath,
    required this.heatByPath,
    required this.ghostPaths,
    required this.auroraSource,
    required this.couplingMatrix,
    required this.onSelect,
    required this.wrapped,
  });

  @override
  Widget build(BuildContext context) {
    // PR-level coherence — average pairwise Jaccard across files. Pills
    // use this to scale their cascade intensity: dense PRs (everything
    // moves together) damp the cascade so the strip doesn't read as
    // uniform glow; sparse PRs amplify it so the rare strong coupling
    // stands out. Single matrix sweep, shared across every pill.
    final m = couplingMatrix;
    final coherence = (m != null && files.length >= 2)
        ? m.coherenceFor(files.map((f) => f.path))
        : 0.0;
    final pills = <Widget>[
      for (final f in files)
        _FilePill(
          file: f,
          isActive: f.path == activePath,
          activePath: activePath,
          clusterId: clusterByPath[f.path],
          clusterByPath: clusterByPath,
          heat: heatByPath[f.path] ?? 0,
          coherence: coherence,
          auroraSource: auroraSource,
          couplingMatrix: couplingMatrix,
          onTap: () => onSelect(f.path),
        ),
      for (final ghost in ghostPaths) _GhostFilePill(path: ghost),
    ];
    if (wrapped) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: pills,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < pills.length; i++)
            Padding(
              padding: EdgeInsets.only(right: i == pills.length - 1 ? 0 : 6),
              child: pills[i],
            ),
        ],
      ),
    );
  }
}

/// Ghost pill = coupling-implied "you forgot this" file. Dashed
/// outline + muted italic. Click is a no-op (file isn't in the PR).
class _GhostFilePill extends StatelessWidget {
  final String path;
  const _GhostFilePill({required this.path});
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final filename = path.split('/').last;
    return Tooltip(
      message: 'usually moves with the files in this PR\n($path)',
      child: CustomPaint(
        painter: _DashedBorderPainter(
          color: t.textMuted.withValues(alpha: 0.55),
          radius: context.surfaceShader.geometry.pillRadius,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
          child: Text(
            '? $filename',
            style: TextStyle(
              color: t.textMuted,
              fontSize: 10.5,
              fontFamily: 'JetBrainsMono',
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  _DashedBorderPainter({required this.color, required this.radius});
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dashWidth = 3.0;
    const dashGap = 3.0;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _FilePill extends StatefulWidget {
  final PrFile file;
  final bool isActive;
  /// Path of the currently-selected file in the strip. Used to paint a
  /// quiet, persistent coupling aura over neighbors of the selection
  /// so the cascade stays visible after a click, not just on hover.
  final String activePath;
  /// Cluster id from the coupling matrix. Null = isolated file (no
  /// stripe). Pills sharing a cluster share their stripe color, the
  /// same identity used by the changes-panel rail — files that move
  /// together visually belong together.
  final int? clusterId;
  /// Full path → cluster-id map for the strip. Used to resolve the
  /// cluster colors of the SELECTION and HOVER source files so the
  /// cascade tint can blend AWAY from this pill's local identity
  /// TOWARD whichever anchor is energizing it — the visual analog of
  /// "the signal is flowing from there into here."
  final Map<String, int> clusterByPath;
  /// Thermal heat 0..1 — exponentially-decayed commit density on this
  /// file. Drives an ember glow on the pill: hot files have a bright
  /// orange-tinted left edge; cold files are silent. Tells the
  /// reviewer "the team currently lives in this file" without any
  /// label.
  final double heat;
  /// PR-level coherence 0..1 — average pairwise Jaccard across all
  /// files in the strip. Modulates cascade intensity: a sparse PR
  /// (low coherence) amplifies the cascade so rare coupling reads,
  /// a dense PR damps it so the strip doesn't melt into uniform glow.
  final double coherence;
  /// Lens-level currently-hovered file (RESONANCE AURORA source).
  /// When non-null AND the matrix says this pill's file has a
  /// coupling Jaccard ≥ 0.4 with the source, we paint a halo
  /// proportional to the coupling.
  final ValueNotifier<String?> auroraSource;
  final FileCouplingMatrix? couplingMatrix;
  final VoidCallback onTap;
  const _FilePill({
    required this.file,
    required this.isActive,
    required this.activePath,
    required this.clusterId,
    required this.clusterByPath,
    required this.heat,
    required this.coherence,
    required this.auroraSource,
    required this.couplingMatrix,
    required this.onTap,
  });
  @override
  State<_FilePill> createState() => _FilePillState();
}

class _FilePillState extends State<_FilePill> {
  bool _hovered = false;

  /// 0 if not part of the current aurora; otherwise the Jaccard
  /// coupling between this pill's file and the hovered source. The
  /// pill itself (the source) returns 0 here; rendering treats the
  /// source separately via _hovered. Hovering the SELECTED pill also
  /// returns 0 — it's the same anchor as the selection cascade, so
  /// we'd double-count the same signal and fire spurious bridge rings
  /// across every coupled neighbor (sqrt(s·s) = s for every pill).
  double _auroraStrength(String? source) {
    if (source == null) return 0;
    if (source == widget.file.path) return 0;
    if (source == widget.activePath) return 0;
    final m = widget.couplingMatrix;
    if (m == null) return 0;
    final s = m.score(source, widget.file.path);
    return s >= 0.4 ? s : 0;
  }

  /// Selection-anchored cascade. Reuses the same Jaccard threshold as
  /// the hover aura but stays painted as long as a file is selected,
  /// so neighbors of the click stay visually grouped after the cursor
  /// moves on. Selected pill itself returns 0 (already lit by isActive).
  double get _selectionAura => _auroraStrength(widget.activePath);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final accent = t.accentBright;
    final filename = widget.file.path.split('/').last;
    final clusterColor = t.clusterStripeColor(widget.clusterId);
    // Resolve the SELECTION source's cluster color once per build —
    // doesn't depend on the live aurora notifier.
    final selSrcColor = widget.activePath.isEmpty
        ? null
        : t.clusterStripeColor(widget.clusterByPath[widget.activePath]);
    return ValueListenableBuilder<String?>(
      valueListenable: widget.auroraSource,
      builder: (context, source, _) {
        final aurora = _auroraStrength(source);
        final selAura = _selectionAura;
        // Resolve the HOVER source's cluster color from the live notifier.
        final hoverSrcColor = source == null
            ? null
            : t.clusterStripeColor(widget.clusterByPath[source]);

        // ─── PILL CHROME — anchored signal system ───────────────────
        //
        // Both coupling cascades (selection-anchored AND hover-anchored)
        // light BOTH chrome channels (fill + border) so the reader can
        // visually compare "files coupled to what I clicked" against
        // "files coupled to what I'm aiming at" at a glance — a pill
        // lit only by selection looks distinct from one lit only by
        // hover (different anchor, different mass), and a pill lit by
        // both stacks louder. The bridge ring (inner stroke) is the
        // precise intersection indicator: it reads as a different
        // SHAPE, so a true path-node is unambiguous even when alphas
        // happen to coincide.
        //
        //   STATE                  CHANNELS              ENCODING
        //   ─────────────────────────────────────────────────────────
        //   cluster identity       Left stripe           static color
        //   heat (commit density)  Left ember            static gradient
        //   selected pill          Fill + border α↑      accent, promoted α
        //   hovered pill           Fill + border bump    cross-channel lift
        //   coupled → CURSOR       Fill + border         cluster, jh × intensity
        //   coupled → SELECTION    Fill + border         cluster, js × intensity·decay
        //   bridge (both)          Inner ring (own)      √(jh·js) × ringMax
        //
        // Cascade intensities adapt to PR coherence (sparse PRs amp,
        // dense PRs damp). Hot files boost the direct hover affordance.
        // The bridge ring is intentionally non-adaptive — rare, precise,
        // always reads at full clarity.

        // One anchor primitive; everything derives from it.
        const restingBorderAlpha = 0.3;
        const selectedBorderAlpha = restingBorderAlpha * 2;
        const selectedFillAlpha = restingBorderAlpha * 0.5;
        const restingFillAlpha = 0.4; // surface1 wash on idle pills
        const hoverBorderBump = restingBorderAlpha * 0.6;
        const hoverFillBump = restingBorderAlpha / 3;
        // Bridge ring peaks at 1.5× resting border — louder than chrome,
        // quieter than the selected outline, so it reads as "real signal"
        // without stealing primary attention from the selected pill.
        const bridgeRingMax = restingBorderAlpha * 1.5;

        // Cascade peaks at Jaccard 1.0 saturate at the same alpha the
        // anchor itself would (selected fill / promotion delta), so a
        // strongly-coupled neighbor visually IS "what the anchor looks
        // like" attenuated by graph distance.
        final hoverCascade = 1.0 - widget.coherence * 0.4;
        final selectionCascade =
            hoverCascade * (0.55 - widget.coherence * 0.2);
        final hoverFillPeak = selectedFillAlpha * hoverCascade;
        final hoverBorderPeak =
            (selectedBorderAlpha - restingBorderAlpha) * hoverCascade;
        final selectionFillPeak = selectedFillAlpha * selectionCascade;
        final selectionBorderPeak =
            (selectedBorderAlpha - restingBorderAlpha) * selectionCascade;

        // Hot files boost the direct hover bump only (cascades stay
        // neutral). Heat 0 → baseline; heat 1 → +50%.
        final heatBoost = 1.0 + widget.heat * 0.5;
        final liveHoverFill = _hovered ? hoverFillBump * heatBoost : 0.0;
        final liveHoverBorder = _hovered ? hoverBorderBump * heatBoost : 0.0;

        // ─── COLOR MIXING ───────────────────────────────────────────
        // The cascade tint of a non-selected pill blends the cluster
        // colors of its two anchors (selection + hover) weighted by
        // each anchor's cascade contribution. The pill's body bleeds
        // AWAY from its own cluster identity TOWARD whichever anchor
        // is energizing it — mycelium energy literally flowing in.
        //
        // Pure selection cascade → tint = selection-source color
        // Pure hover cascade     → tint = hover-source color
        // Both                   → linear blend, ratio = sel / (sel+hov)
        // Neither                → fall back to local cluster identity
        Color cascadeTint() {
          final sFallback = clusterColor ?? accent;
          final wHover = aurora;
          final wSel = selAura;
          if (wHover + wSel <= 0) return sFallback;
          final hSrc = hoverSrcColor ?? sFallback;
          final sSrc = selSrcColor ?? sFallback;
          final mix = wSel / (wHover + wSel);
          return Color.lerp(hSrc, sSrc, mix) ?? sFallback;
        }

        // ─── Channel composition ───────────────────────────────────
        // FILL: selection wash + both cascades + hover bump.
        final fillTouched =
            widget.isActive || aurora > 0 || selAura > 0 || _hovered;
        final fillAlpha = (widget.isActive ? selectedFillAlpha : 0.0) +
            aurora * hoverFillPeak +
            selAura * selectionFillPeak +
            liveHoverFill;
        final fillColor = fillTouched
            ? (widget.isActive ? accent : cascadeTint())
                .withValues(alpha: fillAlpha.clamp(0.0, 0.55))
            : t.surface1.withValues(alpha: restingFillAlpha);

        // BORDER: resting/selected base + both cascades + hover bump.
        final borderTouched =
            widget.isActive || aurora > 0 || selAura > 0 || _hovered;
        final borderAlpha = (widget.isActive
                ? selectedBorderAlpha
                : restingBorderAlpha) +
            aurora * hoverBorderPeak +
            selAura * selectionBorderPeak +
            liveHoverBorder;
        final borderColor = (widget.isActive
                ? accent
                : borderTouched
                    ? cascadeTint()
                    : t.chromeBorder)
            .withValues(alpha: borderAlpha.clamp(0.0, 0.95));

        // BRIDGE ring (own channel) — geometric mean suppresses
        // asymmetric pairs; balanced couplings get full brightness.
        // The ring color is the perfect 50/50 blend of the two source
        // colors (selection + hover): bridges visibly carry BOTH
        // identities, not a weighted compromise. Distinct SHAPE so
        // intersection is unambiguous even when alphas coincide.
        final bridge = (aurora > 0 && selAura > 0)
            ? math.sqrt(aurora * selAura)
            : 0.0;
        // Both auroras inherit the Jaccard 0.4 floor when nonzero, so
        // the minimum visible bridge is 0.4. A simple "is nonzero" gate
        // is the honest threshold — any earlier "0.04" looked meaningful
        // but was unreachable.
        final showBridge = bridge > 0;
        final bridgeBlend = Color.lerp(
                hoverSrcColor ?? clusterColor ?? accent,
                selSrcColor ?? clusterColor ?? accent,
                0.5) ??
            (clusterColor ?? accent);
        final bridgeColor =
            bridgeBlend.withValues(alpha: bridge * bridgeRingMax);

        final pillRadius = context.surfaceShader.geometry.pillRadius;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() => _hovered = true);
            widget.auroraSource.value = widget.file.path;
          },
          onExit: (_) {
            setState(() => _hovered = false);
            // Only clear if WE were the source — fast mouse trails
            // shouldn't blip the aurora off when the next pill's
            // onEnter has already fired.
            if (widget.auroraSource.value == widget.file.path) {
              widget.auroraSource.value = null;
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: context.motion(shader.duration),
              curve: shader.safeCurve,
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(pillRadius),
                border: Border.all(color: borderColor),
              ),
              child: Stack(
                children: [
                  // Bridge ring — inset 1px stroke. Lives on its own
                  // visual channel so a true path-node reads as a
                  // distinct shape, not just brighter alpha.
                  if (showBridge)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: context.motion(shader.duration),
                          curve: shader.safeCurve,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            border: Border.all(color: bridgeColor),
                            borderRadius:
                                BorderRadius.circular(pillRadius - 2),
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 5, 8, 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
              // Left cluster stripe — same palette as the changes-panel
              // rail. Always reserves the slot so pill widths stay
              // aligned whether or not a file is in a cluster.
              // Above the stripe sits an ember-glow proportional to
              // thermal heat: hot files (recent commit density) get
              // an orange wash that bleeds into the pill's leading
              // edge, cold files are silent. The team's current
              // battlefield surfaces visually with no label.
              Stack(
                children: [
                  Container(
                    width: 3,
                    margin: const EdgeInsets.only(right: 6),
                    color: clusterColor ?? Colors.transparent,
                  ),
                  if (widget.heat > 0.05)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                t.stateConflicted
                                    .withValues(alpha: widget.heat * 0.9),
                                t.stateConflicted
                                    .withValues(alpha: widget.heat * 0.3),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (widget.isActive)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent,
                    ),
                  ),
                ),
              Text(
                filename,
                style: TextStyle(
                  color: widget.isActive ? t.textStrong : t.textNormal,
                  fontSize: 10.5,
                  fontFamily: 'JetBrainsMono',
                  fontWeight:
                      widget.isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Text('+${widget.file.additions}',
                  style: TextStyle(
                    color: t.stateAdded.withValues(alpha: 0.85),
                    fontSize: 9,
                    fontFamily: 'JetBrainsMono',
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              const SizedBox(width: 3),
              Text('-${widget.file.deletions}',
                  style: TextStyle(
                    color: t.stateDeleted.withValues(alpha: 0.85),
                    fontSize: 9,
                    fontFamily: 'JetBrainsMono',
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Recycles the canonical diff renderer from the changes panel rather
/// than rolling our own. [DiffLineView] is the same widget the changes
/// panel paints each line through. Staging affordances are off here —
/// PR diffs aren't stageable from this surface.
///
/// Critically, takes a **pre-parsed** map of file → ParsedLines instead
/// of raw diff text. Parsing happens once in [pullRequestDetail] when
/// the future resolves; rebuilding this widget is now an O(filtered
/// list) lookup, not an O(n) regex pass over the full multi-file patch.
/// Without this, every parent setState (AnimatedSize tween, prefetch
/// progress notification, sibling hover) would re-run the parser on
/// the main thread and freeze the app.
///
/// Visual chrome borrows from `_MultiDiffTimelineStrip` in the changes
/// panel: a sticky file header above the lines (path + +/- stats +
/// cluster rail) so the diff feels like a section of the wider review
/// surface, not a floating block. The header carries the same color
/// identity as the file pill above it, so eye-tracking works: the
/// pill the user clicked is now the rail-tinted band at the top of
/// what's underneath it.
class _DiffView extends StatefulWidget {
  final Map<String, List<ParsedLine>> diffByFile;
  final String activeFilePath;
  /// Cluster id from the coupling matrix (same one that tints the
  /// active file pill). Null = isolated; rail goes neutral.
  final int? clusterId;
  /// +/- stats for the active file, surfaced in the header strip.
  final int additions;
  final int deletions;

  const _DiffView({
    super.key,
    required this.diffByFile,
    required this.activeFilePath,
    required this.clusterId,
    required this.additions,
    required this.deletions,
  });

  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  // Per-file expand state. Resets on file switch via the parent's key.
  bool _expanded = false;
  // Match the review pane's collapse heuristic
  // (`_CollapsibleCodeBlock`) but scaled for diffs, which are denser
  // and longer than evidence snippets:
  //   * visible when collapsed: 30 lines (~540 px at the 18px row
  //     contract DiffLineView expects)
  //   * trigger collapse only when hiding >= 20 lines (toggle UI is
  //     worth ~that many to justify)
  static const int _collapsedLines = 30;
  static const int _minHiddenToCollapse = 20;

  // Forward-compat shims so the rest of the build reads the original
  // field names.
  Map<String, List<ParsedLine>> get diffByFile => widget.diffByFile;
  String get activeFilePath => widget.activeFilePath;
  int? get clusterId => widget.clusterId;
  int get additions => widget.additions;
  int get deletions => widget.deletions;

  @override
  void didUpdateWidget(covariant _DiffView old) {
    super.didUpdateWidget(old);
    // If the active file changed, drop the expand state — each file
    // judges its own length independently. (Belt-and-suspenders; the
    // parent should also key us on activeFilePath, but resetting
    // here means a same-key rebuild with a different path stays
    // honest.)
    if (old.activeFilePath != widget.activeFilePath) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lines = diffByFile[activeFilePath] ?? const <ParsedLine>[];
    if (lines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.bg0,
          borderRadius: BorderRadius.circular(
              context.surfaceShader.geometry.pillRadius),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.3)),
        ),
        child: Text('no diff for this file',
            style: TextStyle(color: t.textMuted, fontSize: 11)),
      );
    }
    const lineHeight = 18.0;
    final clusterColor = t.clusterStripeColor(clusterId);
    final hiddenLines = lines.length - _collapsedLines;
    final isLong = hiddenLines >= _minHiddenToCollapse;
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: t.bg0,
          borderRadius: BorderRadius.circular(
              context.surfaceShader.geometry.pillRadius),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File header strip — modelled on `_MultiDiffTimelineStrip`
            // in changes_page. Cluster rail on the left (same palette
            // as the file pill above), file path mono, `+N -N` mono
            // tabular figures aligned right. Sits inside the diff
            // surface so the eye reads "I'm looking at THIS file" as a
            // single visual unit with the lines below.
            Container(
              padding: const EdgeInsets.fromLTRB(0, 0, 10, 0),
              decoration: BoxDecoration(
                color: t.surface1.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(
                    color: t.chromeBorder.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 3,
                    height: 22,
                    color: clusterColor ?? Colors.transparent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        activeFilePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.textNormal,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ),
                  Text('+$additions',
                      style: TextStyle(
                        color: t.stateAdded,
                        fontSize: 10,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                  const SizedBox(width: 4),
                  Text('-$deletions',
                      style: TextStyle(
                        color: t.stateDeleted,
                        fontSize: 10,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ],
              ),
            ),
            // Diff lines — each forced to 18px height so DiffLineView's
            // CrossAxisAlignment.stretch row has bounded extent (its
            // contract — `itemExtent: 18` in the changes panel; this
            // SizedBox is the equivalent contract here).
            //
            // Long-diff auto-collapse: when collapsed, simply build
            // *fewer children* via `take(_collapsedLines)`. Earlier
            // attempt used `ConstrainedBox + ClipRect` around a Column
            // of all N children — wrong, because ClipRect only clips
            // rendered output, not the layout pass. The Column's
            // intrinsic height (N × 18 px) still overflowed the
            // constraint and tripped the overflow assertion. Building
            // fewer children means the Column genuinely is short.
            for (final line in (isLong && !_expanded
                    ? lines.take(_collapsedLines)
                    : lines))
              SizedBox(
                height: lineHeight,
                child: DiffLineView(
                  line: line,
                  tokens: t,
                  blameEntry: null,
                  hovered: false,
                  onGutterEnter: null,
                  onGutterExit: () {},
                  searchTerm: '',
                  useAnimatedTextMode: false,
                ),
              ),
            // Footer toggle — same shape as the review pane's
            // collapsible block: full-width row with a thin top
            // divider, mono caret + count, click toggles.
            if (isLong)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: t.surface1.withValues(alpha: 0.4),
                      border: Border(
                        top: BorderSide(
                          color: t.chromeBorder.withValues(alpha: 0.2),
                        ),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        _expanded
                            ? '▲ collapse'
                            : '▼ $hiddenLines more lines',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10,
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReviewForm extends StatefulWidget {
  final void Function(String event, String body) onSubmit;
  const _ReviewForm({required this.onSubmit});
  @override
  State<_ReviewForm> createState() => _ReviewFormState();
}

class _ReviewFormState extends State<_ReviewForm> {
  final TextEditingController _ctrl = TextEditingController();
  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.bg0,
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.pillRadius),
            border:
                Border.all(color: t.chromeBorder.withValues(alpha: 0.3)),
          ),
          child: TextField(
            controller: _ctrl,
            maxLines: 3,
            style: TextStyle(
              color: t.textNormal,
              fontSize: 11,
              fontFamily: 'JetBrainsMono',
              height: 1.4,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: 'leave a note (optional)…',
              hintStyle: TextStyle(
                color: t.textMuted.withValues(alpha: 0.6),
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _ActionButton(
              label: 'comment',
              onTap: () {
                widget.onSubmit('comment', _ctrl.text);
                _ctrl.clear();
              },
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: 'request changes',
              tone: _ActionTone.warning,
              onTap: () {
                widget.onSubmit('request-changes', _ctrl.text);
                _ctrl.clear();
              },
            ),
            const SizedBox(width: 8),
            _ActionButton(
              label: '✓ approve',
              tone: _ActionTone.primary,
              onTap: () {
                widget.onSubmit('approve', _ctrl.text);
                _ctrl.clear();
              },
            ),
          ],
        ),
        // Theme-shader gap so the form breathes the same way the rest
        // of the workplace does (subtle, not loud).
        SizedBox(height: shader.duration.inMilliseconds > 0 ? 4 : 0),
      ],
    );
  }
}

enum _ActionTone { neutral, primary, warning, danger }

class _ActionButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final _ActionTone tone;
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.tone = _ActionTone.neutral,
  });
  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final (fg, bg, border) = switch (widget.tone) {
      _ActionTone.primary => (
          _hovered ? t.bg0 : t.accentBright,
          _hovered
              ? t.accentBright
              : t.accentBright.withValues(alpha: 0.12),
          t.accentBright.withValues(alpha: 0.6),
        ),
      _ActionTone.warning => (
          _hovered ? t.textStrong : t.stateConflicted,
          _hovered
              ? t.stateConflicted.withValues(alpha: 0.18)
              : t.stateConflicted.withValues(alpha: 0.08),
          t.stateConflicted.withValues(alpha: 0.5),
        ),
      _ActionTone.danger => (
          _hovered ? t.bg0 : t.stateDeleted,
          _hovered
              ? t.stateDeleted
              : t.stateDeleted.withValues(alpha: 0.1),
          t.stateDeleted.withValues(alpha: 0.55),
        ),
      _ActionTone.neutral => (
          _hovered ? t.textStrong : t.textNormal,
          _hovered
              ? t.chromeBorder.withValues(alpha: 0.25)
              : t.chromeBorder.withValues(alpha: 0.12),
          t.chromeBorder.withValues(alpha: 0.4),
        ),
    };
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          child: AnimatedContainer(
            duration: context.motion(shader.duration),
            curve: shader.safeCurve,
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(shader.geometry.pillRadius),
              border: Border.all(color: border, width: 1),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: fg,
                fontSize: 10.5,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PrActionToolbar extends StatefulWidget {
  final bool mergeable;
  final bool stateOpen;
  final bool canExportPatch;
  final VoidCallback onCheckout;
  final VoidCallback? onExportPatch;
  final void Function(String method, bool deleteBranch) onMerge;
  const _PrActionToolbar({
    required this.mergeable,
    required this.stateOpen,
    required this.onCheckout,
    required this.onMerge,
    this.canExportPatch = false,
    this.onExportPatch,
  });
  @override
  State<_PrActionToolbar> createState() => _PrActionToolbarState();
}

class _PrActionToolbarState extends State<_PrActionToolbar> {
  bool _showMergePopover = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          const Spacer(),
          if (widget.canExportPatch && widget.onExportPatch != null) ...[
            _ActionButton(
              label: '↓ patch',
              onTap: widget.onExportPatch!,
            ),
            const SizedBox(width: 8),
          ],
          _ActionButton(label: '[c] checkout', onTap: widget.onCheckout),
          if (widget.stateOpen) ...[
            const SizedBox(width: 8),
            // Merge button + popover. The popover positions itself
            // above the button via Overlay so it doesn't push the row.
            _MergeMenuAnchor(
              enabled: widget.mergeable,
              onPick: widget.onMerge,
            ),
          ],
        ],
      ),
    );
  }
}

class _MergeMenuAnchor extends StatefulWidget {
  final bool enabled;
  final void Function(String method, bool deleteBranch) onPick;
  const _MergeMenuAnchor({required this.enabled, required this.onPick});

  @override
  State<_MergeMenuAnchor> createState() => _MergeMenuAnchorState();
}

class _MergeMenuAnchorState extends State<_MergeMenuAnchor> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  bool _deleteBranchAfter = false;

  void _open() {
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(builder: (ctx) {
      final t = ctx.tokens;
      return Stack(
        children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: (_) => _close(),
            ),
          ),
          Positioned(
            child: CompositedTransformFollower(
              link: _link,
              followerAnchor: Alignment.topRight,
              targetAnchor: Alignment.bottomRight,
              offset: const Offset(0, 6),
              child: Material(
                color: Colors.transparent,
                child: IntrinsicWidth(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 200),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(
                          ctx.surfaceShader.geometry.cardRadius),
                      border: Border.all(
                          color: t.chromeBorder.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          // Was hardcoded `Colors.black.withValues(0.35)`,
                          // wrong-tinted on themes with non-black ambient
                          // (Halo gold, Aether blue, Phosphor green).
                          color: t.shadowElev.withValues(alpha: 0.4),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: StatefulBuilder(
                      builder: (ctx, setLocal) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _MergeMenuRow(
                              label: 'merge commit',
                              onTap: () {
                                widget.onPick('merge', _deleteBranchAfter);
                                _close();
                              }),
                          _MergeMenuRow(
                              label: 'squash & merge',
                              onTap: () {
                                widget.onPick(
                                    'squash', _deleteBranchAfter);
                                _close();
                              }),
                          _MergeMenuRow(
                              label: 'rebase & merge',
                              onTap: () {
                                widget.onPick(
                                    'rebase', _deleteBranchAfter);
                                _close();
                              }),
                          Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(
                                  vertical: 4),
                              color: t.chromeBorder
                                  .withValues(alpha: 0.25)),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setLocal(() =>
                                _deleteBranchAfter = !_deleteBranchAfter),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              child: Row(children: [
                                Container(
                                  width: 11,
                                  height: 11,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                        ctx.surfaceShader.geometry.tinyRadius),
                                    border: Border.all(
                                        color: t.chromeBorder
                                            .withValues(alpha: 0.6)),
                                    color: _deleteBranchAfter
                                        ? t.accentBright
                                        : t.accentBright.withValues(alpha: 0),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text('delete branch after',
                                    style: TextStyle(
                                        color: t.textNormal,
                                        fontSize: 10.5)),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    });
    overlay.insert(_entry!);
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: _ActionButton(
        label: '[m] merge ▾',
        tone: _ActionTone.primary,
        onTap: widget.enabled ? _open : () {},
      ),
    );
  }
}

class _MergeMenuRow extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _MergeMenuRow({required this.label, required this.onTap});
  @override
  State<_MergeMenuRow> createState() => _MergeMenuRowState();
}

class _MergeMenuRowState extends State<_MergeMenuRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          color: _hovered
              ? t.accentBright.withValues(alpha: 0.1)
              : t.accentBright.withValues(alpha: 0),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _hovered ? t.textStrong : t.textNormal,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckLine extends StatelessWidget {
  final CheckSummary check;
  const _CheckLine({required this.check});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final color = _checkColor(t, check);
    final glyph = _checkGlyph(check);
    final duration = check.duration;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              glyph,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            child: Text(
              check.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
            ),
          ),
          if (duration != null)
            Text(
              _formatDuration(duration),
              style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontFamily: 'JetBrainsMono',
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentBlock extends StatelessWidget {
  final GhComment comment;
  const _CommentBlock({required this.comment});

  /// Pre-process before handing to [MarkdownBody]:
  ///   * strip `<br/>` / `<br>` (markdown package leaves them as text)
  ///   * unwrap `<details>...</details>` so the contents render inline
  ///     as a slightly muted block (we don't ship a collapsible widget
  ///     for inline markdown; better to show everything than to render
  ///     raw HTML tags as literal text)
  ///   * strip stray `<summary>` / `</summary>` tags
  static String _scrub(String body) {
    var s = body;
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(
        RegExp(r'</?details[^>]*>', caseSensitive: false), '');
    s = s.replaceAll(
        RegExp(r'</?summary[^>]*>', caseSensitive: false), '');
    return s.trim();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('@${comment.authorLogin}',
                style: TextStyle(
                    color: t.accentBright,
                    fontSize: 10.5,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w700)),
            const SizedBox(width: 8),
            Text(_relativeTime(comment.createdAt),
                style: TextStyle(color: t.textMuted, fontSize: 10)),
          ]),
          const SizedBox(height: 4),
          // Themed markdown styling — body in DM Sans (default), code in
          // JetBrainsMono, headings shrink one step from the page chrome
          // so they don't dominate the row, links use accentBright. All
          // colors / spacings pulled from [tokens] so themes carry.
          MarkdownBody(
            data: _scrub(comment.body),
            selectable: true,
            shrinkWrap: true,
            fitContent: true,
            styleSheet: MarkdownStyleSheet(
              // Prose styles inherit the theme's typography family so
              // serif themes (Halo's Playfair, Blackboard's Lora) get
              // their proper face in markdown bodies — not the default
              // DM Sans regardless of theme.
              p: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                height: 1.45,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              h1: TextStyle(
                color: t.textStrong,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              h2: TextStyle(
                color: t.textStrong,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              h3: TextStyle(
                color: t.textStrong,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              h4: TextStyle(
                color: t.textStrong,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              em: TextStyle(
                color: t.textNormal,
                fontStyle: FontStyle.italic,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              strong: TextStyle(
                color: t.textStrong,
                fontWeight: FontWeight.w700,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              code: TextStyle(
                color: t.accentBright,
                fontFamily: 'JetBrainsMono',
                fontSize: 10.5,
                backgroundColor: t.bg0,
              ),
              codeblockDecoration: BoxDecoration(
                color: t.bg0,
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.pillRadius),
                border:
                    Border.all(color: t.chromeBorder.withValues(alpha: 0.3)),
              ),
              codeblockPadding: const EdgeInsets.all(8),
              blockquote: TextStyle(
                color: t.textMuted,
                fontSize: 11,
                fontStyle: FontStyle.italic,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              blockquoteDecoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: t.chromeBorder.withValues(alpha: 0.5),
                    width: 3,
                  ),
                ),
              ),
              blockquotePadding:
                  const EdgeInsets.only(left: 10, top: 2, bottom: 2),
              a: TextStyle(
                color: t.accentBright,
                decoration: TextDecoration.underline,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              listBullet: TextStyle(
                color: t.textNormal,
                fontSize: 11,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              tableHead: TextStyle(
                color: t.textStrong,
                fontWeight: FontWeight.w700,
                fontFamily: context.surfaceShader.geometry.typography,
              ),
              horizontalRuleDecoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: t.chromeBorder.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Issue row — collapsed metric line + expanded thread/actions
// ────────────────────────────────────────────────────────────────────────

class _IssueRow extends StatefulWidget {
  final IssueSummary issue;
  final String viewerLogin;
  final bool expanded;
  final bool focused;
  final IssueDetail? detail;
  final bool detailLoading;
  final bool actionInFlight;
  /// PRs whose body says they close/fix/ref this issue. Derived locally
  /// from cached PR bodies — no extra calls. Renders inline as
  /// "← addressed by #M" chips that jump cross-lens on click.
  final List<PullRequestSummary> addressingPrs;
  final ValueChanged<int> onJumpToPr;
  final VoidCallback onTap;
  final VoidCallback onAssignSelf;
  final VoidCallback onClose;
  final ValueChanged<String> onComment;
  final ValueChanged<String> onAddLabel;

  const _IssueRow({
    required this.issue,
    required this.viewerLogin,
    required this.expanded,
    required this.focused,
    required this.detail,
    required this.detailLoading,
    required this.actionInFlight,
    required this.addressingPrs,
    required this.onJumpToPr,
    required this.onTap,
    required this.onAssignSelf,
    required this.onClose,
    required this.onComment,
    required this.onAddLabel,
  });
  @override
  State<_IssueRow> createState() => _IssueRowState();
}

class _IssueRowState extends State<_IssueRow> {
  bool _hovered = false;
  final TextEditingController _replyCtrl = TextEditingController();

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Color _railColor(AppTokens t) {
    final first = widget.issue.labels.isNotEmpty
        ? widget.issue.labels.first.toLowerCase()
        : '';
    if (first.contains('bug') || first.contains('regression')) {
      return t.stateDeleted;
    }
    if (first.contains('enhancement') || first.contains('feature')) {
      return t.accentBright;
    }
    if (widget.issue.state == 'CLOSED') return t.textMuted;
    return t.textNormal;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final rail = _railColor(t);
    final isAssignedToMe =
        widget.issue.assignees.contains(widget.viewerLogin);
    final isOpen = widget.issue.state == 'OPEN';
    // Same scoping as PR row: toggle GestureDetector wraps only the
    // header Row, leaving the expanded thread + reply field + action
    // toolbar as sole owners of their own pointer events.
    final addressingCount = widget.addressingPrs.length;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Right-edge incoming connector tab (mirror of the PR
            // row's outgoing tab) — "addressed by N PR(s)". Click
            // jumps cross-lens to the first addressing PR.
            if (addressingCount > 0)
              Positioned(
                top: 8,
                bottom: widget.expanded ? null : 8,
                right: 0,
                child: _WorklineConnector(
                  count: addressingCount,
                  direction: _WorklineDirection.incoming,
                  color: t.accentBright,
                  onTap: () =>
                      widget.onJumpToPr(widget.addressingPrs.first.number),
                ),
              ),
            AnimatedContainer(
        duration: context.motion(shader.duration),
        curve: shader.safeCurve,
        padding: EdgeInsets.fromLTRB(
            12, 10, addressingCount > 0 ? 26 : 12, 10),
        decoration: BoxDecoration(
          color: widget.expanded
              ? t.surface1.withValues(alpha: 0.7)
              : (_hovered || widget.focused
                  ? t.surface1.withValues(alpha: 0.45)
                  : t.surface1.withValues(alpha: 0)),
          borderRadius: BorderRadius.circular(
              context.surfaceShader.geometry.cardRadius),
          border: Border(
            left: BorderSide(
              color: rail.withValues(
                  alpha: widget.expanded || widget.focused ? 1.0 : 0.55),
              width: widget.focused || widget.expanded ? 4 : 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1, right: 10),
                      child: Text(
                        '#${widget.issue.number}',
                      style: TextStyle(
                        color: t.textStrong,
                        fontSize: 12,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [
                          FontFeature.tabularFigures()
                        ],
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.issue.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textStrong,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            ...widget.issue.labels,
                            '@${widget.issue.authorLogin}',
                            if (widget.issue.assignees.isNotEmpty)
                              'assigned: ${widget.issue.assignees.map((a) => '@$a').join(', ')}',
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textMuted,
                            fontSize: 10.5,
                            fontFamily: 'JetBrainsMono',
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${widget.issue.commentCount} conv · '
                          '${_relativeTime(widget.issue.updatedAt)}',
                          style: TextStyle(
                            color: t.textMuted.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontFamily: 'JetBrainsMono',
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ],
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 8, top: 1),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: rail.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(
                          context.surfaceShader.geometry.badgeRadius),
                    ),
                    child: Text(
                      widget.issue.state,
                      style: TextStyle(
                        color: rail,
                        fontSize: 9,
                        fontFamily: 'JetBrainsMono',
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                ],
                ),
              ),
            ),
            if (widget.actionInFlight)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _ActionProgressBar(color: t.accentBright),
                ),
              AnimatedSize(
                duration: context.motion(shader.duration),
                curve: shader.safeCurve,
                alignment: Alignment.topCenter,
                child: !widget.expanded
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            if (widget.detail == null &&
                                widget.detailLoading)
                              Text('reading thread…',
                                  style: TextStyle(
                                      color: t.textMuted,
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic))
                            else if (widget.detail == null)
                              Text('no detail available',
                                  style: TextStyle(
                                      color: t.textMuted, fontSize: 11))
                            else ...[
                              // ADDRESSED BY — workline backlinks. PRs
                              // whose body says they close/ref this
                              // issue. Click → cross-lens jump. Lands
                              // FIRST so the reader sees "this is being
                              // worked on" before reading the body.
                              if (widget.addressingPrs.isNotEmpty) ...[
                                _SectionLabel('ADDRESSED BY'),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final p in widget.addressingPrs)
                                      _PrLinkChip(
                                        pr: p,
                                        onTap: () =>
                                            widget.onJumpToPr(p.number),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
                              if (widget.detail!.body.isNotEmpty) ...[
                                _SectionLabel('DESCRIPTION'),
                                const SizedBox(height: 6),
                                _CommentBlock(
                                  comment: GhComment(
                                    authorLogin: widget.issue.authorLogin,
                                    body: widget.detail!.body,
                                    createdAt: widget.issue.updatedAt,
                                  ),
                                ),
                                const SizedBox(height: 6),
                              ],
                              if (widget.detail!.comments.isNotEmpty) ...[
                                _SectionLabel('THREAD'),
                                const SizedBox(height: 6),
                                for (final c in widget.detail!.comments)
                                  _CommentBlock(comment: c),
                                const SizedBox(height: 8),
                              ],
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: t.bg0,
                                  borderRadius: BorderRadius.circular(
                                      context.surfaceShader.geometry.pillRadius),
                                  border: Border.all(
                                      color: t.chromeBorder
                                          .withValues(alpha: 0.3)),
                                ),
                                child: TextField(
                                  controller: _replyCtrl,
                                  maxLines: 2,
                                  // Reply body is prose, not code —
                                  // drop the JetBrainsMono override
                                  // and let the theme's typography
                                  // pick the family.
                                  style: TextStyle(
                                      color: t.textNormal, fontSize: 11),
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: InputBorder.none,
                                    hintText: 'reply…',
                                    hintStyle: TextStyle(
                                      color: t.textMuted
                                          .withValues(alpha: 0.6),
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            // Action gravity — issue toolbar.
                            Row(
                              children: [
                                const Spacer(),
                                if (!isAssignedToMe && isOpen)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: _ActionButton(
                                      label: 'assign me',
                                      onTap: widget.onAssignSelf,
                                    ),
                                  ),
                                if (isOpen)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(right: 8),
                                    child: _ActionButton(
                                      label: 'close',
                                      tone: _ActionTone.danger,
                                      onTap: widget.onClose,
                                    ),
                                  ),
                                _ActionButton(
                                  label: '↩ post',
                                  tone: _ActionTone.primary,
                                  onTap: () {
                                    final body = _replyCtrl.text.trim();
                                    if (body.isEmpty) return;
                                    widget.onComment(body);
                                    _replyCtrl.clear();
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Shared glyph helpers
// ────────────────────────────────────────────────────────────────────────

String _checkGlyph(CheckSummary c) {
  switch (c.conclusion) {
    case 'pass':
    case 'success':
      return '✓';
    case 'fail':
    case 'failure':
    case 'timed_out':
    case 'action_required':
      return '×';
    case 'cancel':
    case 'cancelled':
      return '-';
    case 'skipping':
    case 'skipped':
    case 'neutral':
      return '○';
    default:
      return '●';
  }
}

Color _checkColor(AppTokens t, CheckSummary c) {
  switch (c.conclusion) {
    case 'pass':
    case 'success':
      return t.accentBright;
    case 'fail':
    case 'failure':
    case 'timed_out':
    case 'action_required':
      return t.stateDeleted;
    case 'cancel':
    case 'cancelled':
    case 'skipping':
    case 'skipped':
    case 'neutral':
      return t.textMuted;
    default:
      return t.textNormal;
  }
}

String _reviewerGlyph(String state) {
  switch (state) {
    case 'APPROVED':
      return '✓';
    case 'CHANGES_REQUESTED':
      return '×';
    case 'COMMENTED':
      return '●';
    case 'DISMISSED':
      return '○';
    case 'PENDING':
    default:
      return '◐';
  }
}

Color _reviewerColor(AppTokens t, String state) {
  switch (state) {
    case 'APPROVED':
      return t.accentBright;
    case 'CHANGES_REQUESTED':
      return t.stateDeleted;
    case 'COMMENTED':
      return t.textNormal;
    case 'DISMISSED':
      return t.textMuted;
    case 'PENDING':
    default:
      return t.textMuted;
  }
}

// ────────────────────────────────────────────────────────────────────────
// Empty / loading / gh-missing notices
// ────────────────────────────────────────────────────────────────────────

class _LensLoadingNotice extends StatelessWidget {
  final String label;
  const _LensLoadingNotice({required this.label});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Text(
        label,
        style: TextStyle(
          color: t.textMuted,
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _LensEmptyNotice extends StatelessWidget {
  final String primary;
  final String secondary;
  const _LensEmptyNotice({required this.primary, required this.secondary});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              primary.toUpperCase(),
              style: TextStyle(
                color: t.textNormal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              secondary,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _GhMissingNotice extends StatelessWidget {
  final GhStatus status;
  const _GhMissingNotice({required this.status});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final headline = status.installed
        ? 'gh CLI not authenticated'
        : 'gh CLI not installed';
    final hint = status.installed
        ? 'Run `gh auth login` in a terminal, then refresh this lens.'
        : 'Install from cli.github.com, then `gh auth login`.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              headline.toUpperCase(),
              style: TextStyle(
                color: t.textNormal,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────

String _relativeTime(DateTime t) {
  final delta = DateTime.now().difference(t);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  if (delta.inDays < 7) return '${delta.inDays}d ago';
  if (delta.inDays < 30) return '${(delta.inDays / 7).floor()}w ago';
  if (delta.inDays < 365) return '${(delta.inDays / 30).floor()}mo ago';
  return '${(delta.inDays / 365).floor()}y ago';
}

String _formatDuration(Duration d) {
  if (d.inSeconds < 60) return '${d.inSeconds}s';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}

/// Outcome of a branch-delete attempt, returned from the page state to
/// the row so the row can arm for force / show inline error / refresh.
sealed class _DeleteBranchOutcome {
  const _DeleteBranchOutcome();
  const factory _DeleteBranchOutcome.ok() = _DeleteOk;
  const factory _DeleteBranchOutcome.needsForce() = _DeleteNeedsForce;
  const factory _DeleteBranchOutcome.error(String message) = _DeleteError;
}

class _DeleteOk extends _DeleteBranchOutcome {
  const _DeleteOk();
}

class _DeleteNeedsForce extends _DeleteBranchOutcome {
  const _DeleteNeedsForce();
}

class _DeleteError extends _DeleteBranchOutcome {
  final String message;
  const _DeleteError(this.message);
}

class _BranchCard extends StatefulWidget {
  final BranchInfo branch;
  final AppTokens tokens;
  final bool actionRunning;
  final VoidCallback? onCheckout;
  /// Returns the outcome so the card can morph its trash button into
  /// a force-confirm affordance for unmerged branches, or render an
  /// inline error next to the row instead of in a distant panel.
  final Future<_DeleteBranchOutcome> Function({bool force})? onDelete;
  const _BranchCard(
      {required this.branch,
      required this.tokens,
      required this.actionRunning,
      this.onCheckout,
      this.onDelete});
  @override
  State<_BranchCard> createState() => _BranchCardState();
}

class _BranchCardState extends State<_BranchCard> {
  bool _hovered = false;
  // Two-stage delete state. After a safe `-d` bounces with "not fully
  // merged", the trash icon morphs into a "Force?" affordance armed
  // for one extra tap. Auto-disarms on a timer or hover-out so a
  // forgotten arm doesn't lurk waiting for an accidental click.
  bool _armedForForce = false;
  Timer? _disarmTimer;
  String? _inlineError;

  static const _disarmAfter = Duration(seconds: 5);

  @override
  void dispose() {
    _disarmTimer?.cancel();
    super.dispose();
  }

  void _arm() {
    _disarmTimer?.cancel();
    setState(() {
      _armedForForce = true;
      _inlineError = null;
    });
    _disarmTimer = Timer(_disarmAfter, () {
      if (!mounted) return;
      setState(() => _armedForForce = false);
    });
  }

  void _disarm() {
    _disarmTimer?.cancel();
    if (!_armedForForce) return;
    setState(() => _armedForForce = false);
  }

  Future<void> _handleDelete({bool force = false}) async {
    final fn = widget.onDelete;
    if (fn == null) return;
    final result = await fn(force: force);
    if (!mounted) return;
    switch (result) {
      case _DeleteOk():
        // The list refreshes via the parent; this card unmounts.
        break;
      case _DeleteNeedsForce():
        _arm();
      case _DeleteError(message: final msg):
        _disarmTimer?.cancel();
        setState(() {
          _armedForForce = false;
          _inlineError = msg;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tokens;
    final b = widget.branch;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) {
        setState(() => _hovered = false);
        // Pointer leaving the row resets the armed state — prevents
        // a stray "force-armed" trash button from sitting around for
        // the user to re-trigger by accident.
        _disarm();
      },
      child: AnimatedContainer(
        duration: context.motion(context.surfaceShader.duration),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: b.current
              ? t.accentBright.withValues(alpha: 0.06)
              : (_hovered ? t.itemHoverBg : t.surface1),
          borderRadius:
              BorderRadius.circular(context.surfaceShader.geometry.radius),
          border: Border.all(
            color: b.current
                ? t.accentBright.withValues(alpha: 0.2)
                : t.chromeBorder.withValues(alpha: 0.08),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Branch icon or checkmark
          b.current
              ? AppIcon(name: 'check', size: 12, color: t.accentBright)
              : AppIcon(name: 'git-branch', size: 12, color: t.textMuted),
          const SizedBox(width: 8),
          // Name + tracking
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Row(children: [
                  Flexible(
                    child: Text(
                      b.name,
                      style: TextStyle(
                        color: b.current ? t.textStrong : t.textNormal,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (b.current) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: t.accentBright,
                        borderRadius: BorderRadius.circular(
                            context.surfaceShader.geometry.pillRadius),
                      ),
                      child: Text('HEAD',
                          style: TextStyle(
                              color: t.surface0,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.02)),
                    ),
                  ],
                ]),
                if (b.upstream != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Text(
                      '→ tracking: ${b.upstream}',
                      style: TextStyle(
                          color: t.textMuted,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ])),
          // Ahead/behind indicators
          if (b.ahead > 0)
            Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('${b.ahead}↑',
                    style: TextStyle(color: t.stateAdded, fontSize: 10))),
          if (b.behind > 0)
            Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text('${b.behind}↓',
                    style: TextStyle(color: t.stateModified, fontSize: 10))),
          // Checkout button (invisible but present for current branch — keeps layout stable)
          const SizedBox(width: 8),
          if (!b.current) ...[
            if (widget.onDelete != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: _armedForForce
                    // Armed: trash morphed into "Force?" pill — the
                    // destructive escalation is visible and on-row,
                    // not hidden in an error popup elsewhere.
                    ? _ForceDeletePill(
                        tokens: t,
                        enabled: !widget.actionRunning,
                        onTap: () => _handleDelete(force: true),
                      )
                    : _BranchIconAction(
                        icon: 'trash',
                        enabled: !widget.actionRunning,
                        onTap: () => _handleDelete(),
                      ),
              ),
            SizedBox(
              width: 80,
              height: 24,
              child: _ChromeButton(
                label: 'Checkout',
                compact: true,
                enabled: !widget.actionRunning,
                onPressed: widget.actionRunning ? null : widget.onCheckout,
              ),
            ),
          ],
        ]),
            // Inline error / status under the row instead of in the
            // far-away create-branch panel. Concise — git's hint lines
            // and stderr noise are stripped upstream. Wrapped in a
            // themed danger-tinted container that matches the rest of
            // the app's inline-error pattern.
            //
            // AnimatedSize tweens the row's height when the error
            // appears or disappears, so the row doesn't snap-jump —
            // matches the surrounding hover/state animations and
            // respects the theme's motion tier.
            AnimatedSize(
              duration: context.motion(context.surfaceShader.duration),
              curve: context.surfaceShader.safeCurve,
              alignment: Alignment.topCenter,
              child: _inlineError == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                padding: const EdgeInsets.only(top: 6, left: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.stateConflicted.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(
                        context.surfaceShader.geometry.badgeRadius),
                    border: Border.all(
                      color: t.stateConflicted.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    _inlineError!,
                    style: TextStyle(
                      color: t.stateConflicted,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Trash icon morphed into a destructive "Force?" pill while the row
/// is armed for force-delete. Reads as a clear escalation, not as the
/// safe action the trash icon implies.
class _ForceDeletePill extends StatelessWidget {
  final AppTokens tokens;
  final bool enabled;
  final VoidCallback onTap;
  const _ForceDeletePill({
    required this.tokens,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final shader = context.surfaceShader;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        // AnimatedContainer + theme motion tier so the trash → pill
        // morph matches the rest of the row and respects the theme's
        // motion language (snappy/fluid/elastic).
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: t.stateDeleted.withValues(alpha: 0.18),
            borderRadius:
                BorderRadius.circular(shader.geometry.badgeRadius),
            border: Border.all(
                color: t.stateDeleted.withValues(alpha: 0.55)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(name: 'trash', size: 11, color: t.stateDeleted),
            const SizedBox(width: 5),
            Text(
              'Force?',
              style: TextStyle(
                color: t.stateDeleted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TagCard extends StatelessWidget {
  final TagEntryData tag;
  final AppTokens tokens;
  final bool hovered;
  final bool actionRunning;
  final ValueChanged<bool> onHoverChange;
  final VoidCallback onDelete;
  const _TagCard(
      {required this.tag,
      required this.tokens,
      required this.hovered,
      required this.actionRunning,
      required this.onHoverChange,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    return MouseRegion(
      onEnter: (_) => onHoverChange(true),
      onExit: (_) => onHoverChange(false),
      child: AnimatedContainer(
        duration: context.motion(context.surfaceShader.duration),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius:
              BorderRadius.circular(context.surfaceShader.geometry.radius),
          border: Border.all(color: t.chromeBorder.withValues(alpha: 0.08)),
        ),
        child: Row(children: [
          AppIcon(name: 'tag', size: 12, color: t.textMuted),
          const SizedBox(width: 8),
          Expanded(
              child: Row(children: [
            Flexible(
              child: Text(
                tag.name,
                style: TextStyle(color: t.textNormal, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (tag.targetHash != null) ...[
              const SizedBox(width: 8),
              Text(
                tag.targetHash!,
                style: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.7),
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono'),
              ),
            ],
            if (tag.tagType == 'annotated') ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: t.accentBright.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text('annotated',
                    style: TextStyle(
                        color: t.accentBright,
                        fontSize: 9,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ])),
          if (hovered)
            GestureDetector(
              onTap: actionRunning ? null : onDelete,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text('✕',
                    style: TextStyle(
                        color: t.textMuted.withValues(alpha: 0.6), fontSize: 10)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _ChromeButton extends StatefulWidget {
  final String label;
  final bool enabled;
  final bool compact;
  final VoidCallback? onPressed;

  const _ChromeButton({
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.compact = false,
  });

  @override
  State<_ChromeButton> createState() => _ChromeButtonState();
}

class _ChromeButtonState extends State<_ChromeButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chrome = primaryButtonChrome(
      t,
      hovered: _hovered,
      pressed: _pressed,
      enabled: widget.enabled,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onPressed : null,
        onTapDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.4,
          child: AnimatedScale(
            duration: context.motion(context.surfaceShader.duration),
            scale: chrome.scale,
            child: AnimatedContainer(
              duration: context.motion(context.surfaceShader.duration),
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 10 : 12,
                vertical: widget.compact ? 4 : 6,
              ),
              decoration: BoxDecoration(
                color: chrome.background,
                gradient: chrome.gradient,
                borderRadius: BorderRadius.circular(
                    context.surfaceShader.geometry.pillRadius),
                border: Border.all(color: chrome.borderColor),
                boxShadow: chrome.shadows,
              ),
              alignment: Alignment.center,
              child: Transform.translate(
                offset: chrome.offset,
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: t.btnText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchIconAction extends StatefulWidget {
  final String icon;
  final bool enabled;
  final VoidCallback onTap;

  const _BranchIconAction({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  State<_BranchIconAction> createState() => _BranchIconActionState();
}

class _BranchIconActionState extends State<_BranchIconAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        child: AnimatedContainer(
          duration: context.motion(context.surfaceShader.duration),
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _hovered
                ? t.stateConflicted.withValues(alpha: 0.08)
                : t.stateConflicted.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(
                context.surfaceShader.geometry.badgeRadius),
            border: Border.all(
              color: _hovered
                  ? t.stateConflicted.withValues(alpha: 0.16)
                  : t.stateConflicted.withValues(alpha: 0),
            ),
          ),
          child: Center(
            child: AppIcon(
              name: widget.icon,
              size: 12,
              color: widget.enabled ? t.stateConflicted : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────
// Patch preview overlay — a dialog that renders any unified-diff source
// (an imported .patch/.diff file, a clipboard paste, an AI-generated
// merge resolution, …) using the same DiffLineView we use for PRs.
// Carries a dry-run "cleanly applies?" badge up front so the user never
// blindly apply()s a busted patch.
// ────────────────────────────────────────────────────────────────────────

/// Public opener so features outside branches_page (changes page, etc.)
/// can reuse this surface without depending on private state methods.
/// Parses [rawPatch], runs `git apply --check` to compute the cleanliness
/// badge, and shows the preview. PR-specific signals (CONFLICTS-WITH-YOU,
/// WILL FIGHT) are off by default — they only make sense when the caller
/// is the PR lens with its own PR/repo-state context.
///
/// On successful apply, [onApplied] is invoked so the caller can refresh
/// any dependent state (e.g. working-tree status after a merge resolve).
Future<void> showPatchPreviewDialog(
  BuildContext context, {
  required String repoPath,
  required String rawPatch,
  required String sourceLabel,
  bool filePillsWrap = true,
  /// When true, apply routes through `git apply --cached` — the patch
  /// shapes the INDEX, the working tree stays untouched. Hides the
  /// 3-way and reverse controls since they're meaningless for staging.
  /// Used by NL partial-staging ("shape this commit in English").
  bool stageMode = false,
  /// The set of paths the CALLER expected this patch to touch. When the
  /// parsed patch paths are a proper subset, the dialog renders a loud
  /// reconciliation banner so the user can't miss that some files were
  /// silently dropped — the #1 merge-resolver trust failure. Pass empty
  /// (default) to skip the check (e.g. imported external patches where
  /// "expected" is meaningless).
  Set<String> expectedPaths = const {},
  /// In-place refinement for shape previews. Invoked with the user's
  /// refinement sentence; the caller should dismiss this dialog, re-run
  /// the AI with the original-sentence + refinement bundled, and open a
  /// fresh preview. Typically wired only in stage mode.
  Future<void> Function(String refinement)? onRefine,
  VoidCallback? onApplied,
}) async {
  final lines = rawPatch.length < 32 * 1024
      ? parseUnifiedDiff(rawPatch)
      : await compute(parseUnifiedDiff, rawPatch);
  final parsed = <String, List<ParsedLine>>{};
  for (final l in lines) {
    final key = l.filePath;
    if (key == null) continue;
    (parsed[key] ??= <ParsedLine>[]).add(l);
  }
  if (parsed.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Patch is empty or unparseable.')),
    );
    return;
  }

  final prFiles = <PrFile>[];
  for (final entry in parsed.entries) {
    var adds = 0, dels = 0;
    for (final l in entry.value) {
      if (l.kind == LineKind.added) adds++;
      else if (l.kind == LineKind.deleted) dels++;
    }
    prFiles.add(PrFile(path: entry.key, additions: adds, deletions: dels));
  }

  final check = await applyPatch(
    repoPath,
    rawPatch,
    cached: stageMode,
    dryRun: true,
    telemetryLabel: stageMode ? 'git.shape_check' : 'git.patch_check',
  );
  if (!context.mounted) return;

  final couplingMatrix =
      context.read<FileCouplingState>().matrixFor(repoPath);
  final auroraSource = ValueNotifier<String?>(null);

  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _PatchPreviewDialog(
      sourceLabel: sourceLabel,
      rawPatch: rawPatch,
      prFiles: prFiles,
      filesByPath: parsed,
      dryRunOk: check.ok,
      dryRunError: check.ok ? null : (check.error ?? 'apply --check failed'),
      conflictingPaths: const {},
      fightTitles: const {},
      fightShared: const {},
      fightOrder: const [],
      couplingMatrix: couplingMatrix,
      auroraSource: auroraSource,
      filePillsWrap: filePillsWrap,
      stageMode: stageMode,
      expectedPaths: expectedPaths,
      onRefine: onRefine,
      onApply: ({required bool threeWay, required bool reverse}) async {
        final r = await applyPatch(
          repoPath,
          rawPatch,
          cached: stageMode,
          threeWay: threeWay,
          reverse: reverse,
          telemetryLabel: stageMode
              ? 'git.shape_apply'
              : reverse
                  ? 'git.patch_apply_reverse'
                  : threeWay
                      ? 'git.patch_apply_3way'
                      : 'git.patch_apply',
        );
        if (r.ok && ctx.mounted) {
          await ctx.read<RepositoryState>().refreshStatus();
          onApplied?.call();
        }
        return r;
      },
    ),
  );
  auroraSource.dispose();
}

/// Tiny modal offering the two patch input sources. Returns 'file' or
/// 'clipboard' (or null if dismissed). Kept deliberately minimal — it's
/// a source picker, not a full preview.
class _PatchSourceMenu extends StatelessWidget {
  const _PatchSourceMenu();
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(24),
      child: Center(
        child: MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: context.surfaceShader.geometry.cardRadius,
          elevated: true,
          padding: const EdgeInsets.all(6),
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  child: Text('OPEN PATCH FROM',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      )),
                ),
                _PatchSourceRow(
                  label: 'from file…',
                  hint: '.patch / .diff',
                  onTap: () => Navigator.of(context).pop('file'),
                ),
                _PatchSourceRow(
                  label: 'from clipboard',
                  hint: 'paste text',
                  onTap: () => Navigator.of(context).pop('clipboard'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PatchSourceRow extends StatefulWidget {
  final String label;
  final String hint;
  final VoidCallback onTap;
  const _PatchSourceRow({
    required this.label,
    required this.hint,
    required this.onTap,
  });
  @override
  State<_PatchSourceRow> createState() => _PatchSourceRowState();
}

class _PatchSourceRowState extends State<_PatchSourceRow> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: context.motion(shader.duration),
          curve: shader.safeCurve,
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hover
                ? t.accentBright.withValues(alpha: 0.08)
                : t.accentBright.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(shader.geometry.tinyRadius),
          ),
          child: Row(
            children: [
              Text(widget.label,
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 12,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w600,
                  )),
              const SizedBox(width: 14),
              Text(widget.hint,
                  style: TextStyle(
                    color: t.textMuted,
                    fontSize: 10,
                    fontFamily: 'JetBrainsMono',
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatchPreviewDialog extends StatefulWidget {
  final String sourceLabel;
  final String rawPatch;
  final List<PrFile> prFiles;
  final Map<String, List<ParsedLine>> filesByPath;
  final bool dryRunOk;
  final String? dryRunError;
  final Set<String> conflictingPaths;
  final Map<int, String> fightTitles;
  final Map<int, Set<String>> fightShared;
  final List<int> fightOrder;
  final FileCouplingMatrix? couplingMatrix;
  final ValueNotifier<String?> auroraSource;
  final bool filePillsWrap;
  /// When true, this preview is for a patch that will shape the INDEX,
  /// not the working tree. Changes: apply label ("stage" not "apply"),
  /// hides 3-way + reverse (nonsense for staging).
  final bool stageMode;
  /// Paths the caller EXPECTED the patch to touch. If the parsed patch
  /// paths are a proper subset, a reconciliation banner appears. Empty
  /// = skip the check.
  final Set<String> expectedPaths;
  final Future<GitResult<void>> Function({
    required bool threeWay,
    required bool reverse,
  }) onApply;

  const _PatchPreviewDialog({
    required this.sourceLabel,
    required this.rawPatch,
    required this.prFiles,
    required this.filesByPath,
    required this.dryRunOk,
    required this.dryRunError,
    required this.conflictingPaths,
    required this.fightTitles,
    required this.fightShared,
    required this.fightOrder,
    required this.couplingMatrix,
    required this.auroraSource,
    required this.filePillsWrap,
    required this.onApply,
    this.stageMode = false,
    this.expectedPaths = const {},
    this.onRefine,
  });

  /// In-place refinement for stage-mode shape dialogs. When non-null, a
  /// persistent input bar appears in the footer; on submit, caller is
  /// expected to dismiss this dialog, re-run the AI with the refinement
  /// appended, and open a fresh preview. Saves the dismiss-retype-wait
  /// loop per iteration. Ignored when not in stage mode.
  final Future<void> Function(String refinement)? onRefine;

  @override
  State<_PatchPreviewDialog> createState() => _PatchPreviewDialogState();
}

class _PatchPreviewDialogState extends State<_PatchPreviewDialog> {
  String? _expanded;
  bool _applying = false;
  String? _applyError;
  bool _applied = false;
  bool _reverseArmed = false;

  Future<void> _doApply({required bool threeWay}) async {
    setState(() {
      _applying = true;
      _applyError = null;
    });
    final r =
        await widget.onApply(threeWay: threeWay, reverse: _reverseArmed);
    if (!mounted) return;
    setState(() {
      _applying = false;
      if (r.ok) {
        _applied = true;
      } else {
        _applyError = r.error ?? 'apply failed';
      }
    });
  }

  (int, int) _countsFor(List<ParsedLine> lines) {
    var adds = 0, dels = 0;
    for (final l in lines) {
      if (l.kind == LineKind.added) adds++;
      else if (l.kind == LineKind.deleted) dels++;
    }
    return (adds, dels);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final files = widget.filesByPath.keys.toList()..sort();
    final totalAdds = widget.prFiles.fold<int>(0, (s, f) => s + f.additions);
    final totalDels = widget.prFiles.fold<int>(0, (s, f) => s + f.deletions);
    final clusters = _computeClusters(widget.prFiles, widget.couplingMatrix);
    final ghosts = _resonanceForecast(
      widget.prFiles,
      widget.couplingMatrix,
      engine: () {
        final repo = context.read<RepositoryState>().activePath;
        return repo == null
            ? null
            : context.read<LogosGitState>().engineFor(repo);
      }(),
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 48, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960, maxHeight: 760),
        child: MaterialSurface(
          tone: AppMaterialTone.surface1,
          radius: shader.geometry.cardRadius,
          elevated: true,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text('PATCH PREVIEW',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontFamily: 'JetBrainsMono',
                          fontWeight: FontWeight.w700,
                        )),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(widget.sourceLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textNormal,
                            fontSize: 13,
                            fontFamily: 'JetBrainsMono',
                            fontWeight: FontWeight.w600,
                          )),
                    ),
                    const Spacer(),
                    _ApplyBadge(
                      ok: widget.dryRunOk,
                      error: widget.dryRunError,
                    ),
                    const SizedBox(width: 6),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('×',
                              style: TextStyle(
                                color: t.textMuted,
                                fontSize: 18,
                                fontFamily: 'JetBrainsMono',
                                fontWeight: FontWeight.w700,
                                height: 1.0,
                              )),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                  height: 1,
                  color: t.chromeBorder.withValues(alpha: 0.18)),

              // Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // RECONCILIATION — when the caller said "I expected
                      // this patch to touch paths X" and the parsed patch
                      // touches a subset, surface the gap LOUDLY. This
                      // is the #1 trust failure for AI-generated
                      // resolutions: a green "applies cleanly" badge on
                      // a patch that silently omitted 2 of 12 files.
                      if (widget.expectedPaths.isNotEmpty)
                        Builder(builder: (ctx) {
                          final got = widget.filesByPath.keys.toSet();
                          final missing =
                              widget.expectedPaths.difference(got);
                          if (missing.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _DroppedPathsBanner(
                              missing: missing.toList()..sort(),
                              total: widget.expectedPaths.length,
                            ),
                          );
                        }),
                      // CONFLICTS-WITH-YOU — highest-stakes local signal.
                      if (widget.conflictingPaths.isNotEmpty) ...[
                        _ConflictsWithYouSection(
                            paths: widget.conflictingPaths.toList()..sort()),
                        const SizedBox(height: 10),
                      ],
                      // WILL FIGHT — patch vs open PRs.
                      if (widget.fightOrder.isNotEmpty) ...[
                        _WillFightSection(
                          prTitles: widget.fightTitles,
                          sharedFiles: widget.fightShared,
                          orderedNumbers: widget.fightOrder,
                          onJumpToPr: (_) => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      // FILES header — same "resonance" strip we use in PRs.
                      _FilesSectionHeader(
                        files: widget.prFiles,
                        matrix: widget.couplingMatrix,
                        isWrapped: widget.filePillsWrap,
                        onToggleWrap: () {},
                      ),
                      const SizedBox(height: 6),
                      _FilePillStrip(
                        files: widget.prFiles,
                        activePath: _expanded ?? '',
                        clusterByPath: clusters,
                        heatByPath: const {},
                        ghostPaths: ghosts,
                        auroraSource: widget.auroraSource,
                        couplingMatrix: widget.couplingMatrix,
                        wrapped: widget.filePillsWrap,
                        onSelect: (p) => setState(
                            () => _expanded = _expanded == p ? null : p),
                      ),
                      const SizedBox(height: 10),
                      // Per-file diff blocks — expand via pill click or
                      // block-header click; both routes hit the same
                      // _expanded field so they stay in sync.
                      for (final path in files)
                        _PatchFileBlock(
                          path: path,
                          lines: widget.filesByPath[path]!,
                          expanded: _expanded == path,
                          onToggle: () => setState(() =>
                              _expanded = _expanded == path ? null : path),
                          counts: _countsFor(widget.filesByPath[path]!),
                        ),
                    ],
                  ),
                ),
              ),

              // Footer
              Container(
                  height: 1,
                  color: t.chromeBorder.withValues(alpha: 0.18)),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 14, 12),
                child: Row(
                  children: [
                    Text(
                      '${files.length} file${files.length == 1 ? '' : 's'}'
                      '  ·  +$totalAdds  −$totalDels',
                      style: TextStyle(
                        color: t.textMuted,
                        fontSize: 11,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                    const SizedBox(width: 14),
                    if (_applied)
                      Text(widget.stageMode ? 'staged.' : 'applied.',
                          style: TextStyle(
                            color: t.stateAdded,
                            fontSize: 11,
                            fontFamily: 'JetBrainsMono',
                            fontWeight: FontWeight.w600,
                          ))
                    else if (_applyError != null)
                      Flexible(
                        child: Text(_applyError!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: t.stateConflicted,
                              fontSize: 11,
                              fontFamily: 'JetBrainsMono',
                            )),
                      ),
                    const Spacer(),
                    if (!_applied) ...[
                      // Reverse + 3-way only make sense for patches that
                      // touch the working tree. In stage mode the patch
                      // shapes the index only — undo via `git restore
                      // --staged`, not `-R`, so the toggle is hidden.
                      if (!widget.stageMode) ...[
                        _ReverseToggle(
                          armed: _reverseArmed,
                          onTap: () => setState(
                              () => _reverseArmed = !_reverseArmed),
                        ),
                        const SizedBox(width: 8),
                        _ActionButton(
                          label: _applying ? 'applying…' : 'apply (3-way)',
                          onTap: _applying
                              ? () {}
                              : () => _doApply(threeWay: true),
                        ),
                        const SizedBox(width: 8),
                      ],
                      _ActionButton(
                        label: _applying
                            ? (widget.stageMode ? 'staging…' : 'applying…')
                            : (widget.stageMode ? 'stage' : 'apply'),
                        tone: widget.dryRunOk
                            ? _ActionTone.primary
                            : _ActionTone.neutral,
                        onTap: _applying
                            ? () {}
                            : () => _doApply(threeWay: false),
                      ),
                    ] else
                      _ActionButton(
                        label: 'close',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                  ],
                ),
              ),
              // In-place refinement (stage mode only). Saves 15s per
              // iteration — no dismiss, no retype, no full sentence
              // re-parse. Feeds the refinement back into the caller so
              // it can re-prompt the AI with the original sentence +
              // delta and replace this dialog.
              if (widget.stageMode &&
                  widget.onRefine != null &&
                  !_applied)
                _RefineBar(
                  onSubmit: (text) async {
                    final trimmed = text.trim();
                    if (trimmed.isEmpty) return;
                    Navigator.of(context).pop();
                    await widget.onRefine!(trimmed);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Slim input that sits at the very bottom of the patch preview dialog
/// when shape-mode refinement is wired. Enter dismisses the current
/// preview and hands the sentence to the caller, which re-prompts the
/// AI with the original intent + refinement and opens a fresh preview.
/// A dedicated hairline border separates it from the action footer so
/// it doesn't read as part of the primary action row.
class _RefineBar extends StatefulWidget {
  final Future<void> Function(String) onSubmit;
  const _RefineBar({required this.onSubmit});
  @override
  State<_RefineBar> createState() => _RefineBarState();
}

class _RefineBarState extends State<_RefineBar> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: t.chromeBorder.withValues(alpha: 0.18)),
        ),
        color: t.surface0,
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('↳',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 13,
                fontFamily: 'JetBrainsMono',
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              onSubmitted: (v) => widget.onSubmit(v),
              style: TextStyle(
                color: t.textNormal,
                fontSize: 12,
                fontFamily: 'JetBrainsMono',
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'refine… (e.g. "also drop the logger changes")',
                hintStyle: TextStyle(
                  color: t.textMuted.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontFamily: 'JetBrainsMono',
                  fontStyle: FontStyle.italic,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Arms the `-R` flag for the next apply. Quiet by default; when armed,
/// switches to a warning-toned pill with a leading glyph so the user
/// can't miss that the next click will undo rather than apply.
class _ReverseToggle extends StatefulWidget {
  final bool armed;
  final VoidCallback onTap;
  const _ReverseToggle({required this.armed, required this.onTap});
  @override
  State<_ReverseToggle> createState() => _ReverseToggleState();
}

class _ReverseToggleState extends State<_ReverseToggle> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final shader = context.surfaceShader;
    final accent = widget.armed ? t.stateConflicted : t.textMuted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Tooltip(
          message: widget.armed
              ? 'armed — next apply will REVERT the patch (-R)'
              : 'arm reverse (-R) — undo instead of apply',
          child: AnimatedContainer(
            duration: context.motion(shader.duration),
            curve: shader.safeCurve,
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: widget.armed
                  ? t.stateConflicted.withValues(alpha: 0.12)
                  : (_hover
                      ? t.chromeBorder.withValues(alpha: 0.15)
                      : t.chromeBorder.withValues(alpha: 0)),
              borderRadius:
                  BorderRadius.circular(shader.geometry.badgeRadius),
              border: Border.all(
                color: widget.armed
                    ? t.stateConflicted.withValues(alpha: 0.5)
                    : t.chromeBorder.withValues(alpha: 0.35),
              ),
            ),
            child: Text(widget.armed ? '⟲ reverse ✓' : '⟲ reverse',
                style: TextStyle(
                  color: accent,
                  fontSize: 10.5,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                )),
          ),
        ),
      ),
    );
  }
}

/// Dry-run "cleanly applies?" badge. Green when `git apply --check` says
/// yes, red with a tooltip when no. Lives in the preview header so the
/// user sees it BEFORE picking an apply button.
/// LOUD amber banner shown when the AI's patch omitted files the caller
/// expected it to touch. This is the guardrail against the "AI resolved
/// 10 of 12 conflicts, user clicks apply, the untouched 2 still have
/// markers but got silently `git add`'d" footgun. Spelled out explicitly
/// so there's no way to miss it between the "applies cleanly" badge and
/// the file-pill strip.
class _DroppedPathsBanner extends StatelessWidget {
  final List<String> missing;
  final int total;
  const _DroppedPathsBanner({required this.missing, required this.total});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.stateConflicted.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(
            context.surfaceShader.geometry.pillRadius),
        border: Border(
          left: BorderSide(
            color: t.stateConflicted.withValues(alpha: 0.8),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('⚠ UNTOUCHED',
                  style: TextStyle(
                    color: t.stateConflicted,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  )),
              const SizedBox(width: 8),
              Text(
                  '${missing.length} of $total file${total == 1 ? '' : 's'} not in the patch',
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          const SizedBox(height: 6),
          for (final p in missing)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('· $p',
                  style: TextStyle(
                    color: t.textNormal,
                    fontSize: 11,
                    fontFamily: 'JetBrainsMono',
                  )),
            ),
          const SizedBox(height: 6),
          Text(
              'these files will stay conflicted — applying will not stage them',
              style: TextStyle(
                color: t.textMuted,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              )),
        ],
      ),
    );
  }
}

class _ApplyBadge extends StatelessWidget {
  final bool ok;
  final String? error;
  const _ApplyBadge({required this.ok, required this.error});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final c = ok ? t.stateAdded : t.stateConflicted;
    return Tooltip(
      message: ok
          ? 'git apply --check passed — patch will apply cleanly'
          : (error ?? 'git apply --check failed'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(
              context.surfaceShader.geometry.tinyRadius),
          border: Border.all(color: c.withValues(alpha: 0.45)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(ok ? 'applies cleanly' : 'will not apply',
                style: TextStyle(
                  color: c,
                  fontSize: 10,
                  fontFamily: 'JetBrainsMono',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                )),
          ],
        ),
      ),
    );
  }
}

/// A single file block inside the patch preview. Collapsed by default —
/// header shows path + +/− counts; click to expand and render each
/// ParsedLine via [DiffLineView] (the canonical diff renderer).
class _PatchFileBlock extends StatelessWidget {
  final String path;
  final List<ParsedLine> lines;
  final bool expanded;
  final VoidCallback onToggle;
  final (int, int) counts;

  const _PatchFileBlock({
    required this.path,
    required this.lines,
    required this.expanded,
    required this.onToggle,
    required this.counts,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (adds, dels) = counts;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 6, horizontal: 6),
                child: Row(
                  children: [
                    Text(expanded ? '▾' : '▸',
                        style: TextStyle(
                          color: t.textMuted,
                          fontSize: 10,
                          fontFamily: 'JetBrainsMono',
                        )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(path,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: t.textNormal,
                            fontSize: 12,
                            fontFamily: 'JetBrainsMono',
                          )),
                    ),
                    const SizedBox(width: 10),
                    Text('+$adds',
                        style: TextStyle(
                          color: t.stateAdded,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                        )),
                    const SizedBox(width: 6),
                    Text('−$dels',
                        style: TextStyle(
                          color: t.stateConflicted,
                          fontSize: 11,
                          fontFamily: 'JetBrainsMono',
                        )),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: context.motion(context.surfaceShader.duration),
            curve: context.surfaceShader.safeCurve,
            alignment: Alignment.topCenter,
            child: expanded
                ? Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      color: t.surface0,
                      border: Border.all(
                          color: t.chromeBorder.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(
                          context.surfaceShader.geometry.tinyRadius),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final line in lines)
                          // DiffLineView's internal Row uses stretch
                          // alignment and needs a bounded height from the
                          // parent. DiffShell gives it that via
                          // itemExtent: 18; here we wrap each row in a
                          // fixed-height SizedBox to honour the same
                          // contract — without it the row collapses to
                          // zero height outside a fixed-extent list.
                          SizedBox(
                            height: 18,
                            child: DiffLineView(
                              line: line,
                              tokens: t,
                              blameEntry: null,
                              hovered: false,
                              onGutterEnter: null,
                              onGutterExit: () {},
                              searchTerm: '',
                              useAnimatedTextMode: false,
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
