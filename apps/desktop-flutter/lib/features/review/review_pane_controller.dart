// SPDX-FileCopyrightText: 2026 Woflo Labs
// SPDX-License-Identifier: GPL-3.0-or-later
// Additional permission: Manifold-Woflo Research Components Exception 1.0; see repository-root LICENSE.md.

// review_pane_controller.dart — production glue between ReviewStore and
// the review surfaces.
//
// The widgets stay data-blind (they render ReviewViewBundle) and the
// store stays UI-blind; this controller is the ONLY place that knows
// both worlds. One instance per open desk-PR review pane, owned by the
// branches page and rebuilt on repo switch. Everything here is
// pull-based: the page calls a verb, then reload(), then setState —
// the same evict-and-reload idiom the PR detail cache uses.

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';

import '../../backend/clock.dart';
import '../../backend/desk_pr_diff.dart' show parseNumstatZ;
import '../../backend/git.dart' as git;
import '../../backend/git_result.dart';
import '../../backend/manifold_refs.dart';
import '../../backend/remote_types.dart' show PrFile;
import '../../backend/review_anchor.dart';
import '../../backend/review_last_seen.dart';
import '../../backend/review_records.dart';
import '../../backend/review_store.dart';
import '../diff/diff_models.dart' show sliceDiffByFile;
import 'review_adapter.dart';

/// Byte gate for anchor-resolution blob reads. A review thread's file
/// is read in full (head + merge-base versions) to resolve content
/// anchors; a pathological blob must never become a giant Dart String
/// on the UI's watch. Beyond the gate the file's anchors degrade to
/// `outdated` and its gutter goes read-only — degrade, not die.
const int kReviewFileByteCap = 4 << 20;

/// The content identity a reviewed-bit is ticked against.
///
/// Same FNV-1a and same line split the anchors use, so "this file's
/// content" means exactly one thing across the feature — a second
/// definition here would let a tick and an anchor disagree about
/// whether the file moved.
String fileContentHash(List<String> lines) {
  var h = 0xcbf29ce484222325;
  for (final line in lines) {
    h ^= lineContentHash(line);
    h = h * 0x100000001b3;
  }
  return hex64(h);
}

/// Canonical blob → lines split for anchor capture AND resolution.
/// One splitter, used by every anchor writer in the app, so a line's
/// content hash can never disagree with itself across the capture site
/// and the resolve site. Keeps `\r` (exact content identity — CRLF
/// repos hash their real bytes) and drops only the phantom empty tail
/// a trailing newline produces.
List<String> splitBlobLines(String content) {
  final lines = content.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// A review LENS: a bounded, already-materialized diff between two
/// review snapshots ("since your last look", or round N..M).
///
/// Deliberately NOT a [PullRequestDetail]. The PR's canonical detail
/// feeds the collision map, the conflicts pill, the magnetic shape
/// fingerprint, patch export and AI review — none of which may ever
/// see a lens slice, so a lens can never be installed where one lives.
/// Bounded by construction: a delta between two rounds of one PR that
/// somehow exceeds the app's spill threshold is refused outright
/// rather than spooled, so no lens owns a temp dir or a file handle.
class ReviewLensDiff {
  /// The two-dot spec this lens rendered (`<from>..<to>`).
  final String spec;

  /// Files that differ between the two snapshots. NOT a subset of the
  /// PR's file list: a file changed in round 1 and reverted in round 2
  /// is absent from `base...head` yet present in `R1..R2`.
  final List<PrFile> files;

  /// Per-path raw patch, pre-sliced once at fetch (never per build).
  final Map<String, String> byPath;

  const ReviewLensDiff({
    required this.spec,
    required this.files,
    required this.byPath,
  });

  String diffFor(String path) => byPath[path] ?? '';
}

/// The turn signal a collapsed PR row needs — cheap enough to load for
/// every desk PR in the list (one ref read each, no blob loads).
class ReviewRowSummary {
  final bool yourTurn;
  final String waitingOn;
  final int unresolvedCount;
  const ReviewRowSummary({
    required this.yourTurn,
    required this.waitingOn,
    required this.unresolvedCount,
  });
}

/// Everything one open review pane renders from. Immutable snapshot;
/// verbs go through the controller and produce a fresh one.
class ReviewPaneData {
  final ReviewViewBundle bundle;
  final ReviewState? state;
  final List<ReviewDraftEntry> drafts;

  /// Latest round's number/commit — the round new anchors are captured
  /// against. Round 0 = review exists but no round could be cut (head
  /// branch unresolvable); anchor capture is disabled then.
  final int latestRound;
  final String latestRoundCommit;

  /// The viewer's client-local "last look" pointer, and the pinned
  /// commit it corresponds to (null when the pointer predates the
  /// state doc or was never set).
  final int? lastSeenRound;
  final String? lastSeenCommit;

  const ReviewPaneData({
    required this.bundle,
    required this.state,
    required this.drafts,
    required this.latestRound,
    required this.latestRoundCommit,
    this.lastSeenRound,
    this.lastSeenCommit,
  });

  bool get hasReview => state != null;
  int get draftCount => drafts.length;
}

class ReviewPaneController {
  final String repoPath;
  final int deskId;
  final String headBranch;
  final String baseRef;

  /// The desk PR author's identity — the turn fold's "author" pole.
  final String authorDisplay;

  /// The person at this keyboard, as an identity rather than a name.
  ///
  /// Non-null and non-empty by construction: a controller that exists is
  /// one whose writes can be signed. The caller resolves the human from
  /// git config and simply does not build a pane when git has no
  /// identity to give, so there is no "unsigned write" branch anywhere
  /// downstream to get wrong. Carrying the object (not the display
  /// string) is also what puts the stable [ReviewIdentity.key] into
  /// every record this controller writes.
  final ReviewIdentity viewer;

  /// The display the records and derivations compare on.
  String get viewerDisplay => viewer.display;

  final ReviewStore store;
  final Clock clock;

  ReviewPaneController({
    required this.repoPath,
    required this.deskId,
    required this.headBranch,
    required this.baseRef,
    required this.authorDisplay,
    required this.viewer,
    required ManifoldRefs refs,
    this.clock = const SystemClock(),
  })  : assert(viewer.display.trim().isNotEmpty,
            'a review controller must be able to sign its writes'),
        store = ReviewStore(refs, clock: clock);

  ReviewPaneData? data;

  /// New-side file lines, cached for anchor capture at gutter-tap time.
  /// Keyed by repo-relative path; a null value means "read, unavailable"
  /// (over the byte cap, absent at this commit) — cached so a hover-heavy
  /// session doesn't re-probe a huge file on every pass.
  final Map<String, List<String>?> _headLines = {};

  /// Merge-base file lines (the old side of the PR diff), for old-side
  /// capture and old-side anchor resolution.
  final Map<String, List<String>?> _baseLines = {};

  /// The commit blob reads resolve against — the LATEST ROUND'S PIN, not
  /// the branch tip. Load-bearing for anchor honesty: [captureAnchor]
  /// records `commit: latestRoundCommit`, so the content it hashes has to
  /// come from that exact commit. Reading `<branch>:<path>` instead would
  /// mint anchors whose recorded commit and hashed bytes disagree the
  /// moment a commit lands between the round cut and the tap — a peer
  /// resolving against the pin would then see `outdated` for a line that
  /// is perfectly present. Falls back to the branch only before any round
  /// exists (where capture is refused anyway).
  String _headSpec = '';
  String? _mergeBase;

  /// Cache identity: blobs stay valid while both endpoints hold.
  String? _blobCacheKey;

  // ─── Loading ─────────────────────────────────────────────────────

  Future<List<String>?> _blobLines(String spec) async {
    final size = await git.gitBlobSize(repoPath, spec);
    if (size == null || size > kReviewFileByteCap) return null;
    final bytes = await git.gitBlobBytes(repoPath, spec);
    if (bytes == null) return null;
    return splitBlobLines(utf8.decode(bytes, allowMalformed: true));
  }

  /// The old side of the PR diff. Mirrors [fetchLocalDeskPrDetail]'s
  /// three-dot rule AND its degrade: with no merge base (unrelated
  /// histories) the diff falls back to the two-dot `base..head`, whose
  /// old side is [baseRef] itself — so old-side anchors follow it there
  /// instead of going dark.
  Future<String> _resolveOldSide() async {
    final r = await git
        .runGit(repoPath, ['merge-base', baseRef, headBranch]);
    final oid =
        r.exitCode == 0 ? (r.stdout as String).trim() : '';
    return oid.isEmpty ? baseRef : oid;
  }

  Future<List<String>?> _ensureHeadLines(String path) async {
    if (_headLines.containsKey(path)) return _headLines[path];
    return _headLines[path] = await _blobLines('$_headSpec:$path');
  }

  Future<List<String>?> _ensureBaseLines(String path) async {
    if (_baseLines.containsKey(path)) return _baseLines[path];
    final mb = _mergeBase ??= await _resolveOldSide();
    return _baseLines[path] = await _blobLines('$mb:$path');
  }

  /// Serializes [load]. Every verb reloads, so two quick actions put two
  /// traversals in flight over the SAME mutable controller state
  /// (`_headSpec`, the blob caches) — one clearing the cache the other
  /// is mid-read of, and the slower one landing last with the older
  /// snapshot. Queuing makes both hazards unrepresentable instead of
  /// guarded: each load runs alone and starts AFTER the write that asked
  /// for it, which coalescing could not promise.
  Future<void> _loadGate = Future<void>.value();

  /// Run [body] alone, after everything already queued on the gate.
  ///
  /// One helper rather than the three-line queue idiom pasted per verb:
  /// the paste is why [setFileReviewed] and [reviewedNow] were outside
  /// the gate at all while touching the very caches it exists to
  /// protect. Callers must not nest — every gated entry point is called
  /// from the page, never from inside another one.
  Future<T> _gated<T>(Future<T> Function() body) {
    final prior = _loadGate;
    final mine = Completer<void>();
    _loadGate = mine.future;
    return prior.then((_) => body()).whenComplete(mine.complete);
  }

  /// Full pane refresh: cut a round if the head moved (the "look"
  /// moment IS the round boundary), then read state + drafts, resolve
  /// every anchored file's content, and fold it all into views.
  Future<GitResult<ReviewPaneData>> load() => _gated(_load);

  Future<GitResult<ReviewPaneData>> _load() async {
    // Round hygiene is gated on the review EXISTING: merely opening a
    // desk PR must not mint review refs (state doc + round pin) for
    // every desk the viewer glances at. The first real intent — a
    // gutter tap that needs an anchor round — goes through
    // [ensureRound] instead.
    var stateR = await store.read(deskId);
    if (!stateR.ok) return GitResult.err(stateR.error ?? 'read failed');
    if (stateR.data != null) {
      // Advisory: a deleted/unborn head branch must not blank the
      // pane — the review's history is still readable without a fresh
      // round, so a cut failure degrades to "no new round".
      final cut = await store.cutRoundIfMoved(
        deskId: deskId,
        branch: headBranch,
        by: viewer,
        authorDisplay: authorDisplay,
      );
      // Re-read ONLY when a round actually landed. The steady state (a
      // pane reloading after every verb, head unmoved) is by far the
      // common one, and it now costs one ref read instead of two.
      if (cut.ok && cut.data != null) {
        stateR = await store.read(deskId);
        if (!stateR.ok) return GitResult.err(stateR.error ?? 'read failed');
      }
    }
    final state = stateR.data;

    final draftsR = await store.listDrafts(deskId);
    if (!draftsR.ok) {
      return GitResult.err(draftsR.error ?? 'drafts failed');
    }
    final drafts = draftsR.data!;

    final latest = state?.latestRound;
    _headSpec = latest?.commit.isNotEmpty == true
        ? latest!.commit
        : headBranch;
    // Blobs are immutable at a pinned commit, so the cache survives every
    // verb-then-reload cycle and only dies when an endpoint actually
    // moves (a new round cut, or a rebased base). Clearing per load made
    // each Done/reply/publish re-read every anchored file.
    final cacheKey = '$_headSpec|$baseRef';
    if (_blobCacheKey != cacheKey) {
      _blobCacheKey = cacheKey;
      _headLines.clear();
      _baseLines.clear();
      _mergeBase = null;
    }

    final newPaths = <String>{};
    final oldPaths = <String>{};
    // Content is needed ONLY to resolve a line anchor. Reading a blob to
    // decide anything about a FILE scope would defeat the reason
    // captureFile exists: it is available on files a line anchor refuses,
    // which is to say the huge ones and the binary ones, and pulling
    // those through the content path on every pane load is exactly the
    // unbudgeted ingestion this codebase has been burned by.
    var wantsFileScopes = false;
    void want(ReviewScope scope) {
      switch (scope) {
        case LineScope(anchor: final a):
          (a.side == 'old' ? oldPaths : newPaths).add(a.path);
        case FileScope():
          wantsFileScopes = true;
        case WholeScope():
          break;
      }
    }

    for (final t in state?.threads ?? const <ReviewThreadRecord>[]) {
      want(t.scope);
    }
    for (final d in drafts) {
      final scope = d.scope;
      if (scope != null) want(scope);
    }
    final currentFiles = <String, List<String>>{};
    for (final p in newPaths) {
      final lines = await _ensureHeadLines(p);
      if (lines != null) currentFiles[p] = lines;
    }
    final oldFiles = <String, List<String>>{};
    for (final p in oldPaths) {
      final lines = await _ensureBaseLines(p);
      if (lines != null) oldFiles[p] = lines;
    }

    // What a file-scoped thread is still about: MEMBERSHIP IN THE
    // CHANGE, not existence in a tree.
    //
    // The distinction is the finding. "This file should not be in this
    // change" is a claim about the diff, and a file the author reverted
    // to its base content still exists in HEAD and in the base while
    // having left the diff completely — so an existence probe reported
    // the thread as current about code the change no longer touches.
    //
    // NOT SIDED, and that is the correction to the first version of this.
    // Membership is a property of the PATH: if it is in the diff, a
    // thread about it is live, whichever version the thread names. The
    // side exists so content resolution knows which tree to read, and
    // borrowing it to classify membership meant inferring status from
    // line counts — where a file that only DELETES lines is
    // indistinguishable from a DELETED file, and a binary file is
    // indistinguishable from anything, which is exactly the case this
    // scope was built to serve.
    //
    // Null means COULD NOT DETERMINE, and the adapter leaves such threads
    // alone rather than decaying them. A transient git failure must not
    // quietly restate itself as "none of these files are in the change
    // any more", which is a lie with the shape of a fact.
    Set<String>? changedPaths;
    if (wantsFileScopes) {
      final r = await git.getRangeNumstatZ(
          repoPath, '$baseRef...$headBranch',
          findRenames: true);
      if (r.ok) {
        changedPaths = {for (final f in parseNumstatZ(r.data ?? '')) f.path};
      }
    }

    final lastSeenN =
        await ReviewLastSeen.read(repoPath: repoPath, deskId: deskId);
    // What this viewer has already been shown. Seeded once from the
    // legacy (round, seq) pointer on the first load after upgrading, so
    // an in-flight review does not re-announce its whole history.
    var seen = await ReviewLastSeen.readSeen(
        repoPath: repoPath, deskId: deskId);
    if (seen.isEmpty && lastSeenN != null && state != null) {
      seen = await ReviewLastSeen.seedSeen(
        repoPath: repoPath,
        deskId: deskId,
        state: state,
        lastSeenRound: lastSeenN,
        lastSeenSeq: await ReviewLastSeen.readSeq(
            repoPath: repoPath, deskId: deskId, round: lastSeenN),
      );
    }
    // The commit the viewer's last-seen round pinned. Drives the
    // "since last look" DIFF lens; unread comments are answered by the
    // seen set and no longer by a moment in time.
    String? lastSeenCommit;
    if (lastSeenN != null && state != null) {
      for (final r in state.rounds) {
        if (r.n == lastSeenN) {
          lastSeenCommit = r.commit;
        }
      }
    }

    // Counted through the SAME spec the lens renders, so the header's
    // "N files since your last look" can never disagree with what the
    // lens actually shows.
    var filesSince = 0;
    final sinceSpec = _specSince(lastSeenCommit);
    if (sinceSpec != null) filesSince = await _countChangedFiles(sinceSpec);

    final bundle = buildReviewViews(
      state ?? ReviewState.fresh(deskId, clock.now()),
      viewerDisplay: viewerDisplay,
      authorDisplay: authorDisplay,
      currentFiles: currentFiles,
      oldFiles: oldFiles,
      changedPaths: changedPaths,
      drafts: drafts,
      filesSinceLastLook: filesSince,
      seenComments: seen,
    );
    data = ReviewPaneData(
      bundle: bundle,
      state: state,
      drafts: drafts,
      latestRound: latest?.n ?? 0,
      latestRoundCommit: latest?.commit ?? '',
      lastSeenRound: lastSeenN,
      lastSeenCommit: lastSeenCommit,
    );
    return GitResult.ok(data!);
  }

  Future<int> _countChangedFiles(String spec) async {
    final r = await git.getRangeNumstatZ(repoPath, spec, findRenames: true);
    if (!r.ok) return 0;
    // Through the canonical parser: hand-splitting the -z stream on NUL
    // and counting TABs over-counts any path that contains a TAB (legal
    // in git) and mis-walks rename triples.
    return parseNumstatZ(r.data ?? '').length;
  }

  // ─── Lenses ──────────────────────────────────────────────────────

  /// `<last-seen pin>..<head pin>`, or null when there's nothing behind
  /// the viewer (never looked, or already caught up). TWO-dot on
  /// purpose: the lens compares two trees the viewer knows — "what I
  /// reviewed" against "what exists now". Three-dot (merge-base
  /// scoping) is the PR-diff rule and would hide a rebase's
  /// incorporated upstream from the very lens meant to surface it.
  String? _specSince(String? lastSeenCommit) {
    if (lastSeenCommit == null || lastSeenCommit.isEmpty) return null;
    if (_headSpec.isEmpty || lastSeenCommit == _headSpec) return null;
    return '$lastSeenCommit..$_headSpec';
  }

  String? get sinceLastLookSpec => _specSince(data?.lastSeenCommit);

  /// `<pin(from)>..<pin(to)>` for a round comparison, or null when
  /// either round has no recorded pin.
  String? compareSpec(int from, int to) {
    final rounds = data?.state?.rounds ?? const <ReviewRoundInfo>[];
    String? pin(int n) {
      for (final r in rounds) {
        if (r.n == n) return r.commit.isEmpty ? null : r.commit;
      }
      return null;
    }

    final a = pin(from);
    final b = pin(to);
    if (a == null || b == null || a == b) return null;
    return '$a..$b';
  }

  /// Materialize a lens for [spec]. Refused (ok(null)) when the delta
  /// exceeds the app's spill threshold — a lens is a reading aid, not a
  /// second machine-scale diff pipeline, and the caller falls back to
  /// the full PR diff rather than holding a spool it would have to own.
  @useResult
  Future<GitResult<ReviewLensDiff?>> loadLens(String spec) async {
    final numstat =
        await git.getRangeNumstatZ(repoPath, spec, findRenames: true);
    if (!numstat.ok) {
      return GitResult.err(numstat.error ?? 'lens numstat failed');
    }
    final files = parseNumstatZ(numstat.data ?? '');
    final spooled =
        await git.spoolRangeDiff(repoPath, spec, findRenames: true);
    if (!spooled.ok || spooled.data == null) {
      return GitResult.err(spooled.error ?? 'lens diff failed');
    }
    final spool = spooled.data!;
    try {
      if (spool.byteLength > git.kDetailDiffSpillBytes) {
        return const GitResult.ok(null);
      }
      final raw = spool.byteLength == 0
          ? ''
          : await git.readSpoolStringLenient(spool.path);
      return GitResult.ok(ReviewLensDiff(
        spec: spec,
        files: files,
        byPath: sliceDiffByFile(raw),
      ));
    } finally {
      // The lens NEVER retains the spool — no temp dir outlives this
      // call, so no lens participates in detail eviction at all.
      await spool.dispose();
    }
  }

  // ─── Bootstrap ───────────────────────────────────────────────────

  /// First-intent bootstrap: make sure a round exists to anchor against
  /// (cutting round 1 creates the state doc as a side effect). [load]
  /// deliberately never does this — looking is free; intending to
  /// comment is what starts a review.
  @useResult
  Future<GitResult<ReviewPaneData>> ensureRound() async {
    final d = data;
    if (d != null && d.latestRound > 0) return GitResult.ok(d);
    final cut = await store.cutRoundIfMoved(
      deskId: deskId,
      branch: headBranch,
      by: viewer,
      authorDisplay: authorDisplay,
    );
    if (!cut.ok) return GitResult.err(cut.error ?? 'round cut failed');
    return load();
  }

  // ─── Anchor capture (gutter taps) ────────────────────────────────

  /// Capture a content anchor for [line] (1-based) on [side] of
  /// [path]. Returns null when the file's content isn't available
  /// (over the byte gate, binary-ish, or no round exists yet) — the
  /// caller renders the affordance disabled, never a broken anchor.
  /// Serialized against [load] for the same reason loads are serialized
  /// against each other: both touch `_headSpec` and the blob caches. A
  /// round cut landing mid-capture could otherwise let lines fetched
  /// from the OLD commit be stamped with the NEW commit's id — an
  /// anchor whose recorded commit does not contain the bytes it hashed,
  /// which is precisely the dishonesty pinning reads to the round was
  /// meant to prevent.
  Future<ReviewAnchor?> captureAt({
    required String path,
    required String side,
    required int line,
  }) =>
      _gated(() => _captureAt(path: path, side: side, line: line));

  /// The scope for a comment on [path] as a whole, or null when no round
  /// has been cut and nothing when the path is on neither side.
  ///
  /// Reads no file CONTENT: a file scope makes no claim about any line,
  /// so there is nothing to hash and nothing to slip. Two size probes,
  /// which is why it is available on files [captureAt] refuses — one over
  /// the byte gate, or binary — exactly where "this file should not be in
  /// this change" is most likely to be the comment.
  ///
  /// SERIALIZED against [load], for the same reason [captureAt] is. This
  /// began as a synchronous read of the cached pin and genuinely had no
  /// in-flight window; discovering the side added two awaits, and with
  /// them exactly the hazard the gate exists for — a round cut landing
  /// between the snapshot and the probes would stamp the scope with one
  /// round while deciding its side from another's tree. A scope whose
  /// recorded commit is not the tree it was captured against is the same
  /// dishonesty pinning reads to the round was meant to prevent.
  ///
  /// The SIDE is discovered here rather than taken from the caller. No
  /// caller can know it: the changed-file records carry additions and
  /// deletions and no status, so the UI was passing 'new' unconditionally
  /// and a comment on a deleted file was born outdated — about the one
  /// file most likely to deserve a whole-file comment. Head first, then
  /// the merge base, so a file the change deleted resolves against the
  /// version that still contains it.
  Future<FileScope?> captureFile({required String path}) =>
      _gated(() => _captureFile(path: path));

  Future<FileScope?> _captureFile({required String path}) async {
    final d = data;
    if (d == null || d.latestRound == 0) return null;
    FileScope at(String side) => FileScope(
          path: path,
          side: side,
          round: d.latestRound,
          commit: d.latestRoundCommit,
        );
    if (await git.gitBlobSize(repoPath, '$_headSpec:$path') != null) {
      return at('new');
    }
    final mb = _mergeBase ??= await _resolveOldSide();
    if (await git.gitBlobSize(repoPath, '$mb:$path') != null) {
      return at('old');
    }
    // On neither side: there is no file here to be about.
    return null;
  }

  /// The scope for a comment on the change itself, or null when no round
  /// has been cut.
  ///
  /// Still round-pinned. "This is two changes in one branch" is a claim
  /// about a particular state of the branch, and a reader three rounds
  /// later deserves to know which one — the same honesty a line anchor
  /// gets from its commit.
  WholeScope? captureReview() {
    final d = data;
    if (d == null || d.latestRound == 0) return null;
    return WholeScope(round: d.latestRound, commit: d.latestRoundCommit);
  }

  Future<ReviewAnchor?> _captureAt({
    required String path,
    required String side,
    required int line,
  }) async {
    final d = data;
    if (d == null || d.latestRound == 0) return null;
    final lines = side == 'old'
        ? await _ensureBaseLines(path)
        : await _ensureHeadLines(path);
    if (lines == null || line < 1 || line > lines.length) return null;
    return captureAnchor(
      lines: lines,
      lineIndex: line - 1,
      round: d.latestRound,
      commit: d.latestRoundCommit,
      path: path,
      side: side,
    );
  }

  // ─── Verbs (page idiom: null = ok, message = failure) ────────────

  /// Draft a new thread about [scope].
  ///
  /// Takes the sealed scope rather than an anchor, so "comment on this
  /// line", "comment on this file" and "comment on this change" are one
  /// verb with one draft batch, one publish, and one set of merge rules —
  /// rather than three code paths that would each have to be taught
  /// privacy, resolution and turn-taking separately.
  Future<String?> saveOpenerDraft({
    required ReviewScope scope,
    required String body,
  }) async {
    final r = await store.saveDraft(
      deskId,
      ReviewDraftEntry(
        threadId: '',
        scope: scope,
        body: body,
        at: clock.now(),
      ),
    );
    return r.ok ? null : (r.error ?? 'draft save failed');
  }

  Future<String?> saveReplyDraft({
    required String threadId,
    required String body,
  }) async {
    final r = await store.saveDraft(
      deskId,
      ReviewDraftEntry(
        threadId: threadId,
        scope: null,
        body: body,
        at: clock.now(),
      ),
    );
    return r.ok ? null : (r.error ?? 'draft save failed');
  }

  Future<String?> resolve(String threadId, {required String how}) async {
    final r = await store.resolveThread(
        deskId: deskId, threadId: threadId, by: viewer, how: how);
    return r.ok ? null : (r.error ?? 'resolve failed');
  }

  Future<String?> reopen(String threadId) async {
    final r = await store.reopenThread(
        deskId: deskId, threadId: threadId, by: viewer);
    return r.ok ? null : (r.error ?? 'reopen failed');
  }

  /// Drop one draft. [threadId] is '' for an opener draft.
  Future<String?> discardOneDraft({
    required String threadId,
    required String body,
    required DateTime at,
  }) async {
    final r = await store.discardDraft(
      deskId,
      ReviewDraftEntry(
          threadId: threadId, scope: null, body: body, at: at),
    );
    return r.ok ? null : (r.error ?? 'discard failed');
  }

  Future<String?> discardDrafts() async {
    final r = await store.discardDrafts(deskId);
    return r.ok ? null : (r.error ?? 'discard failed');
  }

  /// Publish the draft batch (and/or a verdict) as one turn, then move
  /// the viewer's last-look pointer to the round they just spoke to —
  /// publishing IS the "I have looked" event.
  Future<String?> publish({String? verdict}) async {
    final d = data;
    final r = await store.publish(
      deskId: deskId,
      author: viewer,
      authorDisplay: authorDisplay,
      verdict: verdict,
      verdictRound: d?.latestRound,
    );
    if (!r.ok) return r.error ?? 'publish failed';
    final n = d?.latestRound ?? 0;
    if (n > 0) {
      // The sequence the viewer had actually SEEN — the state they were
      // looking at when they published, not the state that came back.
      //
      // Publishing merges: a peer's reply can land in the same write, and
      // taking the post-merge maximum would mark their words read before
      // this viewer had been shown a single one of them. Their own new
      // comments need no cursor (rung 1 of the unread ladder: your own
      // words are never new to you), so the loaded state is exactly the
      // right high-water mark and nothing is lost by stopping there.
      await ReviewLastSeen.write(
          repoPath: repoPath, deskId: deskId, round: n);
      // Everything the viewer was LOOKING AT when they published — the
      // state they had loaded, not the one that came back. Publishing
      // merges, and a peer's reply landing in the same write has never
      // been on this screen.
      await _recordSeen(d?.state);
    }
    return null;
  }

  /// Step out of the attention set without publishing — "not blocking
  /// on me". The manual half of "auto-maintained, manually adjustable":
  /// a rule that cannot be overridden has to be right every time, and
  /// this one sometimes will not be.
  Future<String?> stepOutOfAttention() async {
    final r = await store.setAttention(
      deskId: deskId,
      display: viewerDisplay,
      inSet: false,
      by: viewer,
    );
    return r.ok ? null : (r.error ?? 'attention update failed');
  }

  /// Everyone this review can be handed to right now: the people in
  /// the conversation, minus the viewer (stepping out is its own verb)
  /// and minus anyone already being waited on (handing someone the ball
  /// they are already holding is a no-op that looks like a control).
  List<String> get handOffCandidates {
    final s = data?.state;
    if (s == null) return const [];
    final blocked = s.attentionOn;
    return [
      for (final p in participantsOf(s, authorDisplay))
        if (p != viewerDisplay && !blocked.contains(p)) p,
    ];
  }

  /// Hand the review to someone by name — the explicit hand-back the
  /// turn fold was documented as waiting for.
  Future<String?> handTo(String display) async {
    final r = await store.setAttention(
      deskId: deskId,
      display: display,
      inSet: true,
      by: viewer,
    );
    return r.ok ? null : (r.error ?? 'attention update failed');
  }

  /// Mark (or unmark) a file as reviewed at its CURRENT content.
  ///
  /// The hash is what makes the tick self-invalidating: it records what
  /// was actually read, so the author's next edit to that file makes
  /// the tick stale on every clone without anyone clearing it.
  /// Outcome of a reviewed-bit write.
  ///
  /// `unreadable` is its own answer rather than folded into success or
  /// into an error string: the tick returned the page's "ok" sentinel
  /// on a file it had refused to write, so tapping the checkbox on a
  /// deleted, renamed, or over-cap file did nothing at all — no tick,
  /// no message — while the identical control on the file beside it
  /// worked. Distinguishing it is what lets the page say which.
  Future<({bool unreadable, String? error})> setFileReviewed(
    String path, {
    required bool reviewed,
  }) =>
      _gated(() => _setFileReviewed(path, reviewed: reviewed));

  Future<({bool unreadable, String? error})> _setFileReviewed(
    String path, {
    required bool reviewed,
  }) async {
    final d = data;
    if (d == null) return (unreadable: false, error: null);
    final lines = await _ensureHeadLines(path);
    // A file we cannot read is a file we cannot honestly call reviewed.
    // Un-ticking never needs the content: it writes an empty hash.
    if (lines == null && reviewed) {
      return (unreadable: true, error: null);
    }
    final r = await store.setFileReviewed(
      deskId: deskId,
      reviewer: viewerDisplay,
      path: path,
      contentHash: reviewed ? fileContentHash(lines!) : '',
      round: d.latestRound,
    );
    return (
      unreadable: false,
      error: r.ok ? null : (r.error ?? 'reviewed bit failed'),
    );
  }

  /// Which of [paths] the viewer has ticked AT THEIR CURRENT CONTENT.
  ///
  /// A tick whose recorded hash no longer matches the file is silently
  /// absent rather than shown — the invalidation the research names as
  /// the difference between this and GitHub's "viewed".
  Future<Set<String>> reviewedNow(Iterable<String> paths) =>
      _gated(() => _reviewedNow(paths));

  Future<Set<String>> _reviewedNow(Iterable<String> paths) async {
    final mine = data?.state?.reviewedFiles[viewerDisplay];
    if (mine == null || mine.isEmpty) return const {};
    final out = <String>{};
    for (final path in paths) {
      final bit = mine[path];
      if (bit == null || bit.contentHash.isEmpty) continue;
      final lines = await _ensureHeadLines(path);
      if (lines == null) continue;
      if (fileContentHash(lines) == bit.contentHash) out.add(path);
    }
    return out;
  }

  /// Mark every comment in [state] as shown to this viewer.
  ///
  /// Takes the state the viewer HAD, so a caller must pass its loaded
  /// snapshot rather than a fresher one — the whole point is that a
  /// comment which arrived during the write was never on screen.
  Future<void> _recordSeen(ReviewState? state) async {
    if (state == null) return;
    final ids = <String>{
      for (final t in state.threads)
        for (final c in t.comments) reviewCommentIdentity(c),
    };
    if (ids.isEmpty) return;
    await ReviewLastSeen.addSeen(
        repoPath: repoPath, deskId: deskId, identities: ids);
  }

  /// Explicit "caught up" — the header verb for a look that ends
  /// without anything to say.
  ///
  /// Page idiom: null is success, a message is failure. This used to
  /// return `Future<void>`, which made it the one verb in the pane with
  /// no way to fail out loud: a prefs write that threw escaped into an
  /// unawaited callback, the pill stayed on screen, the lens kept
  /// offering the same delta, and nothing said the pointer had not
  /// moved.
  Future<String?> markCaughtUp() async {
    final n = data?.latestRound ?? 0;
    // No round means no snapshot to be caught up TO. Nothing to write
    // and nothing wrong, so the caller reloads and the pill goes away.
    if (n <= 0) return null;
    try {
      await ReviewLastSeen.write(
          repoPath: repoPath, deskId: deskId, round: n);
      await _recordSeen(data?.state);
      return null;
    } catch (e) {
      return '$e';
    }
  }
}


/// Collapsed-row turn chips for every desk that actually HAS a review.
///
/// One `for-each-ref` over the review namespace first, then a state read
/// only for the desks it names: a repo with fifty desks and no reviews
/// costs ONE git spawn, not fifty. (Reading blindly per desk also made
/// the cost scale with desk count rather than with review count, which
/// is backwards — reviews are the rarer thing.)
Future<Map<int, ReviewRowSummary>> loadReviewRowSummaries({
  required ManifoldRefs refs,
  required Iterable<({int deskId, String author})> desks,
  required String viewerDisplay,
}) async {
  final wanted = {for (final d in desks) d.deskId: d.author};
  if (wanted.isEmpty) return const {};

  final store = ReviewStore(refs);
  final listed = await store.listReviewedDeskIds();
  if (!listed.ok) return const {};
  final reviewed = listed.data!.where(wanted.containsKey);
  if (reviewed.isEmpty) return const {};

  final out = <int, ReviewRowSummary>{};
  for (final deskId in reviewed) {
    final r = await store.read(deskId);
    if (!r.ok || r.data == null) continue;
    final state = r.data!;
    final turn = deriveTurn(state,
        authorDisplay: wanted[deskId]!, viewerDisplay: viewerDisplay);
    out[deskId] = ReviewRowSummary(
      yourTurn: turn.yourTurn,
      waitingOn: turn.waitingOn,
      unresolvedCount: state.unresolvedCount,
    );
  }
  return out;
}
