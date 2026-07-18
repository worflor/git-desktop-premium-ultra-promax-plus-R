import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'repository_xray.dart';
import 'repository_xray_strings.dart';
import 'dtos.dart';
import 'git_diff_paths.dart' show unCQuoteGitPath;
import 'git_result.dart';
import 'merge_session.dart';
import 'process_utils.dart';
import 'win_job_object.dart';
import '../diagnostics/diagnostics_state.dart';

// ---------------------------------------------------------------------------
// Subprocess seam
// ---------------------------------------------------------------------------

/// The single point every `git` subprocess in this library passes through.
///
/// Two reasons it exists. First, counting: [GitSpawn.runCount] +
/// [GitSpawn.startCount] let a test assert that a flow spawns exactly N
/// subprocesses, which is a deterministic, zero-variance proxy for the work
/// the flow does — far more stable than a wall-clock budget. Second,
/// injection: [GitSpawn.runOverride] / [GitSpawn.startOverride] let a test
/// script a failing, hanging, or partially-writing `git` without a real
/// process, so the retry/decode/recovery paths below can be exercised
/// directly instead of hoped about.
///
/// Both overrides are null in production and the counters are two integer
/// increments, so the cost on the hot path is nil.
@visibleForTesting
class GitSpawn {
  GitSpawn._();

  /// Replaces the `Process.run` spawn. Receives the argv (without the
  /// leading `git`). Must return raw-byte stdout/stderr, exactly as the
  /// real call does (`stdoutEncoding: null`).
  static Future<ProcessResult> Function(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
  })?
  runOverride;

  /// Replaces the `Process.start` spawn.
  static Future<Process> Function(
    List<String> args, {
    String? workingDirectory,
    Map<String, String>? environment,
    ProcessStartMode mode,
  })?
  startOverride;

  static int runCount = 0;
  static int startCount = 0;

  /// Total subprocesses spawned since the last [reset].
  static int get totalCount => runCount + startCount;

  /// Clears counters AND overrides. Call in `tearDown` so one test's
  /// injected fault can never leak into the next.
  static void reset() {
    runCount = 0;
    startCount = 0;
    runOverride = null;
    startOverride = null;
  }
}

/// Spawns `git [args]` and collects raw bytes. Every `Process.run` in this
/// library goes through here — see [GitSpawn].
Future<ProcessResult> _spawnRunRaw(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  GitSpawn.runCount++;
  final override = GitSpawn.runOverride;
  if (override != null) {
    return override(
      args,
      workingDirectory: workingDirectory,
      environment: environment,
    );
  }
  return Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    environment: environment,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
}

/// Spawns `git [args]` as a streamed process. Every `Process.start` in this
/// library goes through here — see [GitSpawn].
///
/// [environment] defaults to [_kNonInteractiveGitEnv]. Two call sites
/// (`git patch-id`, `git cat-file --batch`) historically passed no
/// environment at all and so inherited the ambient one, silently opting out
/// of `GIT_TERMINAL_PROMPT=0` / `LC_ALL=C`. Defaulting here closes that gap
/// without those call sites having to remember.
Future<Process> _spawnStart(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
  ProcessStartMode mode = ProcessStartMode.normal,
}) {
  GitSpawn.startCount++;
  final env = environment ?? _kNonInteractiveGitEnv;
  final override = GitSpawn.startOverride;
  if (override != null) {
    return override(
      args,
      workingDirectory: workingDirectory,
      environment: env,
      mode: mode,
    );
  }
  return Process.start(
    'git',
    args,
    workingDirectory: workingDirectory,
    environment: env,
    mode: mode,
  );
}

// Git emits two header forms:
//   unquoted: `diff --git a/path b/path`
//   quoted:   `diff --git "a/path with spaces" "b/path with spaces"` (C-string
//             quoted when the path contains spaces or non-ASCII).
// These helpers are the single source of truth so every caller handles both;
// previous duplicated regexes covered only the unquoted form and silently
// missed renamed-with-spaces paths.

final RegExp _kDiffHeaderUnquoted = RegExp(
  r'^diff --git a/.+ b/(.+)$',
  multiLine: true,
);
final RegExp _kDiffHeaderQuoted = RegExp(
  r'^diff --git "a/[^"]+" "b/([^"]+)"$',
  multiLine: true,
);
final RegExp _kDiffHeaderUnquotedLine = RegExp(r'^diff --git a/.+ b/(.+)$');
final RegExp _kDiffHeaderQuotedLine = RegExp(
  r'^diff --git "a/[^"]+" "b/([^"]+)"$',
);

/// Returns every touched (b-side) path across the full unified diff text,
/// handling both unquoted and C-string-quoted forms.
Set<String> extractDiffTouchedPaths(String diffText) {
  final paths = <String>{};
  for (final m in _kDiffHeaderUnquoted.allMatches(diffText)) {
    paths.add(m.group(1)!);
  }
  for (final m in _kDiffHeaderQuoted.allMatches(diffText)) {
    paths.add(m.group(1)!);
  }
  return paths;
}

/// Parses a single line as a git diff header. Returns the b-side path
/// if it matches either form, else null. Use inside a per-line scan
/// (e.g. to track `currentFile` while walking the diff).
String? diffHeaderPath(String line) {
  final u = _kDiffHeaderUnquotedLine.firstMatch(line);
  if (u != null) return u.group(1);
  final q = _kDiffHeaderQuotedLine.firstMatch(line);
  if (q != null) return q.group(1);
  return null;
}

// ── Error classification ───────────────────────────────────────────────
// Raw git stderr is precise but user-hostile. Every mutating command fails
// for a small set of recurring reasons; naming them lets the UI lead with a
// short, honest line while keeping the raw output one tap away. We never hide
// what git actually said (command transparency is what earns trust) — we just
// stop making a wall of porcelain the headline.

/// The kind of failure a git command hit, inferred from exit code + stderr.
enum GitErrorCategory {
  /// Credentials rejected or missing — HTTP 401/403, ssh publickey, or a
  /// non-interactive session with prompts disabled.
  auth,

  /// A server-side hook (pre-receive / update) declined the push.
  hookRejected,

  /// The remote moved on: push rejected as non-fast-forward, including a
  /// stale `--force-with-lease`.
  nonFastForward,

  /// Couldn't reach the remote at all — DNS, TLS, connection, or timeout.
  network,

  /// The working tree or index has conflicts, or the op would overwrite
  /// local changes.
  conflict,

  /// Anything else. [GitFailure.message] carries the first stderr line.
  other,
}

/// A classified git failure: a [category], a short human [message] safe to
/// headline in a toast, and the raw [detail] (trimmed stderr) preserved for
/// the secondary "show me exactly what git said" affordance.
class GitFailure {
  final GitErrorCategory category;
  final String message;
  final String detail;
  const GitFailure(this.category, this.message, this.detail);
}

/// Classify [stderr] (optionally with the process [exitCode]) into a
/// [GitFailure]. Match order is specificity-first: auth failures and hook
/// rejections both surface as generic "failed to push", so they are tested
/// before the non-fast-forward catch, and conflict last so a push rejection
/// mentioning nothing about merges doesn't get miscoded.
GitFailure classifyGitError(String stderr, {int? exitCode}) {
  final raw = stderr.trim();
  final s = raw.toLowerCase();
  bool has(String needle) => s.contains(needle);

  if (has('authentication failed') ||
      has('could not read username') ||
      has('could not read password') ||
      has('invalid username or password') ||
      has('permission denied (publickey') ||
      has('access denied') ||
      has('terminal prompts disabled') ||
      has('error: 403') ||
      has('http basic: access denied') ||
      (has('permission to') && has('denied'))) {
    return GitFailure(GitErrorCategory.auth, 'Authentication failed.', raw);
  }

  if (has('hook declined') ||
      has('pre-receive hook') ||
      has('push declined') ||
      (has('[remote rejected]') && has('hook'))) {
    return GitFailure(
      GitErrorCategory.hookRejected,
      'Remote rejected the push (hook).',
      raw,
    );
  }

  if (has('could not resolve host') ||
      has('could not resolve proxy') ||
      has('connection timed out') ||
      has('operation timed out') ||
      has('network is unreachable') ||
      has('connection refused') ||
      has('failed to connect') ||
      has("couldn't connect to server") ||
      has('temporary failure in name resolution') ||
      has('ssl certificate problem') ||
      has('unable to access')) {
    return GitFailure(GitErrorCategory.network, "Can't reach the remote.", raw);
  }

  if (has('non-fast-forward') ||
      has('fetch first') ||
      has('failed to push some refs') ||
      has('tip of your current branch is behind') ||
      has('updates were rejected') ||
      has('stale info') ||
      has('! [rejected]')) {
    return GitFailure(
      GitErrorCategory.nonFastForward,
      'Remote has newer commits. Pull first.',
      raw,
    );
  }

  if (has('conflict') ||
      has('needs merge') ||
      has('unmerged') ||
      has('would be overwritten') ||
      has('overwritten by') ||
      has('your local changes') ||
      has('fix conflicts') ||
      has('automatic merge failed') ||
      has('patch does not apply')) {
    return GitFailure(
      GitErrorCategory.conflict,
      'Conflicts need resolving.',
      raw,
    );
  }

  final firstLine = raw.isEmpty
      ? 'Command failed.'
      : raw
            .split('\n')
            .firstWhere(
              (l) => l.trim().isNotEmpty,
              orElse: () => 'Command failed.',
            )
            .trim();
  return GitFailure(GitErrorCategory.other, firstLine, raw);
}

/// Classification of a failed [GitResult]. Null for successes, so callers can
/// write `result.failure?.message` and fall through to the ok path.
extension GitResultClassification<T> on GitResult<T> {
  GitFailure? get failure => ok ? null : classifyGitError(error ?? '');
}

/// Decode outcome: the decoded text, plus whether strict UTF-8 failed
/// (bytes contained invalid sequences) and the byte offset of the first
/// malformed sequence. The flag lets callers emit a lifecycle event so
/// a lossy fallback is never silent in telemetry.
class _GitDecodeOutcome {
  final String text;
  final bool lenientFallback;
  final int? malformedAtOffset;
  const _GitDecodeOutcome(
    this.text,
    this.lenientFallback,
    this.malformedAtOffset,
  );
}

/// Commands whose stdout is known-ASCII structured data (SHAs, ref
/// names, boolean flags). Malformed UTF-8 here doesn't mean "binary
/// patch payload" — it means real ref/config corruption, which should
/// surface as a hard failure, not a silent U+FFFD substitution that
/// lets downstream code consume garbage as though it were valid.
///
/// Deliberately narrow: only subcommands where we're confident the
/// output is purely machine-structured. Anything that can embed commit
/// messages, file content, config values, paths (when `core.quotePath`
/// is off), or user-supplied strings stays in the lenient bucket, since
/// those legitimately carry non-UTF-8 bytes in real repos.
const Set<String> _kStrictDecodeSubcommands = {
  'rev-parse',
  'rev-list',
  'symbolic-ref',
  'merge-base',
  'check-ref-format',
};

/// Subcommands that are **always** read-only regardless of their
/// flags — no matter what arg combination you throw at them they
/// never mutate the repo. Safe to deduplicate two concurrent calls
/// with byte-identical args into a single subprocess.
///
/// Conservative by design: anything that CAN mutate under some
/// flag (branch -D, tag -d, worktree add, stash push, remote add,
/// etc.) stays out even though many of their args are read-only —
/// the cost of a false dedup is correctness loss; the cost of a
/// missed dedup is just paying for one more subprocess spawn.
const Set<String> _kDedupableSubcommands = {
  'rev-parse',
  'rev-list',
  'symbolic-ref',
  'merge-base',
  'check-ref-format',
  'check-ignore',
  'check-attr',
  'cat-file',
  'log',
  'show',
  'diff',
  'blame',
  'grep',
  'status',
  'ls-files',
  'ls-tree',
  'ls-remote',
  'describe',
  'for-each-ref',
};

/// Config-immunity pins for any `git diff`/`git show` whose stdout is parsed
/// as a unified-diff body. Each of `color.diff` (ANSI escapes on +/- lines),
/// `diff.external` (body replaced wholesale by an ext-diff tool), and
/// `diff.mnemonicPrefix`/`diff.noprefix`/`diff.srcPrefix` (header prefixes
/// rewritten to `i/`w/`c/` or dropped) can reshape that body out from under
/// the parser. These force the canonical, machine-stable form regardless of
/// the repo's / user's config, making the whole reshape class unrepresentable.
const List<String> _kDiffContentPins = [
  '--no-color',
  '--no-ext-diff',
  '--src-prefix=a/',
  '--dst-prefix=b/',
];

/// The `diff`/`show` subcommand tokens for every textual-diff call site, with
/// `diff.binary` force-disabled. A user's `[diff] binary = true` makes every
/// binary change emit its full base85 payload inline — a multi-GB blob
/// becomes a multi-GB stdout String, and the churn-based spool gates cannot
/// see it coming because `--numstat` reports `-` (parsed as 0) for binaries.
/// Pinning it off keeps the binary case at its canonical one-line
/// `Binary files a/x and b/x differ` form on every path, spooled or not —
/// the in-app binary renderer reads blobs directly and never consumes patch
/// payloads. Same config-immunity doctrine as [_kDiffContentPins]; `-c` is a
/// GLOBAL git flag that must precede the subcommand, which is why these
/// spreads carry the subcommand token itself.
const List<String> _kDiffCmd = ['-c', 'diff.binary=false', 'diff'];
const List<String> _kShowCmd = ['-c', 'diff.binary=false', 'show'];

/// Pins for every `git log` invocation whose stdout feeds a fixed-layout
/// parser (`_parseCommitLogLines`' 8-line records, `bulkGetCommitDetails`'
/// `>>>`-delimited records, `listCommitsAhead`, `listFileHistoryWithPaths`).
/// `log.showSignature=true` injects `gpg:` lines that shift those records;
/// `--no-show-signature` forces the canonical form regardless of the user's
/// config. Centralized here (matching [_kDiffContentPins]) so a new commit-log
/// call site spreads one source of truth instead of re-typing the literal —
/// the argv-lint law in hostile_gitconfig_differential_test still fails any
/// site that omits it.
const List<String> _kCommitLogPins = ['--no-show-signature'];

/// Request-coalescing cache for concurrent identical git reads.
/// Keyed by a **length-prefixed** encoding of workingDir and every
/// arg — see [_gitDedupKey]. Length prefixes make the key injection-
/// proof: no sequence of bytes inside a real path or arg can forge
/// a boundary, so two calls with different `(workingDir, args)`
/// tuples can never collide. Earlier separator-based designs (NUL,
/// SOH, tab) either tripped git's binary-file heuristic or relied
/// on a "never appears in practice" assumption that is just waiting
/// to be disproven by a path with an unusual character.
///
/// Entries live **only** while the subprocess is in flight — the
/// finalizer at [_git]'s `whenComplete` removes the key, so a later
/// call after the state has changed never shares a stale result.
///
/// **Snapshot semantics (important for the working-tree readers
/// in [_kDedupableSubcommands] — `status`, `diff`, `log`, `show`,
/// `blame`, `ls-files`, `grep` etc.)**: when caller B arrives while
/// caller A's subprocess is still running, B receives A's result.
/// If the filesystem mutates between A's spawn and B's arrival, B
/// observes the PRE-MUTATION state that A captured, not a fresh
/// snapshot at B's wall-clock. In the UI this collapses into a
/// one-refresh-cycle staleness window — the next call (after A
/// completes and its key is cleared) spawns a fresh subprocess that
/// sees the mutation. The guarantee is "two identical concurrent
/// calls see the same bytes," not "each call sees an FS snapshot
/// taken at its own send time." Callers that genuinely need the
/// stricter guarantee should force a fresh spawn by varying an
/// arg (e.g. including a nonce) or by awaiting the previous call
/// before issuing the next.
///
/// Why this matters: startup telemetry shows six `git.status`, three
/// `git.worktree`, and two `git.log` calls firing within a single
/// millisecond at app launch. On Windows, each subprocess spawn costs
/// ~100ms of OS overhead; half a dozen in flight turns into p95
/// blow-up via OS scheduler thrashing + antivirus file-system scans.
/// (Grimoire Circle CVIII: second-moment curse. Circle CIX: fanout
/// multiplies tail risk.) Coalescing identical concurrent reads
/// collapses that burst without changing semantics.
final Map<String, Future<ProcessResult>> _inflightGitReads = {};

/// Caps concurrent git subprocess spawns. Multiple git processes hitting
/// the same pack files cause OS-scheduler thrashing and antivirus fan-out
/// on Windows — telemetry shows 8 simultaneous calls ballooning from
/// ~200ms each to ~7700ms each. Six still leaves headroom for bursty
/// probes without dropping back to mostly-serial throughput.
/// Initial / fallback git-subprocess concurrency. The LIVE limit is derived
/// per-machine by [GitConcurrencyController] (it holds git latency at the
/// Kleinrock ρ=½ power optimum); this is just where the controller starts and
/// the value the fixed-max (test) semaphores use.
@visibleForTesting
const int gitSubprocessMaxConcurrency = 6;

final _gitSubprocessSemaphore = GitSubprocessSemaphore(
  gitSubprocessMaxConcurrency,
  controller: GitConcurrencyController(gitSubprocessMaxConcurrency),
);

@visibleForTesting
class GitSubprocessSemaphore {
  GitSubprocessSemaphore(this._max, {GitConcurrencyController? controller})
    : _controller = controller {
    if (_max < 1) {
      throw ArgumentError.value(_max, 'max', 'must be at least 1');
    }
  }

  // Live limit. Fixed for the bare (test) constructor; driven by the optional
  // [_controller] in production via [observe], so the cap is derived from
  // measured latency instead of hardcoded.
  int _max;
  final GitConcurrencyController? _controller;
  int _active = 0;
  int _peakActive = 0;
  final _waiters = <Completer<void>>[];

  @visibleForTesting
  int get activeCount => _active;

  @visibleForTesting
  int get queuedCount => _waiters.length;

  /// High-water mark of concurrently-held permits since the last
  /// [resetPeakActiveCount]. Lets a test prove throttling is real — that a
  /// burst of acquirers never drove [activeCount] past the live ceiling.
  @visibleForTesting
  int get peakActiveCount => _peakActive;

  @visibleForTesting
  void resetPeakActiveCount() => _peakActive = _active;

  void _onActiveIncremented() {
    if (_active > _peakActive) _peakActive = _active;
  }

  Future<void> acquire() {
    if (_active < _max) {
      _active++;
      _onActiveIncremented();
      return Future.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future;
  }

  void release() {
    if (_active <= 0) {
      throw StateError('Semaphore released without an active permit.');
    }
    _active--;
    // Recovery path (additive-increase): every release — including ordinary,
    // un-observed `_gitRaw` traffic — nudges the adaptive limit back toward the
    // ceiling, so a depression from a past contended grep burst can't throttle
    // ordinary git indefinitely. Paired with the multiplicative shrink in
    // [observe], this is AIMD.
    final ctrl = _controller;
    if (ctrl != null) {
      ctrl.recover();
      _max = ctrl.limit;
    }
    _drainWaiters();
  }

  // Wake queued acquirers up to the current limit. Each freed permit is
  // reserved before its waiter is completed (the waiter resumes on a later
  // microtask), so new acquirers can't cut the queue. Loops because the
  // adaptive limit can grow between calls.
  void _drainWaiters() {
    while (_waiters.isNotEmpty && _active < _max) {
      _active++;
      _onActiveIncremented();
      _waiters.removeAt(0).complete();
    }
  }

  /// Feed one git call's observed service latency to the adaptive controller
  /// (if any) and adopt its derived limit. Called by [withGitSubprocessLimit].
  void observe(Duration serviceLatency) {
    final c = _controller;
    if (c == null) return;
    c.observe(serviceLatency);
    _max = c.limit;
    _drainWaiters(); // the limit may have grown
  }
}

/// Derives the git-subprocess concurrency *operating point* instead of fixing
/// it. Holds median git-call service latency at ~2× its learned uncontended
/// floor — Kleinrock's M/M/1 power optimum (ρ=½, where throughput/latency
/// peaks) — so it shrinks under contention toward the thrash-safe point.
///
/// [ceiling] is a SAFETY RAIL, not the tuning: the telemetry-justified cap
/// ([gitSubprocessMaxConcurrency]) the controller never exceeds. Going ABOVE
/// it is unvalidated — only the fan-out greps feed the latency signal
/// ([observe]); the un-observed `_gitRaw` burst it also governs can't be
/// calibrated on, so the limit must not push that burst past the documented
/// thrash threshold on a machine where greps happen not to inflate. Recovery
/// is symmetric, though: every git release (incl. `_gitRaw`) nudges the limit
/// back up via [recover], so a depression from one contended burst doesn't
/// strand ordinary traffic — multiplicative-decrease on observed contention,
/// additive-increase on all traffic (AIMD). The tuning's only constant is the
/// ρ=½ theorem; the operating point is derived per-machine from measured
/// latency, between 1 and the rail. (A direct power hill-climb finds the same
/// point noise-free but wanders under real latency noise — this latency
/// set-point stays stable; validated by simulation against this repo's
/// measured git-latency curve.)
class GitConcurrencyController {
  GitConcurrencyController(int ceiling)
    : _ceiling = ceiling.clamp(1, 64).toDouble(),
      _limit = ceiling.clamp(1, 64).toDouble();
  final double _ceiling;
  double _limit;
  double _ema = 0;
  double _floor = double.infinity;

  void observe(Duration serviceLatency) {
    final l = serviceLatency.inMicroseconds.toDouble();
    if (l <= 0) return;
    _ema = _ema == 0 ? l : 0.7 * _ema + 0.3 * l;
    // Windowed uncontended floor: the recent-minimum service time, slowly
    // forgetting old minima (×1.0005/call ≈ a ~1400-call window) so the
    // baseline re-learns if the machine genuinely speeds up or slows down.
    _floor = math.min(l, _floor * 1.0005);
    // gradient = floor/ema. The ρ=½ power optimum is latency = 2×floor ⇔
    // gradient = 0.5. Move the limit multiplicatively toward it; the ^0.25
    // damping keeps it stable (no hunting) under noisy readings.
    final gradient = (_floor / _ema).clamp(0.05, 1.0);
    final factor = math.pow(gradient / 0.5, 0.25).toDouble();
    _limit = (_limit * factor).clamp(1.0, _ceiling);
  }

  /// Additive-increase recovery: nudge the limit a hair back toward the
  /// ceiling. Called on every git release (not just the observed greps), so
  /// ordinary traffic lifts a limit depressed by a past contended burst. Tiny
  /// per call; the sharp multiplicative shrink in [observe] dominates while
  /// contention persists, so the operating point holds during a real burst.
  void recover() {
    _limit = math.min(_ceiling, _limit * 1.01);
  }

  int get limit => _limit.round();

  @visibleForTesting
  double get rawLimit => _limit;
}

/// Zone marker: present + true while an async call chain already holds a git
/// permit, so a nested [withGitSubprocessLimit] reuses it instead of acquiring
/// a second one and self-deadlocking under a low limit.
final Object _gitPermitZoneKey = Object();

/// Run [task] under the shared git-subprocess limit — the same
/// [GitSubprocessSemaphore] the other throttled git paths use, driven
/// adaptively by [GitConcurrencyController]. Use this to throttle ad-hoc
/// fan-outs of git subprocesses — e.g. a parallel batch of `git grep` — so
/// they don't thrash the OS scheduler / antivirus on Windows (see the
/// semaphore note above). NOTE: it governs only semaphore-gated git, not the
/// un-throttled `_runGitCommand` callers. Re-entrant: nesting reuses the held
/// permit rather than acquiring a second, so a low derived limit can't
/// self-deadlock.
///
/// FOOTGUN: the re-entrancy guard only covers a nested `withGitSubprocessLimit`
/// — `_gitRaw` (the path every `_git(...)` call takes) acquires the semaphore
/// UNCONDITIONALLY without checking the zone. So calling a semaphore-gated
/// `_git`-based function from inside a `task` here takes a SECOND permit and
/// can self-deadlock once the derived limit drops to 1. Only wrap calls that
/// bypass the semaphore (today: ai.dart's `_runGitCommand` greps).
Future<T> withGitSubprocessLimit<T>(Future<T> Function() task) async {
  // Already holding a permit on this async chain — run directly. Acquiring a
  // second permit under a low limit would deadlock against the one we hold.
  if (Zone.current[_gitPermitZoneKey] == true) return task();
  await _gitSubprocessSemaphore.acquire();
  final sw = Stopwatch()..start();
  try {
    return await runZoned(task, zoneValues: {_gitPermitZoneKey: true});
  } finally {
    // Feed the call's service latency to the adaptive controller, then
    // release — the limit it derives takes effect on this drain.
    _gitSubprocessSemaphore.observe(sw.elapsed);
    _gitSubprocessSemaphore.release();
  }
}

/// Live active-permit count on the shared production semaphore — the one every
/// throttled git spawn (including ai.dart's, via [withGitSubprocessLimit])
/// contends for. Lets a test assert the permit is released on every exit path.
@visibleForTesting
int gitSubprocessActiveForTesting() => _gitSubprocessSemaphore.activeCount;

/// High-water concurrency on the shared production semaphore since the last
/// [resetGitSubprocessPeakForTesting]. A test fires a burst of git runs and
/// asserts this never exceeded the ceiling.
@visibleForTesting
int gitSubprocessPeakForTesting() => _gitSubprocessSemaphore.peakActiveCount;

@visibleForTesting
void resetGitSubprocessPeakForTesting() =>
    _gitSubprocessSemaphore.resetPeakActiveCount();

String _gitDedupKey(String workingDir, List<String> args) {
  // Length-prefixed concatenation: each field is emitted as
  // `"${length}:${field}"`. Decoding is unambiguous — read the
  // digits up to the colon, read exactly that many chars, repeat —
  // so two distinct `(workingDir, args)` tuples can never produce
  // the same string. This matters because the dedupable subcommand
  // list includes `log`, `diff`, `show`, and `grep`, whose args can
  // legally carry user-supplied paths, pathspecs, and format
  // strings with arbitrary bytes (tabs in POSIX paths, tabs in
  // `--pretty=format:%h\t%s`, etc). Any fixed-character separator
  // would be a latent collision waiting on the right input.
  final buf = StringBuffer()
    ..write(workingDir.length)
    ..write(':')
    ..write(workingDir);
  for (final arg in args) {
    buf
      ..write(arg.length)
      ..write(':')
      ..write(arg);
  }
  return buf.toString();
}

bool _isDedupableGitCall(List<String> args) {
  final sub = _gitSubcommandToken(args);
  if (sub == null) return false;
  return _kDedupableSubcommands.contains(sub);
}

/// Git accepts global options before the subcommand (e.g. `git -C <dir>
/// rev-parse HEAD`, `git --git-dir=<path> rev-list`, `git -c foo=bar
/// status`). A naive `args.first` check would classify such a call as
/// lenient even though the real subcommand is strict-eligible. Walk
/// past every leading global option to find the subcommand token.
///
/// Global options per `man git(1)` that take values as a separate
/// argument: `-C`, `-c`, `--exec-path=` (only when given without `=`),
/// `--git-dir`, `--work-tree`, `--namespace`, `--super-prefix`,
/// `--config-env`. Attached-value forms (`--foo=bar`, `-C<path>`) are
/// a single token and are skipped by the prefix check.
String? _gitSubcommandToken(List<String> args) {
  var i = 0;
  while (i < args.length) {
    final a = args[i];
    if (!a.startsWith('-')) return a; // positional → this is the subcommand
    // Boolean-only global flags: consume one slot.
    const boolFlags = {
      '-p',
      '-P',
      '--paginate',
      '--no-pager',
      '--bare',
      '--no-replace-objects',
      '--literal-pathspecs',
      '--glob-pathspecs',
      '--noglob-pathspecs',
      '--icase-pathspecs',
      '-h',
      '--help',
      '--version',
    };
    if (boolFlags.contains(a)) {
      i++;
      continue;
    }
    // Value-taking flags when split across two args: `-C <dir>` style.
    const splitFlags = {
      '-C',
      '-c',
      '--exec-path',
      '--git-dir',
      '--work-tree',
      '--namespace',
      '--super-prefix',
      '--config-env',
    };
    if (splitFlags.contains(a)) {
      i += 2;
      continue;
    }
    // Attached-value form (`-C<dir>`, `--git-dir=<path>`, `-cfoo=bar`)
    // — single token, just advance past it.
    i++;
  }
  return null;
}

/// Decodes git stdout/stderr bytes as UTF-8. Behavior depends on
/// [strict]:
///   • strict=true  — throw `FormatException` on any malformed byte.
///     Used for structural commands where U+FFFD substitution would
///     silently corrupt a parser that expects exact bytes.
///   • strict=false — attempt strict first, fall back to lenient
///     decode on FormatException. Used for content-bearing commands
///     (diff, show, log, grep, cat-file, ls-files when paths may be
///     raw) where non-UTF-8 bytes are legitimate and blocking on them
///     would kill the flow.
_GitDecodeOutcome _decodeGitBytes(Object? raw, {required bool strict}) {
  if (raw is! List<int>) {
    return _GitDecodeOutcome(raw?.toString() ?? '', false, null);
  }
  if (strict) {
    // Propagate FormatException to caller; no fallback. The outer
    // catch turns this into a `git.invoke_failed` lifecycle event
    // with the malformed-byte offset preserved in the message.
    return _GitDecodeOutcome(utf8.decode(raw), false, null);
  }
  try {
    return _GitDecodeOutcome(utf8.decode(raw), false, null);
  } on FormatException catch (e) {
    return _GitDecodeOutcome(
      utf8.decode(raw, allowMalformed: true),
      true,
      e.offset,
    );
  }
}

/// Environment overlaid on every git subprocess we spawn (matches what VS
/// Code sets). Passed via `environment:` WITHOUT
/// `includeParentEnvironment: false`, so PATH / HOME / the GUI credential
/// helper are still inherited — these two only change git's *terminal*
/// behaviour, never the GUI credential popup:
///   • GIT_TERMINAL_PROMPT=0 — a call that would otherwise block forever on
///     an interactive terminal username/password prompt fails fast instead.
///     Our calls have no timeout and share a bounded semaphore, so one hung
///     prompt would strand a permit permanently; failing fast frees it.
///   • GIT_OPTIONAL_LOCKS=0 — background read probes (status, etc.) no longer
///     take the optional index lock, so they stop churning `index.lock`
///     against user-initiated mutations that need the real lock.
///   • LC_ALL=C — pins git's message locale. Every stderr classifier in
///     this codebase (index.lock retry matcher, held-by-desk delete
///     classifier, untracked-overwrite mapping) matches English fragments;
///     a localized git would silently disable them all at once. LC_ALL
///     outranks LANG/LANGUAGE, so this one variable settles it. Message
///     text only — path/content bytes still flow through the lenient
///     decode and core.quotepath handling unchanged.
const Map<String, String> _kNonInteractiveGitEnv = {
  'GIT_TERMINAL_PROMPT': '0',
  'GIT_OPTIONAL_LOCKS': '0',
  'LC_ALL': 'C',
};

/// Public alias of [_kNonInteractiveGitEnv]. The AI backend (ai.dart) runs its
/// own git subprocesses through a separate exec path; it overlays this so those
/// spawns inherit the identical non-interactive terminal behaviour rather than
/// re-declaring the constant and drifting out of sync with this layer.
const Map<String, String> kNonInteractiveGitEnv = _kNonInteractiveGitEnv;

/// True when [stderr] is git's `index.lock` contention shape — another
/// process (or a Windows antivirus scan briefly holding the file, see the
/// semaphore note above) owns the lock. The observed modern-git message
/// (2.52) is:
///   fatal: Unable to create '<path>/.git/index.lock': File exists.
///   Another git process seems to be running in this repository ...
/// We match on the stable fragments rather than the whole sentence so a
/// localized or slightly reworded build still trips the retry, while an
/// unrelated failure (which never mentions index.lock) never does.
bool _isIndexLockContention(String stderr) {
  if (!stderr.contains('index.lock')) return false;
  return stderr.contains('File exists') ||
      stderr.contains('Unable to create') ||
      stderr.contains('Another git process');
}

/// A git call mutates the repo unless its subcommand is one we know is
/// always read-only ([_kDedupableSubcommands]). Only mutations can lose a
/// race for `index.lock`, so only they are worth the transient retry — a
/// read that somehow surfaced the message would be misclassified as safe,
/// and the retry would be skipped, which is the conservative direction.
bool _isMutatingGitCall(List<String> args) {
  final sub = _gitSubcommandToken(args);
  if (sub == null) return true;
  return !_kDedupableSubcommands.contains(sub);
}

/// Subcommands that rewrite `.git/index`. These are the calls serialized by
/// the per-repo write lock (see [_withRepoIndexWriteLock]): git's own
/// index-lock only makes the WRITE exclusive, not the whole read-modify-write
/// — a command may read the index before acquiring the lock, so two of our
/// index writers running concurrently in one repo can commit a full index
/// built from a stale snapshot, silently reverting the other's just-landed
/// entry (observed empirically: `reset -q HEAD -- fileA` exits 0, yet a
/// concurrent `apply --cached` for fileB leaves fileA's entry stale). No
/// retry policy can fix a lost update that reports success, so the class is
/// removed by never letting two in-process index writers overlap. Ref-only
/// writers (update-ref, push, fetch) and pure reads are NOT serialized —
/// ref safety is CAS-based (zero-oid create, force-with-lease) by design.
const Set<String> _kIndexWritingSubcommands = {
  'add',
  'rm',
  'mv',
  'reset',
  'restore',
  'checkout',
  'checkout-index',
  'switch',
  'apply',
  'stash',
  'commit',
  'merge',
  'pull',
  'rebase',
  'cherry-pick',
  'revert',
  'read-tree',
  'update-index',
};

bool _isIndexWritingGitCall(List<String> args) {
  final sub = _gitSubcommandToken(args);
  // No recognizable subcommand → conservatively serialize: a mutation we
  // cannot classify must not be allowed to race the index.
  if (sub == null) return _isMutatingGitCall(args);
  return _kIndexWritingSubcommands.contains(sub);
}

/// Tail of each repo's in-process index-write chain, keyed by
/// [_repoWriteLockKey]. An entry exists only while a writer is queued or
/// running; the last writer out removes it.
final Map<String, Future<void>> _repoIndexWriteChainTails =
    <String, Future<void>>{};

String _repoWriteLockKey(String workingDir) {
  var key = workingDir.replaceAll('\\', '/');
  while (key.length > 1 && key.endsWith('/')) {
    key = key.substring(0, key.length - 1);
  }
  // NTFS is case-insensitive: two spellings of one repo path must share a
  // lock, or the lock silently splits and the race returns.
  return Platform.isWindows ? key.toLowerCase() : key;
}

/// Runs [body] with this repo's index-write lock held: at most one
/// index-writing git subprocess per repo at any moment (see
/// [_kIndexWritingSubcommands] for why overlap loses updates). FIFO via
/// promise-chaining; reads and other-repo writers are unaffected. The lock is
/// acquired BEFORE the subprocess semaphore (inside [body]) so a queued
/// writer never sits on a semaphore permit while blocked. Cross-process
/// writers (a terminal `git add` beside the app) remain the domain of git's
/// own index.lock plus the transient-contention retry.
Future<T> _withRepoIndexWriteLock<T>(
  String workingDir,
  Future<T> Function() body,
) async {
  final key = _repoWriteLockKey(workingDir);
  final prev = _repoIndexWriteChainTails[key] ?? Future<void>.value();
  final gate = Completer<void>();
  final tail = gate.future;
  _repoIndexWriteChainTails[key] = tail;
  await prev;
  try {
    return await body();
  } finally {
    gate.complete();
    if (identical(_repoIndexWriteChainTails[key], tail)) {
      // remove() hands back the stored (already-completed) tail — nothing to
      // await, this is pure map cleanup.
      unawaited(_repoIndexWriteChainTails.remove(key));
    }
  }
}

Future<ProcessResult> _git(
  String workingDir,
  List<String> args, {
  Map<String, String>? extraEnv,
}) async {
  // Coalesce concurrent identical reads. Two callers asking for
  // `git.status --porcelain=v2 --branch -u` in the same instant pay
  // for ONE subprocess, not two. Only applies to known pure-read
  // subcommands (see [_kDedupableSubcommands]); mutating calls
  // (commit, push, add, stash push, ...) always spawn fresh.
  //
  // A call carrying [extraEnv] (e.g. commit-tree with author-identity
  // overrides) always skips the dedup path below and goes straight to
  // [_gitRaw] — the dedup key is (workingDir, args) only, and two calls
  // with identical args but different env must never share a cached
  // result. None of today's dedupable subcommands ever pass extraEnv,
  // so this is a no-op for every existing caller.
  if (extraEnv == null && _isDedupableGitCall(args)) {
    final key = _gitDedupKey(workingDir, args);
    final inflight = _inflightGitReads[key];
    if (inflight != null) {
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'coalesced',
        command: args.isEmpty
            ? 'git'
            : 'git.${_gitSubcommandToken(args) ?? args.first}',
        message: 'shared with in-flight identical call',
      );
      return inflight;
    }
    final future = _gitRaw(workingDir, args);
    _inflightGitReads[key] = future;
    // `whenComplete` returns a NEW future that re-carries any error from
    // [future]; leaving that chain unobserved turns every throwing
    // dedupable call (invalid working dir, spawn failure) into an
    // unhandled async error even though the real awaiter below handles
    // it. Swallow the error on the cleanup chain ONLY — the caller still
    // sees it through the returned [future].
    unawaited(
      future
          .whenComplete(() {
            // Only clear if this is still the live entry. A concurrent
            // race where another caller replaced the future would be a
            // bug in the caller, not this cache; defensive equality check
            // just avoids eager-clearing a fresh in-flight call.
            if (identical(_inflightGitReads[key], future)) {
              _inflightGitReads.remove(key);
            }
          })
          .then<void>((_) {}, onError: (_) {}),
    );
    return future;
  }
  return _gitRaw(workingDir, args, env: extraEnv);
}

/// Jitter source for the transient index.lock backoff. A shared RNG is fine —
/// the only goal is to de-correlate two of our own colliding retries.
final math.Random _gitRetryJitter = math.Random();

/// Emits the lenient-UTF-8-fallback diagnostic (if either stream fell back)
/// and assembles the decoded [ProcessResult]. Factored out of [_gitRaw] so
/// the index.lock retry loop can build a result per attempt without
/// duplicating the fallback-audit event.
ProcessResult _finalizeGitResult(
  String commandLabel,
  ProcessResult raw,
  _GitDecodeOutcome stdoutOut,
  _GitDecodeOutcome stderrOut,
) {
  // Surface any lenient-decode fallback as a diagnostic lifecycle event.
  // Without this, malformed-byte replacement (U+FFFD) is invisible to ops —
  // downstream parsers would silently consume corrupted text. The event is
  // type=warning rather than failure so it doesn't poison success metrics;
  // the errorCode + message are grep-able for encoding audits.
  if (stdoutOut.lenientFallback || stderrOut.lenientFallback) {
    final streams = [
      if (stdoutOut.lenientFallback) 'stdout@${stdoutOut.malformedAtOffset}',
      if (stderrOut.lenientFallback) 'stderr@${stderrOut.malformedAtOffset}',
    ].join(',');
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'warning',
      command: commandLabel,
      errorCode: 'git.malformed_utf8',
      message: 'lenient UTF-8 fallback: $streams',
    );
  }
  return ProcessResult(raw.pid, raw.exitCode, stdoutOut.text, stderrOut.text);
}

/// Count of this process's in-flight MUTATING git subprocesses (commit,
/// checkout, fetch, merge, … — anything [_isMutatingGitCall] classifies as
/// a write). Reads never count. [GitDirWatcher] consumers use this to
/// pause external-change watching while the app is the one mutating the
/// repo: our own ref churn then coalesces into one post-operation refresh
/// instead of racing the operation with N watcher-triggered ones.
int get gitMutationsInFlight => _gitMutationsInFlight;
int _gitMutationsInFlight = 0;
final List<void Function()> _gitMutationListeners = <void Function()>[];

/// Register [listener] to run whenever [gitMutationsInFlight] changes.
/// Fired synchronously from the exec path — keep listeners trivial
/// (a pause/resume flip), never long work.
void addGitMutationListener(void Function() listener) =>
    _gitMutationListeners.add(listener);

void removeGitMutationListener(void Function() listener) =>
    _gitMutationListeners.remove(listener);

void _bumpGitMutations(int delta) {
  _gitMutationsInFlight += delta;
  // Iterate a copy so a listener that removes itself mid-notify is safe.
  for (final l in List<void Function()>.of(_gitMutationListeners)) {
    l();
  }
}

Future<ProcessResult> _gitRaw(
  String workingDir,
  List<String> args, {
  Map<String, String>? env,
}) {
  final commandLabel = args.isEmpty ? 'git' : 'git.${args.first}';
  // Classify by subcommand for strict-decode selection. stderr is always
  // lenient — it carries human messages that may be localized to a non-UTF-8
  // locale on exotic setups. Use `_gitSubcommandToken` so global options
  // before the subcommand (`-C`, `--git-dir`, etc.) don't silently downgrade
  // a strict-eligible command to lenient mode. The mutation gate + index.lock
  // retry classification live inside [_runGitChoreographed].
  final subcommand = _gitSubcommandToken(args);
  final strictStdout =
      subcommand != null && _kStrictDecodeSubcommands.contains(subcommand);
  return _runGitChoreographed(
    commandLabel,
    workingDir,
    args,
    strictStdout: strictStdout,
    spawnAttempt: () => _spawnRunRaw(
      args,
      workingDirectory: workingDir,
      // Merge order is deliberate: caller-supplied [env] (GIT_INDEX_FILE for a
      // snapshot commit; GIT_AUTHOR_*/GIT_COMMITTER_* identity overrides from
      // callers like ManifoldRefs) is spread FIRST, then the non-interactive
      // safety base is spread AFTER — so a caller can add whatever keys it
      // needs, but can never shadow GIT_TERMINAL_PROMPT / GIT_OPTIONAL_LOCKS /
      // LC_ALL by supplying same-named keys of its own. Base-after-caller.
      environment: env == null
          ? _kNonInteractiveGitEnv
          : {...env, ..._kNonInteractiveGitEnv},
    ),
  );
}

/// Shared exec choreography for every git subprocess: the start/finish
/// lifecycle events, the per-repo index-write lock for index-writing calls
/// ([_withRepoIndexWriteLock] — git's own index.lock does not make the whole
/// read-modify-write atomic, so overlapping in-process index writers lose
/// updates), the [_gitSubprocessSemaphore] permit, the [gitMutationsInFlight]
/// bump for mutating calls (so [GitDirWatcher] pauses external-change
/// watching while we mutate), the transient index.lock retry with jittered
/// backoff, and latency recording. The single [spawnAttempt] closure is the
/// ONLY thing that varies between the plain path ([_gitRaw] → [_spawnRunRaw])
/// and the stdin-piping path ([_gitRawStdin] → [_spawnAndPipeStdin]); it is
/// re-invoked from scratch on each retry, so a stdin payload is re-sent per
/// attempt. It must return a raw (undecoded) [ProcessResult] whose
/// stdout/stderr are byte lists.
Future<ProcessResult> _runGitChoreographed(
  String commandLabel,
  String workingDir,
  List<String> args, {
  required Future<ProcessResult> Function() spawnAttempt,
  bool strictStdout = false,
}) {
  Future<ProcessResult> run() => _runGitChoreographedUnlocked(
    commandLabel,
    args,
    spawnAttempt: spawnAttempt,
    strictStdout: strictStdout,
  );
  if (!_isIndexWritingGitCall(args)) return run();
  return _withRepoIndexWriteLock(workingDir, run);
}

Future<ProcessResult> _runGitChoreographedUnlocked(
  String commandLabel,
  List<String> args, {
  required Future<ProcessResult> Function() spawnAttempt,
  bool strictStdout = false,
}) async {
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  await _gitSubprocessSemaphore.acquire();
  var countedMutation = false;
  try {
    final mutating = _isMutatingGitCall(args);
    if (mutating) {
      countedMutation = true;
      _bumpGitMutations(1);
    }

    // A mutation that loses the race for `index.lock` — another git process,
    // or (the documented Windows pain point above) an antivirus scan briefly
    // holding the file — fails hard even though the contention is transient.
    // Retry with exponentially escalating jittered backoff before surfacing
    // it: the lock is held for the duration of the competing git process, and
    // that duration scales with system load, so a fixed short backoff window
    // is exactly what gets exhausted on a busy machine (two of our own
    // back-to-back index mutations can hold it for over a second under
    // contention). The jitter de-synchronizes two of our own mutations that
    // collided. We only retry on the index.lock shape (see
    // [_isIndexLockContention]) so any other failure is returned on the first
    // attempt, unchanged. Worst-case total wait is ~3s, bounded.
    const maxLockRetries = 5;
    ProcessResult result;
    var attempt = 0;
    while (true) {
      final raw = await spawnAttempt();
      final stdoutOut = _decodeGitBytes(raw.stdout, strict: strictStdout);
      final stderrOut = _decodeGitBytes(raw.stderr, strict: false);
      result = _finalizeGitResult(commandLabel, raw, stdoutOut, stderrOut);
      final retryable =
          mutating &&
          result.exitCode != 0 &&
          attempt < maxLockRetries &&
          _isIndexLockContention(result.stderr.toString());
      if (!retryable) break;
      attempt++;
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'warning',
        command: commandLabel,
        errorCode: 'git.index_lock_contended',
        message: 'index.lock held; retry $attempt/$maxLockRetries',
      );
      // Exponential jittered backoff: 50–100ms, 100–200ms, … 800–1600ms.
      final baseMs = 50 << (attempt - 1);
      await Future<void>.delayed(
        Duration(milliseconds: baseMs + _gitRetryJitter.nextInt(baseMs + 1)),
      );
    }
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    final ok = result.exitCode == 0;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: ok ? 'success' : 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: ok ? null : 'git.exit_${result.exitCode}',
      message: ok ? null : result.stderr.toString().trim(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: commandLabel,
        ok: ok,
        scope: 'git',
        roundTripMs: elapsedMs,
        backendDurationMs: elapsedMs,
        errorCode: ok ? null : 'git.exit_${result.exitCode}',
      ),
    );
    return result;
  } catch (error) {
    stopwatch.stop();
    final elapsedMs = stopwatch.elapsedMicroseconds / 1000;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: commandLabel,
      durationMs: elapsedMs,
      errorCode: 'git.invoke_failed',
      message: error.toString(),
    );
    unawaited(
      DiagnosticsState.instance.recordCommandLatency(
        command: commandLabel,
        ok: false,
        scope: 'git',
        roundTripMs: elapsedMs,
        backendDurationMs: elapsedMs,
        errorCode: 'git.invoke_failed',
      ),
    );
    rethrow;
  } finally {
    if (countedMutation) _bumpGitMutations(-1);
    _gitSubprocessSemaphore.release();
  }
}

/// Streamed-spawn sibling of [_spawnRunRaw] that pipes [stdinPayload] to the
/// subprocess and collects both output streams as raw bytes. Both streams are
/// drained concurrently with the exit code to avoid a pipe-buffer deadlock on
/// large output. Used by [_gitRawStdin].
Future<ProcessResult> _spawnAndPipeStdin(
  List<String> args, {
  required String workingDir,
  required List<int> stdinPayload,
  Map<String, String>? env,
}) async {
  final process = await _spawnStart(
    args,
    workingDirectory: workingDir,
    environment: env == null
        ? _kNonInteractiveGitEnv
        : {...env, ..._kNonInteractiveGitEnv},
  );
  // Raw bytes, never IOSink.write: process stdin defaults to the SYSTEM
  // encoding (cp1252 on Windows), which lossily mangles any non-ASCII payload
  // and makes git reject or corrupt the hunk.
  process.stdin.add(stdinPayload);
  await process.stdin.flush();
  await process.stdin.close();
  final stdoutFuture = _collectStreamBytes(process.stdout);
  final stderrFuture = _collectStreamBytes(process.stderr);
  final exit = await process.exitCode;
  final out = await stdoutFuture;
  final err = await stderrFuture;
  return ProcessResult(process.pid, exit, out, err);
}

/// Drains a byte stream into one contiguous list.
Future<List<int>> _collectStreamBytes(Stream<List<int>> stream) async {
  final builder = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// stdin-piping sibling of [_gitRaw]: runs `git [args]` feeding [stdinPayload]
/// to its stdin through the shared [_runGitChoreographed] choreography — so,
/// unlike a bare [_spawnStart], the call takes a semaphore permit, bumps
/// [gitMutationsInFlight] when mutating (pausing [GitDirWatcher]), and RETRIES
/// a transient index.lock, re-sending the payload on each attempt. Pass
/// [commandLabel] to override the telemetry label (e.g. a caller's `git.apply`
/// variant); the stdout of a stdin-piped mutation is never parsed as text, so
/// decode stays lenient.
Future<ProcessResult> _gitRawStdin(
  String workingDir,
  List<String> args, {
  required List<int> stdinPayload,
  String? commandLabel,
  Map<String, String>? env,
}) {
  final label = commandLabel ?? (args.isEmpty ? 'git' : 'git.${args.first}');
  return _runGitChoreographed(
    label,
    workingDir,
    args,
    strictStdout: false,
    spawnAttempt: () => _spawnAndPipeStdin(
      args,
      workingDir: workingDir,
      stdinPayload: stdinPayload,
      env: env,
    ),
  );
}

/// THE public entry point for running a git subprocess from outside this
/// library. Routes through the same shared path (`_git`) every internal call
/// uses: the [GitSubprocessSemaphore] throttle, the non-interactive
/// environment ([_kNonInteractiveGitEnv] — `GIT_TERMINAL_PROMPT=0` so an auth
/// wall fails fast instead of hanging), lenient-UTF-8 decode, transient
/// index.lock retry, and read-coalescing for pure-read subcommands. Callers
/// elsewhere (PR checkout, the .git watcher, forge coord/URL resolution, IPC
/// helpers, the engine's stats walks) MUST use this rather than a raw
/// a raw `Process.run` spawn of `git`, which would prompt on a credential wall and escape
/// the app-wide concurrency budget. Safe for mutations too: a non-read
/// subcommand skips coalescing and runs fresh, still throttled and
/// non-interactive.
///
/// [extraEnv] overlays additional environment variables onto the spawn —
/// e.g. `GIT_AUTHOR_NAME`/`GIT_AUTHOR_EMAIL`/`GIT_COMMITTER_*` for a
/// `commit-tree` that must bake in an identity other than the repo's
/// configured `user.name`/`user.email` (ManifoldRefs' metadata commits).
/// Merge precedence is base-after-caller: [extraEnv] is applied first and
/// [_kNonInteractiveGitEnv] is spread on top, so `GIT_TERMINAL_PROMPT` /
/// `GIT_OPTIONAL_LOCKS` / `LC_ALL` can never be shadowed by a same-named
/// key in [extraEnv] — see the merge inside [_gitRaw]. A call that passes
/// [extraEnv] always skips read-coalescing (see [_git]'s doc), which is
/// harmless here since every current [extraEnv] caller is a mutation
/// anyway.
Future<ProcessResult> runGit(
  String workingDir,
  List<String> args, {
  Map<String, String>? extraEnv,
}) {
  return _git(workingDir, args, extraEnv: extraEnv);
}

Future<GitResult<String>> openRepository(String path) async {
  // Stale recent / moved folder: surface a clean message instead of letting
  // `git rev-parse` throw a raw `ProcessException: The directory name is
  // invalid` that would leak to the UI verbatim. Checked up front as a fast
  // path, and again in the catch so a folder that vanishes in the TOCTOU
  // window between this check and the spawn still gets the clean message
  // rather than the raw exception text.
  if (!await Directory(path).exists()) {
    return const GitResult.err("This project's folder no longer exists.");
  }
  try {
    final r = await _git(path, ['rev-parse', '--git-dir']);
    if (r.exitCode != 0) return const GitResult.err('Not a git repository');
    return GitResult.ok(path);
  } catch (error) {
    if (!await Directory(path).exists()) {
      return const GitResult.err("This project's folder no longer exists.");
    }
    return GitResult.err(error.toString());
  }
}

Future<GitResult<List<String>>> listRecentRepositories() async {
  // Stored in shared_preferences — handled at app layer
  return const GitResult.ok([]);
}

Future<GitResult<RepositoryStatus>> getRepositoryStatus(String repo) async {
  // Single `status --porcelain=v2 --branch` replaces the previous 4
  // serial calls (rev-parse HEAD, status v1, rev-parse @{u}, rev-list
  // --left-right --count). Porcelain v2 emits the branch name,
  // upstream name, and ahead/behind counts as header lines alongside
  // the file status entries — saves 3 subprocess spawns (~150-450ms)
  // on every refresh.
  //
  // Header format (one per line, leading `#`):
  //   # branch.oid <hash>             — HEAD sha or `(initial)`
  //   # branch.head <branch>          — branch name or `(detached)`
  //   # branch.upstream <upstream>    — only if upstream configured
  //   # branch.ab +<ahead> -<behind>  — only if upstream configured
  //
  // File entry format (leading digit / char):
  //   1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>       — tracked
  //   2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>\t<orig>
  //   u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>
  //   ? <path>                                           — untracked
  //   ! <path>                                           — ignored
  try {
    final status = await _git(repo, [
      'status',
      '--porcelain=v2',
      '--branch',
      '-u',
    ]);
    if (status.exitCode != 0) {
      return GitResult.err(status.stderr.toString().trim());
    }

    String branchName = '';
    String? upstreamName;
    int ahead = 0;
    int behind = 0;
    // True until the parser sees `# branch.oid (initial)` — a fresh
    // repo with no commits. Lets the UI hide affordances that only
    // make sense once HEAD is a real ref (amend, reflog recovery).
    bool hasHeadCommit = true;
    final files = <RepositoryStatusFile>[];

    for (final rawLine in status.stdout.toString().split('\n')) {
      if (rawLine.isEmpty) continue;
      final first = rawLine.codeUnitAt(0);
      if (first == 0x23) {
        // '#' — header line. Match by key prefix.
        if (rawLine.startsWith('# branch.oid ')) {
          final v = rawLine.substring(13).trim();
          if (v == '(initial)') hasHeadCommit = false;
        } else if (rawLine.startsWith('# branch.head ')) {
          final v = rawLine.substring(14).trim();
          if (v != '(detached)') branchName = v;
        } else if (rawLine.startsWith('# branch.upstream ')) {
          upstreamName = rawLine.substring(18).trim();
        } else if (rawLine.startsWith('# branch.ab ')) {
          // Format: `+<ahead> -<behind>`
          final parts = rawLine.substring(12).trim().split(' ');
          if (parts.length == 2) {
            ahead = int.tryParse(parts[0].replaceFirst('+', '')) ?? 0;
            behind = int.tryParse(parts[1].replaceFirst('-', '')) ?? 0;
          }
        }
        continue;
      }
      if (first == 0x31 /* '1' */ || first == 0x32 /* '2' */ ) {
        // Tracked / renamed: `<type> <XY> <sub> <mH> <mI> <mW> <hH> <hI> [<rename>] <path>`
        // The XY field is at a known position (chars 2-3). For `2`
        // entries there's an additional `<X><score>` field before the
        // path, and the path itself is followed by `\t<origPath>`.
        // We only need the XY and the final path.
        if (rawLine.length < 4) continue;
        final staged = rawLine[2];
        final unstaged = rawLine[3];
        // Path is whatever follows the 8th (tracked) or 9th (rename)
        // space-separated field. Splitting once per space is simpler
        // than counting fields — skip through the fixed-width metadata.
        final pathStart = first == 0x31
            ? _nthSpace(rawLine, 8) + 1
            : _nthSpace(rawLine, 9) + 1;
        if (pathStart <= 0 || pathStart >= rawLine.length) continue;
        var path = rawLine.substring(pathStart);
        // Rename records append `\t<origPath>` — we only want the new
        // path for RepositoryStatusFile.
        final tab = path.indexOf('\t');
        if (tab >= 0) path = path.substring(0, tab);
        // core.quotePath=true (the git default) C-quotes any non-ASCII path
        // (`"caf\303\251.txt"`); recover the real bytes via the shared decoder.
        path = unCQuoteGitPath(path);
        if (path.isEmpty) continue;
        files.add(
          RepositoryStatusFile(
            path: path,
            staged: canonicalGitStatusCode(staged, stagedSlot: true),
            unstaged: canonicalGitStatusCode(unstaged, stagedSlot: false),
          ),
        );
        continue;
      }
      if (first == 0x75 /* 'u' */ ) {
        // Unmerged: path starts after the 10th field.
        if (rawLine.length < 4) continue;
        final staged = rawLine[2];
        final unstaged = rawLine[3];
        final pathStart = _nthSpace(rawLine, 10) + 1;
        if (pathStart <= 0 || pathStart >= rawLine.length) continue;
        final path = unCQuoteGitPath(rawLine.substring(pathStart));
        if (path.isEmpty) continue;
        files.add(
          RepositoryStatusFile(
            path: path,
            staged: canonicalGitStatusCode(staged, stagedSlot: true),
            unstaged: canonicalGitStatusCode(unstaged, stagedSlot: false),
          ),
        );
        continue;
      }
      if (first == 0x3f /* '?' */ || first == 0x21 /* '!' */ ) {
        // Untracked / ignored: `? <path>` or `! <path>`.
        final path = unCQuoteGitPath(rawLine.substring(2));
        if (path.isEmpty) continue;
        files.add(
          RepositoryStatusFile(
            path: path,
            staged: canonicalGitStatusCode('', stagedSlot: true),
            unstaged: canonicalGitStatusCode(
              first == 0x3f ? '?' : '!',
              stagedSlot: false,
            ),
          ),
        );
      }
    }

    return GitResult.ok(
      RepositoryStatus(
        branch: branchName,
        upstream: upstreamName,
        ahead: ahead,
        behind: behind,
        files: files,
        hasHeadCommit: hasHeadCommit,
      ),
    );
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

/// Return the byte-index of the [n]th space in [s], or -1 when there
/// are fewer than [n] spaces. Used to locate the path field in
/// porcelain-v2 entries without allocating a full `split(' ')` list
/// per status line.
int _nthSpace(String s, int n) {
  var count = 0;
  for (var i = 0; i < s.length; i++) {
    if (s.codeUnitAt(i) == 0x20) {
      count++;
      if (count == n) return i;
    }
  }
  return -1;
}

/// Format string used by both listCommitHistory and listFileHistory.
/// Shape: hash, shortHash, parents, refs, subject, author, email, date.
/// Keep in sync with `_parseCommitLogLines` below.
const String _kCommitLogFormat = '--format=%H%n%h%n%P%n%D%n%s%n%aN%n%aE%n%aI';

/// Parses 8-line commit records from `git log --format=_kCommitLogFormat`.
/// Each commit occupies 8 consecutive non-empty lines; blank lines separate
/// them. Used by listCommitHistory and listFileHistory.
List<CommitHistoryEntry> _parseCommitLogLines(List<String> lines) {
  final entries = <CommitHistoryEntry>[];
  int i = 0;
  while (i + 7 < lines.length) {
    final hash = lines[i].trim();
    // Skip blank separators AND any `gpg:` verification lines that
    // log.showSignature=true interleaves ahead of each commit's format output.
    // The call sites pin --no-show-signature so these never reach production;
    // screening them here too keeps the fixed-8-line window aligned if they
    // ever do. Only the record-START line is screened — a commit whose SUBJECT
    // legitimately begins "gpg:" is read positionally at i+4 and left intact.
    if (hash.isEmpty || hash.startsWith('gpg:')) {
      i++;
      continue;
    }
    final parents = lines[i + 2]
        .trim()
        .split(' ')
        .where((s) => s.isNotEmpty)
        .toList();
    entries.add(
      CommitHistoryEntry(
        commitHash: hash,
        shortHash: lines[i + 1].trim(),
        parentHashes: parents,
        refNames: lines[i + 3]
            .trim()
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        isMerge: parents.length > 1,
        subject: lines[i + 4].trim(),
        authorName: lines[i + 5].trim(),
        authorEmail: lines[i + 6].trim(),
        authoredAt: lines[i + 7].trim(),
      ),
    );
    i += 8;
    while (i < lines.length && lines[i].trim().isEmpty) {
      i++;
    }
  }
  return entries;
}

Future<GitResult<List<CommitHistoryEntry>>> listCommitHistory(
  String repo, {
  int limit = 200,
  String? branch,
}) async {
  // --no-show-signature: log.showSignature=true injects `gpg:` lines that
  // shift _parseCommitLogLines' fixed-8-line commit windows; pin it off.
  final args = ['log', ..._kCommitLogPins, _kCommitLogFormat, '-n', '$limit'];
  if (branch != null) args.add(branch);
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(_parseCommitLogLines(r.stdout.toString().split('\n')));
}

/// Commits reachable from [branch] that are NOT reachable from [excluding].
/// Concretely: `git log <branch> ^<excluding>` — the diverged set, oldest
/// at the end like every other history list. Used by the History page's
/// hover-preview to show what commits would land if the user merged
/// the hovered desk into the active worktree, without leaving the view.
Future<GitResult<List<CommitHistoryEntry>>> listCommitsAhead(
  String repo, {
  required String branch,
  required String excluding,
  int limit = 200,
}) async {
  final args = [
    'log',
    ..._kCommitLogPins,
    _kCommitLogFormat,
    '-n',
    '$limit',
    branch,
    '^$excluding',
  ];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(_parseCommitLogLines(r.stdout.toString().split('\n')));
}

/// Bulk-fetches file stats for all commits in two parallel git log passes
/// (--numstat and --name-status). Merges with already-loaded commit metadata
/// to produce a full CommitDetailData per commit — body is left empty since
/// it isn't needed for the file list view and the individual getCommitDetail
/// path fills it in on demand.
Future<GitResult<Map<String, CommitDetailData>>> bulkGetCommitDetails(
  String repo,
  List<CommitHistoryEntry> commits, {
  int limit = 200,
  String? branch,
}) async {
  if (commits.isEmpty) return const GitResult.ok({});

  final args = ['log', ..._kCommitLogPins, '--format=>>>%H', '-n', '$limit'];
  if (branch != null) args.add(branch);
  // `--raw` (status letters) + `--numstat` (additions/deletions) coexist
  // in a single `git log` pass; `--name-status` and `--numstat` do NOT —
  // git silently honours only the last of those two, dropping the other
  // block entirely. Combining `--raw` with `--numstat` is the
  // single-call way to get both file paths AND churn:
  //   raw    : `:mode mode sha sha STATUS\tpath`            ('A', 'M', 'D', 'R100', etc.)
  //   numstat: `<adds>\t<dels>\t<path>` (or `-\t-\t<path>` for binary)
  // Discriminated by line prefix without needing a separator pass.
  args.add('--raw');
  args.add('--numstat');
  final r = await _git(repo, args);
  if (r.exitCode != 0) {
    return GitResult.err(r.stderr.toString().trim());
  }

  final numstatByHash = <String, List<_BulkFileStat>>{};
  final changeTypesByHash = <String, Map<String, String>>{};
  String? cur;
  for (final line in r.stdout.toString().split('\n')) {
    if (line.startsWith('>>>')) {
      cur = line.substring(3).trim();
      numstatByHash[cur] = [];
      changeTypesByHash[cur] = {};
      continue;
    }
    if (cur == null) continue;
    if (line.isEmpty) continue;
    final first = line.codeUnitAt(0);
    if (first == 0x3a /* ':' */ ) {
      // Raw row format:
      //   single parent: `:srcMode dstMode srcSha dstSha STATUS\tpath`
      //                  (rename/copy: `STATUS<score>\told\tnew`)
      //   merge commit:  `::m1 m2 m3 m4 s1 s2 STATUS\tpath`
      //                  (combined-diff, leading `::` and one extra
      //                   mode + sha pair per parent).
      // We accept both shapes, key off "first whitespace-separated
      // token whose first char is A–Z" as the status. Anything else
      // (malformed, no tab, no recognisable letter token) is skipped
      // — the numstat block on the same commit will still land its
      // adds/dels even if status couldn't be classified.
      final tabIdx = line.indexOf('\t');
      if (tabIdx <= 0) continue;
      final head = line.substring(0, tabIdx);
      final rest = line.substring(tabIdx + 1);
      final tokens = head.split(' ');
      String? status;
      for (var i = tokens.length - 1; i >= 0; i--) {
        final tok = tokens[i];
        if (tok.isEmpty) continue;
        final c = tok.codeUnitAt(0);
        if (c >= 0x41 && c <= 0x5a) {
          status = tok;
          break;
        }
      }
      if (status == null || status.isEmpty) continue;
      // Rename/copy: `STATUS<score>\told\tnew` — destination wins.
      final path = rest.contains('\t') ? rest.split('\t').last : rest;
      // Un-C-quote so this key matches the numstat key below under
      // core.quotePath=true (git default) — both must decode identically.
      final pathTrim = unCQuoteGitPath(path.trim());
      if (pathTrim.isEmpty) continue;
      changeTypesByHash[cur]![pathTrim] = status.substring(0, 1);
      continue;
    }
    final isDigit = first >= 0x30 && first <= 0x39;
    final isDash = first == 0x2d; // '-' — binary file in numstat
    if (isDigit || isDash) {
      // Numstat row: <adds>\t<dels>\t<path>  (or -\t-\t<path>)
      final parts = line.split('\t');
      if (parts.length >= 3) {
        final adds = int.tryParse(parts[0]) ?? 0;
        final dels = int.tryParse(parts[1]) ?? 0;
        final path = unCQuoteGitPath(parts[2].trim());
        if (path.isNotEmpty) {
          numstatByHash[cur]!.add(_BulkFileStat(path, adds, dels));
        }
      }
    }
  }

  // Build CommitDetailData from existing metadata + fetched file stats
  final out = <String, CommitDetailData>{};
  for (final c in commits) {
    final stats = numstatByHash[c.commitHash] ?? [];
    final types = changeTypesByHash[c.commitHash] ?? {};
    final files = stats
        .map(
          (s) => CommitFileStatData(
            path: s.path,
            additions: s.additions,
            deletions: s.deletions,
            changeType: types[s.path] ?? 'M',
          ),
        )
        .toList();
    out[c.commitHash] = CommitDetailData(
      commitHash: c.commitHash,
      shortHash: c.shortHash,
      subject: c.subject,
      body: '',
      authorName: c.authorName,
      authorEmail: c.authorEmail,
      authoredAt: c.authoredAt,
      filesChanged: files.length,
      additions: files.fold(0, (s, f) => s + f.additions),
      deletions: files.fold(0, (s, f) => s + f.deletions),
      files: files,
    );
  }
  return GitResult.ok(out);
}

class _BulkFileStat {
  final String path;
  final int additions;
  final int deletions;
  const _BulkFileStat(this.path, this.additions, this.deletions);
}

/// Wraps a history entry with the file path AS IT EXISTED at that commit.
/// Critical for correctly fetching diffs/blame across renames: if the file
/// was foo.txt before being renamed to bar.txt, pre-rename commits must be
/// queried with the OLD name, not the current one.
class FileHistoryEntry {
  final CommitHistoryEntry commit;
  final String pathAtRevision;
  const FileHistoryEntry({required this.commit, required this.pathAtRevision});
}

/// Returns the commit history for a file, with `--follow` tracking renames,
/// AND the path the file had at each commit (used to query diffs/blame
/// correctly for commits from before a rename).
Future<GitResult<List<FileHistoryEntry>>> listFileHistoryWithPaths(
  String repo,
  String filePath, {
  int limit = 100,
}) async {
  // --name-status emits a status line (M/A/D/R100 etc.) after each commit's
  // metadata, with the file path(s) involved. For renames, two paths:
  // old\tnew. We use these to resolve the name at each historical commit.
  final r = await _git(repo, [
    'log',
    ..._kCommitLogPins,
    '--follow',
    _kCommitLogFormat,
    '--name-status',
    '-n',
    '$limit',
    '--',
    filePath,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  // Separate the interleaved output into two streams:
  //   - commit metadata lines (8 per commit) → parsed by shared helper
  //   - per-commit name-status lines → resolved into pathsByHash
  // This keeps `_parseCommitLogLines` as the single source of truth for
  // the 8-line commit format.
  final raw = r.stdout.toString().split('\n');
  final metadataLines = <String>[];
  final pathsByHash = <String, String>{};
  // Rolling fallback: git log is newest→oldest, so if a commit's name-status
  // fails to parse, the last successfully-resolved path is more likely to be
  // correct than the current HEAD filePath (which would be wrong for anything
  // before a rename).
  String? lastKnownPath;
  int i = 0;
  while (i + 7 < raw.length) {
    final hash = raw[i].trim();
    if (hash.isEmpty) {
      i++;
      continue;
    }
    // Forward the 8 metadata lines + a blank separator to the shared parser.
    for (var j = 0; j < 8; j++) {
      metadataLines.add(i + j < raw.length ? raw[i + j] : '');
    }
    metadataLines.add('');
    i += 8;
    while (i < raw.length && raw[i].trim().isEmpty) {
      i++;
    }
    // Name-status lines: "STATUS\tpath" or "R100\told\tnew". In both cases
    // we want parts[1]: the first path (old name for renames, which is what
    // the file was called AT this commit in the file's history chain).
    String? pathAt;
    while (i < raw.length && raw[i].isNotEmpty) {
      final parts = raw[i].split('\t');
      if (parts.length >= 2) pathAt = parts[1];
      i++;
    }
    final resolved = pathAt ?? lastKnownPath ?? filePath;
    pathsByHash[hash] = resolved;
    lastKnownPath = resolved;
  }

  final commits = _parseCommitLogLines(metadataLines);
  final entries = commits
      .map(
        (c) => FileHistoryEntry(
          commit: c,
          pathAtRevision: pathsByHash[c.commitHash] ?? filePath,
        ),
      )
      .toList();
  return GitResult.ok(entries);
}

/// Thin wrapper returning just the commit entries (path info discarded).
/// Kept for callers that don't need rename-aware behavior.
Future<GitResult<List<CommitHistoryEntry>>> listFileHistory(
  String repo,
  String filePath, {
  int limit = 100,
}) async {
  final r = await listFileHistoryWithPaths(repo, filePath, limit: limit);
  if (!r.ok) return GitResult.err(r.error!);
  return GitResult.ok(r.data!.map((e) => e.commit).toList());
}

Future<GitResult<String>> getFileDiffAtRevision(
  String repo,
  String filePath,
  String commitHash,
) async {
  final r = await _git(repo, [
    ..._kDiffCmd,
    ..._kDiffContentPins,
    '--full-index',
    '$commitHash~1..$commitHash',
    '--',
    filePath,
  ]);
  if (r.exitCode == 0) return GitResult.ok(r.stdout.toString());

  // Only fall back to `git show` when the error genuinely looks like
  // "this commit has no parent" — i.e. a root commit. Other errors
  // (invalid hash, missing file, etc.) should surface as-is instead of
  // being masked by a second command's failure.
  final primaryErr = r.stderr.toString();
  final looksLikeRootCommit =
      primaryErr.contains('unknown revision') ||
      primaryErr.contains('ambiguous argument') ||
      primaryErr.contains('bad revision');
  if (!looksLikeRootCommit) {
    return GitResult.err(primaryErr.trim());
  }
  final r2 = await _git(repo, [
    ..._kShowCmd,
    ..._kDiffContentPins,
    '--full-index',
    commitHash,
    '--',
    filePath,
  ]);
  if (r2.exitCode != 0) {
    // Preserve the original diff error context alongside the fallback's.
    return GitResult.err(
      '${primaryErr.trim()}\n(fallback also failed: ${r2.stderr.toString().trim()})',
    );
  }
  return GitResult.ok(r2.stdout.toString());
}

/// The three PR-merge strategies. Each maps to a different landing shape in
/// [mergeBranchIntoBase]; the routing (which worktree, or a ref-level merge)
/// is orthogonal and chosen by the engine.
enum BranchMergeMethod {
  /// A two-parent merge commit — preserves both histories. Landed by
  /// `git merge --no-ff` in the base's worktree, or `git commit-tree` with
  /// parents `[base, head]` when the base is checked out nowhere.
  mergeCommit,

  /// A squash: collapse the branch's commits into one on the base. Landed by
  /// `git merge --squash` + commit, or a single-parent `git commit-tree`.
  squash,

  /// Replay the branch onto the base for linear history, then fast-forward
  /// the base. Needs the base checked out in a worktree — there is no
  /// ref-level rebase without one.
  rebase,
}

/// Routing decision + git-level classification of a local-PR merge, returned
/// by [mergeBranchIntoBase] BEFORE any conflict-editor interaction. Splitting
/// the pure engine (this) from the UI reconcile mirrors the pull path, where
/// [runNativeMerge] classifies and the flow layer drives the editor.
///
/// [outcome] speaks the same sealed [MergeOutcome] family as pull/sync, so a
/// caller can't mistake a recoverable conflict for a hard failure.
/// [conflictWorktree] names the worktree whose working tree now holds live
/// conflict markers to resolve in the shared editor — null when the conflict
/// was found at ref level (the zero-checkout path) and no tree was touched.
/// [rebasePaused] flags a halted rebase (finish with [finishLocalPrRebase]
/// once its conflicts are resolved) versus a halted merge (conclude with a
/// commit).
class LocalPrMergeResult {
  final MergeOutcome outcome;
  final String? conflictWorktree;
  final bool rebasePaused;
  const LocalPrMergeResult(
    this.outcome, {
    this.conflictWorktree,
    this.rebasePaused = false,
  });
}

/// The worktree currently holding [branchName] checked out, or null when no
/// worktree has it. The routing primitive behind [mergeBranchIntoBase]: a
/// merge runs WHERE a ref is already checked out (never hijacking another
/// worktree's HEAD), and a ref checked out nowhere is free to advance purely
/// at the ref level.
Future<WorktreeData?> worktreeHolding(String repo, String branchName) async {
  final wts = await listWorktrees(repo);
  if (!wts.ok) return null;
  for (final wt in wts.data!) {
    if (wt.branch == branchName) return wt;
  }
  return null;
}

/// Merge [branch] into [baseRef] with the chosen [method], choosing where the
/// merge lands so it NEVER switches a worktree's HEAD as a side effect:
///   • base checked out in a worktree → run the native merge THERE (the desk
///     already has it out; no checkout at all);
///   • base checked out nowhere → a zero-checkout ref-level merge
///     (`merge-tree` → `commit-tree` → CAS `update-ref`), leaving every
///     working tree untouched. A ref-level conflict returns [MergeConflicted]
///     with the refs unmoved.
/// Rebase is the exception: it needs a worktree, so an unchecked-out base
/// yields [MergeNeedsCheckout] rather than a hidden temp worktree.
///
/// On success the merged state is VERIFIED from git before the result claims
/// clean — `merge-base --is-ancestor` for merge-commit/rebase, and tree
/// equality (the squash's committed tree must equal the tree `merge-tree`
/// builds from the pre-merge base and head) for squash, since a squash of
/// N≥2 commits patch-matches nothing per-commit — so a caller can trust
/// [MergeClean] to mean history actually landed. Pure git; the caller owns
/// UI + DeskPr bookkeeping.
Future<LocalPrMergeResult> mergeBranchIntoBase({
  required String repoPath,
  required String branch,
  required String baseRef,
  required BranchMergeMethod method,
  String? squashSubject,
}) async {
  if (branch == baseRef) {
    return LocalPrMergeResult(
      MergeFailed('Base and head are the same branch ($branch).'),
    );
  }
  final headTip = await _revParse(repoPath, branch);
  if (headTip.isEmpty) {
    return LocalPrMergeResult(
      MergeFailed('Could not resolve head branch $branch.'),
    );
  }
  final baseTip = await _revParse(repoPath, baseRef);
  if (baseTip.isEmpty) {
    return LocalPrMergeResult(
      MergeFailed('Could not resolve base branch $baseRef.'),
    );
  }

  switch (method) {
    case BranchMergeMethod.rebase:
      return _rebaseIntoBase(repoPath, branch, baseRef);
    case BranchMergeMethod.mergeCommit:
    case BranchMergeMethod.squash:
      final baseWt = await worktreeHolding(repoPath, baseRef);
      if (baseWt != null) {
        return _mergeInWorktree(baseWt, branch, baseRef, method, squashSubject);
      }
      return _mergeAtRefLevel(
        repoPath,
        branch,
        baseRef,
        baseTip,
        headTip,
        method,
        squashSubject,
      );
  }
}

String _squashSubject(String? supplied, String branch) =>
    (supplied != null && supplied.trim().isNotEmpty)
    ? supplied.trim()
    : 'Merge local PR ($branch)';

/// Native merge inside the worktree that already has [baseRef] out — no
/// checkout, so the desk's HEAD is exactly where it was. Conflicts leave UU
/// markers in that tree for the shared editor to resolve.
Future<LocalPrMergeResult> _mergeInWorktree(
  WorktreeData baseWt,
  String branch,
  String baseRef,
  BranchMergeMethod method,
  String? squashSubject,
) async {
  final repo = baseWt.path;
  // Gate on TRACKED modifications only, read fresh in this worktree at gate
  // time (not the cached `dirtyFileCount`, which also counts untracked `??`
  // files). A stray scratch file must not block a merge — `git merge` itself
  // rides over non-colliding untracked files, and its own overwrite-refusal
  // is the backstop for the rare untracked collision (handled below).
  final dirty = await _modifiedPaths(repo);
  if (dirty.tracked.isNotEmpty) {
    return LocalPrMergeResult(
      MergeBlockedByLocalChanges(dirty.tracked.toList()..sort()),
    );
  }

  // Capture the base tip BEFORE the merge: the squash verifier needs it to
  // rebuild the expected merged tree, and it lets a post-mutation failure
  // report honestly whether the base already advanced.
  final baseBefore = await _revParse(repo, baseRef);

  if (method == BranchMergeMethod.squash) {
    final sq = await _git(repo, ['merge', '--squash', branch]);
    if (sq.exitCode != 0) {
      final conflicted = await _conflictedPaths(repo);
      // `--squash` on conflict leaves UU markers + SQUASH_MSG but no
      // MERGE_HEAD; the editor's `git commit` conclusion produces the
      // single-parent commit squash wants.
      if (conflicted.isNotEmpty) {
        return LocalPrMergeResult(
          MergeConflicted(conflicted),
          conflictWorktree: repo,
        );
      }
      final blocked = _untrackedOverwritePaths(sq.stderr as String);
      if (blocked.isNotEmpty) {
        return LocalPrMergeResult(MergeBlockedByLocalChanges(blocked..sort()));
      }
      return LocalPrMergeResult(MergeFailed((sq.stderr as String).trim()));
    }
    final commit = await _git(repo, [
      'commit',
      '-m',
      _squashSubject(squashSubject, branch),
    ]);
    if (commit.exitCode != 0) {
      return LocalPrMergeResult(
        MergeFailed(
          'Squash commit failed: ${(commit.stderr as String).trim()}',
        ),
      );
    }
  } else {
    final mc = await _git(repo, ['merge', '--no-ff', '--no-edit', branch]);
    if (mc.exitCode != 0) {
      final conflicted = await _conflictedPaths(repo);
      if (conflicted.isNotEmpty) {
        return LocalPrMergeResult(
          MergeConflicted(conflicted),
          conflictWorktree: repo,
        );
      }
      final blocked = _untrackedOverwritePaths(mc.stderr as String);
      if (blocked.isNotEmpty) {
        return LocalPrMergeResult(MergeBlockedByLocalChanges(blocked..sort()));
      }
      return LocalPrMergeResult(MergeFailed((mc.stderr as String).trim()));
    }
  }

  final verified = await _verifyMerged(
    repo,
    baseRef,
    branch,
    method,
    squashBaseBefore: baseBefore,
  );
  if (!verified) {
    // The commit/merge already advanced the base by this point — say so
    // rather than implying nothing happened. This is near-impossible with
    // tree-equality verification, but the message must never lie.
    final baseAfter = await _revParse(repo, baseRef);
    final moved = baseAfter.isNotEmpty && baseAfter != baseBefore;
    return LocalPrMergeResult(
      MergeFailed(
        moved
            ? '$baseRef advanced but the merge of $branch could not be verified — '
                  'inspect $baseRef before marking merged.'
            : 'Merge ran but $baseRef does not contain $branch — not marking merged.',
      ),
    );
  }
  return LocalPrMergeResult(
    MergeClean(
      SyncData(
        operation: 'merge',
        remote: '',
        output: 'Merged $branch into $baseRef.',
      ),
    ),
  );
}

/// Zero-checkout merge for a base checked out nowhere: `merge-tree` builds the
/// merged tree in the object store (no working tree), `commit-tree` wraps it
/// (two parents for a merge commit, one for a squash), and a CAS `update-ref`
/// advances the base only if it hasn't moved since we read it. A `merge-tree`
/// conflict returns the file list with every ref left exactly as it was.
Future<LocalPrMergeResult> _mergeAtRefLevel(
  String repo,
  String branch,
  String baseRef,
  String baseTip,
  String headTip,
  BranchMergeMethod method,
  String? squashSubject,
) async {
  final mt = await _git(repo, [
    'merge-tree',
    '--write-tree',
    '--name-only',
    baseRef,
    branch,
  ]);
  if (mt.exitCode == 1) {
    // Conflicts. Nothing was written to any ref — this is a pure prediction.
    // `merge-tree --write-tree --name-only` emits THREE sections separated by
    // a blank line: the merged-tree OID (line 1), then the conflicted file
    // NAMES (one per line), then a human-readable "informational messages"
    // block ("Auto-merging <f>", "CONFLICT (content): …"). Only the middle
    // section is a path list — stop at the blank line, or those prose lines
    // leak in as bogus conflict "paths".
    final lines = (mt.stdout as String).split('\n');
    final paths = <String>[];
    for (var i = 1; i < lines.length; i++) {
      final name = lines[i].trim();
      if (name.isEmpty) break; // end of the conflicted-names section
      paths.add(name);
    }
    return LocalPrMergeResult(MergeConflicted(paths));
  }
  if (mt.exitCode != 0) {
    return LocalPrMergeResult(
      MergeFailed('merge-tree failed: ${(mt.stderr as String).trim()}'),
    );
  }
  final tree = (mt.stdout as String).trim().split('\n').first.trim();
  if (tree.isEmpty) {
    return const LocalPrMergeResult(
      MergeFailed('merge-tree produced no tree.'),
    );
  }

  final ctArgs = <String>['commit-tree', tree, '-p', baseTip];
  if (method == BranchMergeMethod.mergeCommit) ctArgs.addAll(['-p', headTip]);
  ctArgs.addAll(['-m', _squashSubject(squashSubject, branch)]);
  final ct = await _git(repo, ctArgs);
  if (ct.exitCode != 0) {
    return LocalPrMergeResult(
      MergeFailed('commit-tree failed: ${(ct.stderr as String).trim()}'),
    );
  }
  final newSha = (ct.stdout as String).trim();

  // Compare-and-swap: fail cleanly if the base moved between our read and
  // this write, rather than clobbering a concurrent update.
  final upd = await _git(repo, [
    'update-ref',
    'refs/heads/$baseRef',
    newSha,
    baseTip,
  ]);
  if (upd.exitCode != 0) {
    return LocalPrMergeResult(
      MergeFailed(
        '$baseRef moved during the merge — nothing changed, retry. '
        '(${(upd.stderr as String).trim()})',
      ),
    );
  }

  // Verify. A squash here is verified by TREE EQUALITY like the worktree
  // path, but we already hold the merged [tree] `merge-tree` built and
  // [newSha] is `commit-tree` of exactly that tree — so confirm the landed
  // commit carries it rather than recomputing the merge. Merge-commit falls
  // back to the ancestor check.
  final verified = method == BranchMergeMethod.squash
      ? (await _revParse(repo, '$newSha^{tree}')) == tree
      : await _verifyMerged(repo, baseRef, branch, method);
  if (!verified) {
    return LocalPrMergeResult(
      MergeFailed(
        'Merge landed but $baseRef does not contain $branch — not marking merged.',
      ),
    );
  }
  return LocalPrMergeResult(
    MergeClean(
      SyncData(
        operation: 'merge',
        remote: '',
        output: 'Merged $branch into $baseRef.',
      ),
    ),
  );
}

/// Rebase [branch] onto [baseRef], then fast-forward the base. The replay
/// runs in the HEAD branch's OWN worktree (it legitimately owns that ref — no
/// hijack) and the fast-forward in the base's worktree. Either ref checked out
/// nowhere yields [MergeNeedsCheckout]: there is no ref-level rebase, and we
/// won't conjure a temp worktree in v1.
Future<LocalPrMergeResult> _rebaseIntoBase(
  String repo,
  String branch,
  String baseRef,
) async {
  final baseWt = await worktreeHolding(repo, baseRef);
  if (baseWt == null) {
    return LocalPrMergeResult(
      MergeNeedsCheckout(
        branch: branch,
        baseRef: baseRef,
        message:
            'Rebasing $branch onto $baseRef needs $baseRef checked out in a '
            'desk. Open it, then rebase — or pick merge commit / squash instead.',
      ),
    );
  }
  final headWt = await worktreeHolding(repo, branch);
  if (headWt == null) {
    return LocalPrMergeResult(
      MergeNeedsCheckout(
        branch: branch,
        baseRef: baseRef,
        message:
            'Rebasing $branch needs it checked out in a desk. Open it, then '
            'rebase — or pick merge commit / squash instead.',
      ),
    );
  }
  // Gate on TRACKED modifications only, read fresh in each worktree. `git
  // rebase` refuses over any tracked change, but untracked scratch files are
  // no obstacle — don't let one falsely block the replay.
  final headDirty = await _modifiedPaths(headWt.path);
  if (headDirty.tracked.isNotEmpty) {
    return LocalPrMergeResult(
      MergeBlockedByLocalChanges(headDirty.tracked.toList()..sort()),
    );
  }
  final baseDirty = await _modifiedPaths(baseWt.path);
  if (baseDirty.tracked.isNotEmpty) {
    return LocalPrMergeResult(
      MergeBlockedByLocalChanges(baseDirty.tracked.toList()..sort()),
    );
  }

  final rb = await _git(headWt.path, ['rebase', baseRef]);
  if (rb.exitCode != 0) {
    final conflicted = await _conflictedPaths(headWt.path);
    if (conflicted.isNotEmpty) {
      // Paused mid-rebase in the head's worktree. The flow layer drives the
      // editor loop, then calls [finishLocalPrRebase] to advance the base.
      return LocalPrMergeResult(
        MergeConflicted(conflicted),
        conflictWorktree: headWt.path,
        rebasePaused: true,
      );
    }
    await _git(headWt.path, ['rebase', '--abort']);
    return LocalPrMergeResult(
      MergeFailed('Rebase failed: ${(rb.stderr as String).trim()}'),
    );
  }
  return _fastForwardBaseToHead(repo, branch, baseRef, baseWt);
}

/// Fast-forward [baseRef] to the (already-rebased) tip of [branch] in the
/// base's worktree, then verify. Shared by the clean-rebase path and the
/// editor-resolved [finishLocalPrRebase] continuation.
Future<LocalPrMergeResult> _fastForwardBaseToHead(
  String repo,
  String branch,
  String baseRef,
  WorktreeData baseWt,
) async {
  final newHeadTip = await _revParse(repo, branch);
  final ff = await _git(baseWt.path, ['merge', '--ff-only', branch]);
  if (ff.exitCode != 0) {
    return LocalPrMergeResult(
      MergeFailed(
        'Rebased, but fast-forward of $baseRef failed: ${(ff.stderr as String).trim()}',
      ),
    );
  }
  if (!await _isAncestor(repo, newHeadTip, baseRef)) {
    return LocalPrMergeResult(
      MergeFailed(
        'Rebased but $baseRef did not advance to $branch — not marking merged.',
      ),
    );
  }
  return LocalPrMergeResult(
    MergeClean(
      SyncData(
        operation: 'merge',
        remote: '',
        output: 'Rebased $branch onto $baseRef.',
      ),
    ),
  );
}

/// Finish a rebase whose conflicts were resolved in the editor: the head
/// branch is now at its rebased tip, so advance the base by fast-forward.
/// Returns [MergeNeedsCheckout] if the base's worktree vanished mid-flow.
Future<LocalPrMergeResult> finishLocalPrRebase(
  String repo,
  String branch,
  String baseRef,
) async {
  final baseWt = await worktreeHolding(repo, baseRef);
  if (baseWt == null) {
    return LocalPrMergeResult(
      MergeNeedsCheckout(
        branch: branch,
        baseRef: baseRef,
        message:
            'Rebased $branch, but $baseRef is no longer checked out — '
            'open it in a desk to finish the fast-forward.',
      ),
    );
  }
  return _fastForwardBaseToHead(repo, branch, baseRef, baseWt);
}

/// Derive "merged" from git rather than trusting the caller.
///
/// Merge-commit and rebase land [branch] as an ancestor of [baseRef], so
/// `merge-base --is-ancestor` is exact. A squash is different: it collapses
/// N commits into one, so per-commit patch-ids match nothing — `git cherry`
/// (which [detectSquashMergedBranches] uses for its own, different purpose)
/// reports every branch commit as still-unique and would reject a perfectly
/// good squash of N≥2 commits. The correct squash oracle is TREE EQUALITY:
/// a clean squash's committed tree IS the tree `merge-tree` builds from the
/// pre-merge base tip ([squashBaseBefore]) and the head — independent of how
/// many commits were folded in. We recompute that merged tree and require it
/// to equal `baseRef^{tree}` after the squash landed.
Future<bool> _verifyMerged(
  String repo,
  String baseRef,
  String branch,
  BranchMergeMethod method, {
  String? squashBaseBefore,
}) async {
  if (method == BranchMergeMethod.squash) {
    if (squashBaseBefore == null || squashBaseBefore.isEmpty) return false;
    // `merge-tree --write-tree` prints the merged tree SHA on a clean merge
    // (exit 0); a non-zero exit means it could not reproduce a clean tree,
    // which for an already-committed clean squash should never happen — treat
    // it as unverified rather than guessing.
    final mt = await _git(repo, [
      'merge-tree',
      '--write-tree',
      squashBaseBefore,
      branch,
    ]);
    if (mt.exitCode != 0) return false;
    final expectTree = (mt.stdout as String).trim().split('\n').first.trim();
    if (expectTree.isEmpty) return false;
    final actualTree = await _revParse(repo, '$baseRef^{tree}');
    return actualTree.isNotEmpty && actualTree == expectTree;
  }
  return _isAncestor(repo, branch, baseRef);
}

/// Paths git named in its untracked-overwrite refusal ("The following
/// untracked working tree files would be overwritten by merge: …"). Git
/// aborts before touching anything — the working tree is intact — so mapping
/// this to a typed blocked outcome (with the exact files) beats dumping raw
/// stderr. Empty when the stderr is some other failure.
List<String> _untrackedOverwritePaths(String stderr) {
  final paths = <String>[];
  var capturing = false;
  for (final line in stderr.split('\n')) {
    if (line.contains('would be overwritten by')) {
      capturing = true;
      continue;
    }
    if (!capturing) continue;
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    // The path list is tab-indented; the "Please move…/Aborting" epilogue and
    // any further error/warning lines close it.
    if (line.startsWith('Please ') ||
        line.startsWith('error:') ||
        line.startsWith('warning:') ||
        trimmed == 'Aborting' ||
        trimmed.startsWith('Merge with strategy')) {
      break;
    }
    paths.add(trimmed);
  }
  return paths;
}

Future<GitResult<CommitDetailData>> getCommitDetail(
  String repo,
  String hash,
) async {
  // Two calls: metadata + numstat, and name-status for change types
  final results = await Future.wait([
    _git(repo, [
      'show',
      '--numstat',
      '--format=%H%n%h%n%s%n%b%n---END-META---%n%aN%n%aE%n%aI',
      hash,
    ]),
    _git(repo, ['diff-tree', '--no-commit-id', '-r', '--name-status', hash]),
  ]);

  final r = results[0];
  final r2 = results[1];
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  // Parse change types from name-status output
  final changeTypes = <String, String>{};
  if (r2.exitCode == 0) {
    for (final line in r2.stdout.toString().split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final tabIdx = trimmed.indexOf('\t');
      if (tabIdx < 0) continue;
      final type = trimmed.substring(0, tabIdx).trim();
      final path = trimmed.substring(tabIdx + 1).trim();
      // For renames, git outputs "old\tnew" after the type — use the new path
      final finalPath = path.contains('\t') ? path.split('\t').last : path;
      changeTypes[finalPath] = type.substring(0, 1); // first char: M/A/D/R/C
    }
  }

  final output = r.stdout.toString();
  final metaEnd = output.indexOf('---END-META---');
  if (metaEnd == -1) return const GitResult.err('Unexpected git output');

  final metaLines = output.substring(0, metaEnd).split('\n');
  final fullHash = metaLines[0].trim();
  final shortHash = metaLines[1].trim();
  final subject = metaLines[2].trim();
  final bodyLines = <String>[];
  int mi = 3;
  while (mi < metaLines.length && metaLines[mi].trim() != '---END-META---') {
    bodyLines.add(metaLines[mi]);
    mi++;
  }

  // The format string emits `%n` right after the sentinel, so the first
  // split element is the empty tail of the sentinel's own line — the
  // identity fields start at index 1. (Indexing from 0 here shipped the
  // avatar-less metadata row for months: name read as '', email as the
  // name, and the noreply email landed in the date slot.)
  final afterMeta = output
      .substring(metaEnd + '---END-META---'.length)
      .split('\n');
  final authorName = afterMeta.length > 1 ? afterMeta[1].trim() : '';
  final authorEmail = afterMeta.length > 2 ? afterMeta[2].trim() : '';
  final authoredAt = afterMeta.length > 3 ? afterMeta[3].trim() : '';

  // Parse numstat lines: additions<tab>deletions<tab>path
  final files = <CommitFileStatData>[];
  for (final line in afterMeta.skip(4)) {
    final parts = line.trim().split('\t');
    if (parts.length < 3) continue;
    final adds = int.tryParse(parts[0]) ?? 0; // '-' for binaries → 0
    final dels = int.tryParse(parts[1]) ?? 0;
    final filePath = parts[2].trim();
    if (filePath.isEmpty) continue;
    files.add(
      CommitFileStatData(
        path: filePath,
        additions: adds,
        deletions: dels,
        changeType: changeTypes[filePath] ?? 'M',
      ),
    );
  }

  return GitResult.ok(
    CommitDetailData(
      commitHash: fullHash,
      shortHash: shortHash,
      subject: subject,
      body: bodyLines.join('\n').trim(),
      authorName: authorName,
      authorEmail: authorEmail,
      authoredAt: authoredAt,
      filesChanged: files.length,
      additions: files.fold(0, (s, f) => s + f.additions),
      deletions: files.fold(0, (s, f) => s + f.deletions),
      files: files,
    ),
  );
}

/// Lazily fetch per-file hunk headers for a commit. Header-only parse:
/// `git show --unified=0` emits one `@@ -a,b +c,d @@` per hunk, whose
/// counts already carry the composition (d added, b deleted) and the
/// new-file start line (c) — so we never touch a body line, and the
/// output we scan is ~one line per hunk, not one per changed line.
/// Keyed by new-file path (from the `+++ b/…` header; deletions key on
/// the `--- a/…` old path). Meant to be called once per commit-detail
/// open and cached by hash on the caller side.
/// Backstop on the hunk-header count collected for the seismograph. A treemap
/// of churn bands needs nowhere near this many; it only guards a pathological
/// commit with millions of scattered hunks from growing the map unbounded.
const int _kCommitHunkCap = 200000;

Future<GitResult<Map<String, List<CommitHunk>>>> getCommitHunks(
  String repo,
  String hash,
) async {
  // STREAM `git show --unified=0` line-by-line, keeping ONLY the hunk/file
  // headers. `--unified=0` drops context but still emits every +/- body line;
  // buffering all of them into one String + splitting it (the old code) meant a
  // multi-GB commit could exhaust memory just to draw churn bands. Here git
  // streams the body, we discard it a line at a time — memory is bounded by the
  // header count, not the patch size.
  final Process proc;
  try {
    proc = await _spawnStart([
      ..._kShowCmd,
      '--unified=0',
      '--no-color',
      '--no-ext-diff',
      '--format=',
      '-M',
      hash,
    ], workingDirectory: repo);
  } on Object catch (e) {
    return GitResult.err(e.toString());
  }

  final out = <String, List<CommitHunk>>{};
  // `@@ -oldStart[,oldCount] +newStart[,newCount] @@` — counts default to
  // 1 when omitted (git elides `,1`).
  final hunkRe = RegExp(r'^@@ -\d+(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');
  String? curNew; // path from +++ b/…
  String? curOld; // path from --- a/… (for deletions / dev-null new side)
  var hunkCount = 0;

  final errBuf = BytesBuilder(copy: false);
  final errDone = proc.stderr.forEach(errBuf.add);
  await proc.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .transform(const LineSplitter())
      .forEach((line) {
        // Once capped, keep draining stdout (so git isn't blocked on a full pipe)
        // but stop growing the map.
        if (hunkCount >= _kCommitHunkCap) return;
        if (line.startsWith('+++ ')) {
          final p = line.substring(4).trim();
          curNew = (p == '/dev/null') ? null : _stripDiffPrefix(p);
        } else if (line.startsWith('--- ')) {
          final p = line.substring(4).trim();
          curOld = (p == '/dev/null') ? null : _stripDiffPrefix(p);
        } else if (line.startsWith('@@')) {
          final m = hunkRe.firstMatch(line);
          if (m == null) return;
          final del = int.tryParse(m.group(1) ?? '') ?? 1;
          final newStart = int.tryParse(m.group(2) ?? '') ?? 0;
          final add = int.tryParse(m.group(3) ?? '') ?? 1;
          final key = curNew ?? curOld;
          if (key == null) return;
          (out[key] ??= <CommitHunk>[]).add(
            CommitHunk(newStart: newStart, additions: add, deletions: del),
          );
          hunkCount++;
        }
        // Body lines (+/-) are discarded — never stored.
      });
  final code = await proc.exitCode;
  await errDone;
  if (code != 0) {
    return GitResult.err(
      utf8.decode(errBuf.takeBytes(), allowMalformed: true).trim(),
    );
  }
  return GitResult.ok(out);
}

/// Strip the leading `a/` or `b/` git adds to diff header paths. Quoted
/// paths (non-ASCII / spaces) come wrapped in double quotes — leave those
/// alone; the seismograph keys on the numstat path and a mismatch just
/// means no bands for that one file (graceful).
String _stripDiffPrefix(String p) {
  if (p.length >= 2 && (p.startsWith('a/') || p.startsWith('b/'))) {
    return p.substring(2);
  }
  return p;
}

Future<GitResult<String>> getFileDiff(
  String repo,
  String path, {
  bool staged = false,
  int contextLines = 3,
}) async {
  final args = staged
      ? [
          ..._kDiffCmd,
          ..._kDiffContentPins,
          '--full-index',
          '--cached',
          '-U$contextLines',
          '--',
          path,
        ]
      : [
          ..._kDiffCmd,
          ..._kDiffContentPins,
          '--full-index',
          '-U$contextLines',
          '--',
          path,
        ];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString());
}

/// Everything a desk has *added* relative to where it diverged from
/// [targetRef], as a single unified diff. Run from inside the desk's
/// worktree and compared against the **merge-base** of [targetRef] and
/// the desk's HEAD, this folds:
///   • commits the desk has made since branching from [targetRef],
///   • uncommitted modifications to tracked files, AND
///   • untracked files in the desk's working tree
/// into one patch that, when applied to a [targetRef] worktree, brings
/// the desk's contributions over without reverting anything [targetRef]
/// has gained in the meantime. Returns an empty string when the desk
/// has nothing beyond the divergence point (no own commits, no WIP,
/// no new files).
/// Diffing against [targetRef] directly was an earlier implementation
/// and was wrong: when the desk was behind [targetRef], the resulting
/// patch contained reversals of every [targetRef] commit the desk
/// hadn't yet picked up. Imprinting that on a clean [targetRef]
/// worktree wiped real work. Merge-base scoping is the only shape
/// that captures "the desk's contribution" symmetrically across
/// ahead / behind / diverged states.
/// `git diff` ignores untracked files by default, so a separate
/// `ls-files --others --exclude-standard` pass enumerates them and
/// each is rendered as a synthetic `/dev/null → b/<path>` block. The
/// same helper [getSelectionDiff] uses on the changes page; format is
/// what `git apply` consumes for new-file creation.
/// Count commits the worktree's HEAD is ahead and behind [targetRef].
/// Returns `(ahead, behind)` — for "is the desk behind main?" the
/// caller reads `behind > 0 && ahead == 0` as "fast-forwardable."
/// Runs `git rev-list --left-right --count targetRef...HEAD` in the
/// desk's worktree. Returns err on detached HEAD with no resolvable
/// target, empty output, or unrelated histories.
Future<GitResult<({int ahead, int behind})>> getDeskAheadBehind(
  String deskPath,
  String targetRef,
) async {
  final res = await _git(deskPath, [
    'rev-list',
    '--left-right',
    '--count',
    '$targetRef...HEAD',
  ]);
  if (res.exitCode != 0) {
    return GitResult.err(
      res.stderr.toString().trim().isEmpty
          ? 'Could not compare with $targetRef.'
          : res.stderr.toString().trim(),
    );
  }
  final parts = res.stdout.toString().trim().split(RegExp(r'\s+'));
  if (parts.length < 2) {
    return GitResult.err('Unexpected rev-list output: "${res.stdout}"');
  }
  // left (targetRef-only) is "behind"; right (HEAD-only) is "ahead".
  final behind = int.tryParse(parts[0]) ?? 0;
  final ahead = int.tryParse(parts[1]) ?? 0;
  return GitResult.ok((ahead: ahead, behind: behind));
}

/// Fast-forward the desk's checked-out branch to [targetRef]. Fails
/// (ok=false, no side effects) if the fast-forward isn't possible —
/// i.e. the desk has diverged or has uncommitted changes that block
/// the merge. Callers should fall back to a patch / rebase flow in
/// that case. Succeeds when the desk is a strict ancestor of the
/// target and the worktree is clean: git moves HEAD + updates the
/// working tree in one atomic step.
Future<GitResult<void>> fastForwardDeskTo(
  String deskPath,
  String targetRef,
) async {
  final res = await _git(deskPath, ['merge', '--ff-only', targetRef]);
  if (res.exitCode != 0) {
    return GitResult.err(
      res.stderr.toString().trim().isEmpty
          ? 'Fast-forward from $targetRef failed.'
          : res.stderr.toString().trim(),
    );
  }
  return const GitResult.ok(null);
}

Future<GitResult<String>> getDeskDumpDiff(
  String deskPath,
  String targetRef, {
  int contextLines = 3,
}) async {
  final base = await _git(deskPath, ['merge-base', targetRef, 'HEAD']);
  if (base.exitCode != 0) {
    // No common ancestor — unrelated histories. There is no meaningful
    // "desk's contribution" to extract; surface the underlying error so
    // the caller can show it instead of silently dumping a giant
    // whole-tree diff.
    return GitResult.err(
      base.stderr.toString().trim().isEmpty
          ? 'No common history between desk and $targetRef.'
          : base.stderr.toString().trim(),
    );
  }
  final mergeBase = base.stdout.toString().trim();

  // Tracked changes since divergence (committed + WIP modifications).
  final tracked = await _git(deskPath, [
    ..._kDiffCmd,
    ..._kDiffContentPins,
    '--full-index',
    '-U$contextLines',
    mergeBase,
  ]);
  if (tracked.exitCode != 0) {
    return GitResult.err(tracked.stderr.toString().trim());
  }

  // Untracked files — enumerate then synthesize new-file diffs.
  // --exclude-standard honours .gitignore + .git/info/exclude + the
  // user's global excludes, so ignored junk doesn't leak into the dump.
  final untracked = await _git(deskPath, [
    'ls-files',
    '--others',
    '--exclude-standard',
  ]);
  if (untracked.exitCode != 0) {
    return GitResult.err(untracked.stderr.toString().trim());
  }
  final untrackedPaths = untracked.stdout
      .toString()
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  final parts = <String>[];
  final trackedOut = tracked.stdout.toString();
  if (trackedOut.trim().isNotEmpty) parts.add(trackedOut);
  for (final path in untrackedPaths) {
    // git --no-index synthesizes the new-file diff with bounded memory (no
    // whole-file read). Exit 1 = "differs from /dev/null" = expected success.
    // ANY other exit is a real failure (permission, vanished path, git error) —
    // fail the whole dump rather than silently returning an INCOMPLETE one that
    // a caller would persist/transfer believing it holds the full change.
    final r = await _git(deskPath, _untrackedDiffArgs(path));
    if (r.exitCode == 0 || r.exitCode == 1) {
      parts.add(r.stdout.toString().trim());
    } else {
      return GitResult.err(
        'untracked diff failed for "$path": ${r.stderr.toString().trim()}',
      );
    }
  }
  return GitResult.ok(parts.where((p) => p.trim().isNotEmpty).join('\n'));
}

/// Base revision for the combined selection diff: `HEAD` when it exists,
/// else the repo's empty tree (unborn HEAD — no commit yet), resolved with
/// `hash-object -t tree /dev/null` so it is correct under SHA-1 and SHA-256
/// repos alike.
Future<GitResult<String>> _selectionDiffBase(String repo) async {
  final head = await _git(repo, ['rev-parse', '--verify', 'HEAD']);
  if (head.exitCode == 0) return const GitResult.ok('HEAD');
  final emptyTree = await _git(repo, [
    'hash-object',
    '-t',
    'tree',
    '/dev/null',
  ]);
  if (emptyTree.exitCode != 0) {
    return GitResult.err(emptyTree.stderr.toString().trim());
  }
  return GitResult.ok(emptyTree.stdout.toString().trim());
}

/// The combined "all changes in this selection" diff.
///
/// Tracked paths are diffed in ONE `git diff <base> -- <paths>` pass
/// (HEAD→worktree), never a `--cached` pass plus an unstaged pass. The
/// two-pass shape emitted the SAME path twice for a staged+unstaged (`MM`)
/// file, and no consumer could handle that: the document model keys
/// sections, slices, and navigation by path, so the eager slicer silently
/// dropped the staged section (last-wins) while the lazy index kept an
/// unreachable duplicate. One pass makes duplicate sections structurally
/// impossible AND shows the full HEAD→worktree delta for `MM` files. The
/// deliberate consequence: a staged change undone in the worktree nets to
/// nothing here — correct for a combined view; the per-file staged/unstaged
/// views carry the split story.
Future<GitResult<String>> getSelectionDiff(
  String repo,
  List<RepositoryStatusFile> files, {
  int contextLines = 3,
}) async {
  if (files.isEmpty) {
    return const GitResult.ok('');
  }

  final trackedPaths = files
      .where((file) => !_isUntrackedFile(file))
      .map((file) => file.path)
      .toList();
  final hasTrackedChange = files.any(
    (file) =>
        !file.isUntracked && (file.hasStagedChange || file.hasUnstagedChange),
  );

  final futures = <Future<GitResult<String>>>[];

  if (trackedPaths.isNotEmpty && hasTrackedChange) {
    Future<GitResult<String>> trackedPass() async {
      final base = await _selectionDiffBase(repo);
      if (!base.ok) return GitResult<String>.err(base.error ?? 'no base');
      final r = await _git(repo, [
        ..._kDiffCmd,
        ..._kDiffContentPins,
        '--full-index',
        '-U$contextLines',
        base.data!,
        '--',
        ...trackedPaths,
      ]);
      return r.exitCode != 0
          ? GitResult<String>.err(r.stderr.toString().trim())
          : GitResult<String>.ok(r.stdout.toString().trim());
    }

    futures.add(trackedPass());
  }

  // Untracked files: let git synthesize the new-file diff via `--no-index`
  // (bounded memory) instead of reading the whole file into Dart. `--no-index`
  // exits 1 when the file differs from /dev/null (always, for a new file), so
  // treat 0 and 1 as success.
  final untrackedFutures = files.where(_isUntrackedFile).map((f) async {
    final r = await _git(repo, _untrackedDiffArgs(f.path));
    if (r.exitCode != 0 && r.exitCode != 1) {
      return GitResult<String>.err(r.stderr.toString().trim());
    }
    return GitResult.ok(r.stdout.toString().trim());
  }).toList();

  final results = await Future.wait([...futures, ...untrackedFutures]);

  final parts = <String>[];
  for (final r in results) {
    if (!r.ok) return GitResult.err(r.error ?? 'git diff failed');
    final output = r.data?.trim() ?? '';
    if (output.isNotEmpty) parts.add(output);
  }

  return GitResult.ok(parts.join('\n'));
}

/// A combined diff streamed straight to a temp spool file — its bytes never all
/// resided in RAM. Feed [path] to `DiffDocument.lazyFromSpool` for a disk-backed
/// document whose resident memory is independent of diff size. The owner MUST
/// call [dispose] when done to delete the spool.
class SpooledDiff {
  final String path;
  final String _dir;
  final int byteLength;
  const SpooledDiff(this.path, this._dir, this.byteLength);

  /// The owning temp directory — hand to `DiffDocument.lazyFromSpool`'s
  /// `ownedTempDir` so the document deletes it on dispose (single owner).
  String get dir => _dir;

  Future<void> dispose() async {
    try {
      await Directory(_dir).delete(recursive: true);
    } catch (_) {}
  }
}

/// Read a spool file back as text with the SAME leniency as the exec
/// layer's stdout decode (`_decodeGitBytes` with `allowMalformed`): a spool
/// holds raw git output, and repos legitimately contain non-UTF-8 bytes in
/// patchable content. A strict `readAsString()` here would THROW on diffs
/// the lenient pipeline (and the FileByteStore render path) degrades to
/// U+FFFD and shows fine — re-materializing a small spool must never be
/// stricter than fetching the same bytes as a String would have been.
Future<String> readSpoolStringLenient(String spoolPath) async {
  final bytes = await File(spoolPath).readAsBytes();
  return utf8.decode(bytes, allowMalformed: true);
}

/// Write an already-built [content] String to a temp spool file in bounded,
/// surrogate-safe chunks, and return a [SpooledDiff] over it. Two properties
/// matter: the chunking keeps the write from doubling peak memory, and a chunk
/// boundary NEVER splits a UTF-16 surrogate pair (a lone high surrogate would
/// encode to a replacement byte and corrupt the diff). Used as the retroactive
/// spill when a diff was fetched in-RAM but turns out too large to hold.
Future<SpooledDiff> spoolStringToTempFile(
  String content, {
  int chunkSize = 4 * 1024 * 1024,
}) async {
  final dir = await Directory.systemTemp.createTemp('manifold_diff');
  final file = File('${dir.path}/selection.diff');
  final raf = await file.open(mode: FileMode.write);
  try {
    var i = 0;
    while (i < content.length) {
      var end = (i + chunkSize < content.length)
          ? i + chunkSize
          : content.length;
      if (end < content.length) {
        final cu = content.codeUnitAt(end - 1);
        if (cu >= 0xD800 && cu <= 0xDBFF) end++; // keep surrogate pair whole
      }
      await raf.writeString(content.substring(i, end));
      i = end;
    }
  } finally {
    await raf.close();
  }
  final len = await file.length();
  return SpooledDiff(file.path, dir.path, len);
}

/// [getFileDiff], but streamed to a temp spool file instead of returned as a
/// (potentially multi-GB) `String`. For a large tracked modification this keeps
/// git's output off the Dart heap entirely — the diff never has to fit in a
/// String before it can be spooled. Returns an empty [SpooledDiff] (byteLength
/// 0) when the file has no diff on the requested side (e.g. it is untracked, or
/// has no staged/unstaged change), so the caller can fall through.
Future<GitResult<SpooledDiff>> spoolFileDiff(
  String repo,
  String path, {
  bool staged = false,
  int contextLines = 3,
}) async {
  final args = staged
      ? [
          ..._kDiffCmd,
          ..._kDiffContentPins,
          '--full-index',
          '--cached',
          '-U$contextLines',
          '--',
          path,
        ]
      : [
          ..._kDiffCmd,
          ..._kDiffContentPins,
          '--full-index',
          '-U$contextLines',
          '--',
          path,
        ];
  final dir = await Directory.systemTemp.createTemp('manifold_diff');
  final spool = File('${dir.path}/file.diff');
  final sink = spool.openWrite();
  try {
    await _streamGitDiffInto(sink, repo, args);
    await sink.flush();
    await sink.close();
    final len = await spool.length();
    return GitResult.ok(SpooledDiff(spool.path, dir.path, len));
  } catch (e) {
    try {
      await sink.close();
    } catch (_) {}
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    return GitResult.err(e.toString());
  }
}

/// Stream a diff (produced by [primaryArgs], falling back to [fallbackArgs] on a
/// root-commit-style revision error) to a fresh spool file. The fallback resets
/// the spool first so a partial primary write can't corrupt it. Shared by the
/// history spool functions.
Future<GitResult<SpooledDiff>> _spoolDiffWithFallback(
  String repo,
  List<String> primaryArgs,
  List<String> fallbackArgs,
) async {
  final dir = await Directory.systemTemp.createTemp('manifold_diff');
  final spool = File('${dir.path}/rev.diff');
  var sink = spool.openWrite();
  try {
    try {
      await _streamGitDiffInto(sink, repo, primaryArgs);
    } on ProcessException catch (e) {
      final err = e.message;
      final rootish =
          err.contains('unknown revision') ||
          err.contains('ambiguous argument') ||
          err.contains('bad revision');
      if (!rootish) rethrow;
      await sink.close();
      sink = spool.openWrite(); // truncate any partial primary output
      await _streamGitDiffInto(sink, repo, fallbackArgs);
    }
    await sink.flush();
    await sink.close();
    final len = await spool.length();
    return GitResult.ok(SpooledDiff(spool.path, dir.path, len));
  } catch (e) {
    try {
      await sink.close();
    } catch (_) {}
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    return GitResult.err(e.toString());
  }
}

/// `git diff <hash>~1..<hash>` (falling back to `git show <hash>` for root
/// commits, which have no parent), streamed to a spool (bounded memory) —
/// for large commits.
Future<GitResult<SpooledDiff>> spoolCommitDiff(String repo, String hash) =>
    _spoolDiffWithFallback(
      repo,
      [..._kDiffCmd, ..._kDiffContentPins, '--full-index', '$hash~1..$hash'],
      [..._kShowCmd, ..._kDiffContentPins, '--full-index', hash],
    );

/// [getFileDiffAtRevision], streamed to a spool (bounded memory).
Future<GitResult<SpooledDiff>> spoolFileDiffAtRevision(
  String repo,
  String filePath,
  String commitHash,
) => _spoolDiffWithFallback(
  repo,
  [
    ..._kDiffCmd,
    ..._kDiffContentPins,
    '--full-index',
    '$commitHash~1..$commitHash',
    '--',
    filePath,
  ],
  [
    ..._kShowCmd,
    ..._kDiffContentPins,
    '--full-index',
    commitHash,
    '--',
    filePath,
  ],
);

/// Spool byte length above which a fetched PR-detail diff stays on disk as
/// the detail's [SpooledDiff] instead of materializing into the String form.
/// Every detail loader STREAMS its diff to a spool during transport (gh/glab
/// CLI stdout, Gitea's uncapped `.diff` response, the local desk range diff),
/// so this threshold reads the spool's REAL on-disk byte count — never a
/// String proxy. 8 MiB sits above what the hosted forges serve for ordinary
/// PRs while a machine-scale patch stays on the bounded path.
const int kDetailDiffSpillBytes = 8 * 1024 * 1024;

/// `git diff --numstat -z [--find-renames] <spec>` for an arbitrary revision
/// range spec (`base...head` / `base..head`), through the gated exec layer
/// with the diff-family pins — raw `Process.run` here would re-open the
/// hostile-config class (`color.diff=always` corrupting the parse) the pins
/// closed. Returns raw NUL-separated stdout for the caller to parse.
Future<GitResult<String>> getRangeNumstatZ(
  String repo,
  String spec, {
  bool findRenames = false,
}) async {
  final r = await _git(repo, [
    ..._kDiffCmd,
    ..._kDiffContentPins,
    '--numstat',
    '-z',
    if (findRenames) '--find-renames',
    spec,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString());
}

/// `git diff [--find-renames] <spec>` as a String — for ranges the numstat
/// probe has already sized as small. Same pins as every textual-diff site.
Future<GitResult<String>> getRangeDiff(
  String repo,
  String spec, {
  bool findRenames = false,
}) async {
  final r = await _git(repo, [
    ..._kDiffCmd,
    ..._kDiffContentPins,
    if (findRenames) '--find-renames',
    spec,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString());
}

/// [getRangeDiff], streamed to a spool (bounded memory). Callers stream
/// FIRST and let the spool's actual [SpooledDiff.byteLength] pick the
/// representation — no numstat/churn heuristic can be trusted to predict
/// patch bytes (a handful of very long lines reads as tiny churn; binary
/// churn reads as 0). The diff never exists as a Dart String at any point.
Future<GitResult<SpooledDiff>> spoolRangeDiff(
  String repo,
  String spec, {
  bool findRenames = false,
}) async {
  final args = [
    ..._kDiffCmd,
    ..._kDiffContentPins,
    if (findRenames) '--find-renames',
    spec,
  ];
  final dir = await Directory.systemTemp.createTemp('manifold_diff');
  final spool = File('${dir.path}/range.diff');
  final sink = spool.openWrite();
  try {
    await _streamGitDiffInto(sink, repo, args);
    await sink.flush();
    await sink.close();
    final len = await spool.length();
    return GitResult.ok(SpooledDiff(spool.path, dir.path, len));
  } catch (e) {
    try {
      await sink.close();
    } catch (_) {}
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    return GitResult.err(e.toString());
  }
}

/// [getSelectionDiff], but the combined diff is streamed to a temp file instead
/// of assembled into one (potentially multi-GB) `String`. Each `git diff`
/// invocation's stdout is piped to disk with backpressure, so peak RAM stays
/// bounded regardless of diff size — the machine-scale path for the changes
/// list. Tracked paths ride ONE HEAD→worktree pass for the same reason as
/// [getSelectionDiff]: a `--cached` + unstaged pass pair emitted duplicate
/// path sections for `MM` files, which the path-keyed document model cannot
/// represent. The parts concatenate exactly as [getSelectionDiff] joins
/// them: every `git diff` block ends in a newline, so raw concatenation
/// yields the same single-newline separation between files.
Future<GitResult<SpooledDiff>> spoolSelectionDiff(
  String repo,
  List<RepositoryStatusFile> files, {
  int contextLines = 3,
}) async {
  if (files.isEmpty) return const GitResult.err('no files');

  final trackedPaths = files
      .where((file) => !_isUntrackedFile(file))
      .map((file) => file.path)
      .toList();
  final hasTrackedChange = files.any(
    (file) =>
        !file.isUntracked && (file.hasStagedChange || file.hasUnstagedChange),
  );

  final dir = await Directory.systemTemp.createTemp('manifold_diff');
  final spool = File('${dir.path}/selection.diff');
  final sink = spool.openWrite();
  try {
    if (trackedPaths.isNotEmpty && hasTrackedChange) {
      final base = await _selectionDiffBase(repo);
      if (!base.ok) {
        throw ProcessException('git', const ['rev-parse'], base.error ?? '', 1);
      }
      await _streamGitDiffInto(sink, repo, [
        ..._kDiffCmd,
        ..._kDiffContentPins,
        '--full-index',
        '-U$contextLines',
        base.data!,
        '--',
        ...trackedPaths,
      ]);
    }
    for (final f in files.where(_isUntrackedFile)) {
      // Stream the untracked file's new-file diff straight from git to disk —
      // git reads it with bounded memory; nothing whole-file lands in Dart RAM.
      await _streamGitDiffInto(
        sink,
        repo,
        _untrackedDiffArgs(f.path),
        okCodes: const {0, 1},
      );
    }
    await sink.flush();
    await sink.close();
    final len = await spool.length();
    return GitResult.ok(SpooledDiff(spool.path, dir.path, len));
  } catch (e) {
    try {
      await sink.close();
    } catch (_) {}
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
    return GitResult.err(e.toString());
  }
}

/// Pipe one `git diff` invocation's stdout into [sink] with backpressure (so a
/// multi-GB diff never buffers in RAM), draining stderr concurrently to avoid a
/// pipe deadlock. Throws with the stderr text on an unexpected exit.
///
/// [okCodes] are the exit codes treated as success. Default `{0}`; the untracked
/// path passes `{0, 1}` because `git diff --no-index` exits 1 whenever the files
/// differ — which, against `/dev/null`, is always true for a non-empty new file.
Future<void> _streamGitDiffInto(
  IOSink sink,
  String repo,
  List<String> args, {
  Set<int> okCodes = const {0},
}) async {
  // Same choreography contract as every other git subprocess: a semaphore
  // permit (streamed diff fetches are the MAIN diff path now — many
  // concurrent PR/history loads must not spawn unbounded git processes) and
  // the start/success/failure lifecycle events. Deliberately NO index.lock
  // retry and no mutation bump: these are pure reads, and a retry could not
  // replay bytes already streamed into [sink] anyway.
  final commandLabel = 'git.${_gitSubcommandToken(args) ?? 'diff'}.stream';
  final stopwatch = Stopwatch()..start();
  DiagnosticsState.instance.recordCommandLifecycleEvent(
    type: 'start',
    command: commandLabel,
  );
  await _gitSubprocessSemaphore.acquire();
  var lifecycleRecorded = false;
  try {
    final proc = await _spawnStart(args, workingDirectory: repo);
    final errBuf = BytesBuilder(copy: false);
    final errDone = proc.stderr.forEach(errBuf.add);
    try {
      await sink.addStream(proc.stdout);
    } catch (_) {
      // A sink write failure (disk full, spool dir vanished) must not
      // orphan the live git child mid-stream: kill it and drain the
      // stderr reader + exit code so nothing dangles or throws
      // unobserved, then let the outer catch record the failure.
      proc.kill();
      try {
        await errDone;
      } catch (_) {}
      try {
        await proc.exitCode;
      } catch (_) {}
      rethrow;
    }
    final code = await proc.exitCode;
    await errDone;
    stopwatch.stop();
    final ok = okCodes.contains(code);
    lifecycleRecorded = true;
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: ok ? 'success' : 'failure',
      command: commandLabel,
      durationMs: stopwatch.elapsedMicroseconds / 1000,
      errorCode: ok ? null : 'git.exit_$code',
    );
    if (!ok) {
      throw ProcessException(
        'git',
        args,
        utf8.decode(errBuf.takeBytes(), allowMalformed: true).trim(),
        code,
      );
    }
  } catch (e) {
    if (!lifecycleRecorded) {
      stopwatch.stop();
      DiagnosticsState.instance.recordCommandLifecycleEvent(
        type: 'failure',
        command: commandLabel,
        durationMs: stopwatch.elapsedMicroseconds / 1000,
        errorCode: 'git.stream_failed',
        message: e.toString(),
      );
    }
    rethrow;
  } finally {
    _gitSubprocessSemaphore.release();
  }
}

/// `git diff --no-index -- /dev/null <path>` — makes git itself emit the
/// new-file diff (a `+` for every line) for an UNTRACKED file, reading the file
/// with git's own bounded memory. This replaces reading the whole file into a
/// Dart `Uint8List` + decoding + splitting into a 15M-object line list (the
/// marble OOM). `/dev/null` is understood by git on every platform (it maps to
/// `nul` on Windows). Binary new files emit `Binary files … differ` naturally.
List<String> _untrackedDiffArgs(String path) => [
  ..._kDiffCmd,
  '--no-index',
  ..._kDiffContentPins,
  '--',
  '/dev/null',
  path,
];

bool _isUntrackedFile(RepositoryStatusFile file) => file.isUntracked;

/// True when a selection contains a tracked deletion whose source blob is not
/// present in the working tree. A filesystem-size estimate necessarily sees
/// that path as zero bytes, although its patch can be arbitrarily large. Route
/// these selections to [spoolSelectionDiff] before starting `git diff` so the
/// deletion never first exists as a Dart String.
bool selectionContainsTrackedDeletion(List<RepositoryStatusFile> files) =>
    files.any(
      (file) =>
          !file.isUntracked &&
          (file.stagedCode == 'D' || file.unstagedCode == 'D'),
    );

Future<Uint8List?> gitBlobBytes(String repo, String objectHash) async {
  await _gitSubprocessSemaphore.acquire();
  try {
    final raw = await _spawnRunRaw(
      ['cat-file', 'blob', objectHash],
      workingDirectory: repo,
      environment: _kNonInteractiveGitEnv,
    );
    if (raw.exitCode != 0) return null;
    return Uint8List.fromList(raw.stdout as List<int>);
  } finally {
    _gitSubprocessSemaphore.release();
  }
}

Future<Uint8List?> gitBlobHeader(
  String repo,
  String objectHash, [
  int bytes = 32,
]) async {
  await _gitSubprocessSemaphore.acquire();
  Process? proc;
  try {
    proc = await _spawnStart(
      ['cat-file', 'blob', objectHash],
      workingDirectory: repo,
      environment: _kNonInteractiveGitEnv,
    );
    final stderrDrained = proc.stderr.drain<void>();
    final chunk = <int>[];
    await for (final data in proc.stdout) {
      chunk.addAll(data);
      if (chunk.length >= bytes) break;
    }
    proc.kill();
    await Future.wait([proc.exitCode, stderrDrained]);
    return chunk.isEmpty
        ? null
        : Uint8List.fromList(chunk.sublist(0, chunk.length.clamp(0, bytes)));
  } finally {
    proc?.kill();
    _gitSubprocessSemaphore.release();
  }
}

Future<int?> gitBlobSize(String repo, String objectHash) async {
  final r = await _git(repo, ['cat-file', '-s', objectHash]);
  if (r.exitCode != 0) return null;
  return int.tryParse(r.stdout.toString().trim());
}

Future<GitResult<List<BranchInfo>>> listBranches(String repo) async {
  // Five fields: name, HEAD-marker, upstream short, upstream track,
  // committer date (ISO8601). Tab-delimited because branch names can
  // contain spaces and committerdate's ISO form contains them too.
  final r = await _git(repo, [
    'branch',
    '-vv',
    '--format=%(refname:short)%09%(HEAD)%09%(upstream:short)%09%(upstream:track)%09%(committerdate:iso8601)',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final branches = <BranchInfo>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    final name = parts[0].trim();
    final isCurrent = parts.length > 1 && parts[1].trim() == '*';
    final upstream = parts.length > 2 && parts[2].trim().isNotEmpty
        ? parts[2].trim()
        : null;
    int ahead = 0, behind = 0;
    var gone = false;
    if (parts.length > 3) {
      final track = parts[3];
      final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(track);
      final behindMatch = RegExp(r'behind (\d+)').firstMatch(track);
      if (aheadMatch != null) ahead = int.tryParse(aheadMatch.group(1)!) ?? 0;
      if (behindMatch != null) {
        behind = int.tryParse(behindMatch.group(1)!) ?? 0;
      }
      // git reports `[gone]` in the upstream:track field when the
      // remote tracking branch was deleted (typically: PR merged +
      // remote branch deleted on the forge). The local copy is now
      // orphaned — safe to delete. Match on the bracket form
      // explicitly so a branch literally named "gone" or unusual
      // tracking strings can't false-positive.
      if (track.contains('[gone]')) gone = true;
    }
    DateTime? lastCommitAt;
    if (parts.length > 4) {
      lastCommitAt = DateTime.tryParse(parts[4].trim());
    }
    branches.add(
      BranchInfo(
        name: name,
        current: isCurrent,
        upstream: upstream,
        ahead: ahead,
        behind: behind,
        gone: gone,
        lastCommitAt: lastCommitAt,
      ),
    );
  }
  return GitResult.ok(branches);
}

/// Commit timestamps (UNIX seconds) on [branch] over the last 90 days,
/// walking first-parent only, newest-first, capped at 300 rows. Feeds
/// the branches lens churn sparkline — a per-branch histogram of recent
/// activity so a hot branch reads dense at a glance.
///
/// `%ct` already emits the committer date as a UNIX timestamp; the
/// redundant `--date=unix` is harmless and pins the intent. Returns an
/// empty list on any failure (bad ref, huge repo, spawn error) so the
/// caller renders the row identically minus the spark — never an error
/// surface.
Future<List<int>> branchChurnTimestamps(String repo, String branch) async {
  try {
    final r = await _git(repo, [
      'log',
      branch,
      '--since=90.days',
      '--date=unix',
      '--format=%ct',
      '--first-parent',
      '-n',
      '300',
    ]);
    if (r.exitCode != 0) return const [];
    final out = <int>[];
    for (final line in r.stdout.toString().split('\n')) {
      final v = int.tryParse(line.trim());
      if (v != null) out.add(v);
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// For each branch in [branches], determine whether all of its
/// commits have a patch-id-equivalent commit on [baseRef]. The killer
/// detection that `git branch --merged` misses: a PR merged via
/// squash-merge produces a single commit on main with a different
/// SHA from the branch's commits, so `--merged` reports false even
/// though the branch's work IS in main.
///
/// Uses `git cherry <base> <branch>`: each line begins with `+` or
/// `-`. `-` means the patch-id is already in [baseRef] (squash-merged
/// or cherry-picked). `+` means unique work. A branch is "fully
/// squash-merged" iff every line is `-` (and there's at least one
/// line — empty output means the branch is identical to base).
///
/// Probed via a bounded worker pool. Branches with their `current`
/// flag set are skipped (don't waste a probe on the active branch).
/// Returns a fresh list with [BranchInfo.squashMerged] populated;
/// preserves all other fields and ordering.
///
/// Concurrency is capped at [_squashProbeMaxConcurrency] so a repo
/// with 50+ branches doesn't fork 50+ git processes in one tick.
/// `git cherry` is cheap individually but each probe is a full
/// process spawn + index walk; a hard cap keeps Manifold from
/// behaving differently on big repos than small ones.
Future<List<BranchInfo>> detectSquashMergedBranches(
  String repo,
  List<BranchInfo> branches, {
  required String baseRef,
}) async {
  Future<bool?> probe(BranchInfo b) async {
    if (b.current) return null;
    if (b.name == baseRef) return null;
    try {
      final r = await _git(repo, ['cherry', baseRef, b.name]);
      if (r.exitCode != 0) return null;
      final lines = r.stdout
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) return null; // identical to base; --merged catches it
      return lines.every((l) => l.startsWith('- '));
    } catch (_) {
      return null;
    }
  }

  final flags = List<bool?>.filled(branches.length, null);
  // Index-stream worker pool: an atomic counter hands the next
  // unclaimed branch index to each worker as it finishes its
  // current probe. Cheaper than chunking (no idle workers waiting
  // on the slowest probe in their batch) and order-preserving
  // because we write into `flags` by the original index.
  var next = 0;
  final workers = math.min(squashProbeMaxConcurrency, branches.length);
  await Future.wait(
    List.generate(
      workers,
      (_) => Future(() async {
        while (true) {
          final i = next++;
          if (i >= branches.length) return;
          flags[i] = await probe(branches[i]);
        }
      }),
    ),
  );
  return [
    for (var i = 0; i < branches.length; i++)
      branches[i].copyWith(squashMerged: flags[i]),
  ];
}

/// Cap on the number of `git cherry` probes we'll run concurrently in
/// [detectSquashMergedBranches]. Keep this below the global git
/// subprocess cap so background squash detection cannot monopolize every
/// permit needed by UI-critical status/diff probes.
@visibleForTesting
const int squashProbeMaxConcurrency = gitSubprocessMaxConcurrency - 1;

// ===========================================================================
// THE ABSORPTION LAW — judge a branch by content, not ancestry.
// ===========================================================================
//
// Git's ancestry is testimony; the tree is ground truth. When the owner
// develops in a worktree and TRANSPLANTS the changes onto main (Manifold's
// move-changes flow) instead of merging — or squash-merges, cherry-picks, or
// replays amended commits — the CONTENT lands in main but no parent edge
// records it. So `git branch --merged` and ahead/behind lie ("12 ahead" of
// ghosts) and the branch reads live/idle when it is actually spent.
//
// The exact test is EXISTENTIAL OVER HISTORY, not a tip check. Absorption is
// a historical event: at the moment of the squash/transplant, merging the
// branch into that base commit was a no-op — the base evolving afterwards
// (even rewriting the very same files) cannot revoke delivery. Evaluating
// only at base's tip damns branches whose files base has since touched
// (orrery: squash-merged, then history_page.dart moved on → tip merge-tree
// conflicts even though delivery happened). The corrected law:
//
//   absorbed(b, m)  ⇔  ∃ commit c on m's first-parent line since fork(b, m):
//                        merge-tree --write-tree(c, b) == c^{tree}
//
// Once a witness c exists, absorbed is PERMANENT. The tip-only check is the
// special case c = tip — kept as the instant accept (cheapest witness, no
// walk). The proof search, in cost order:
//
//   1. TIP        — merge-tree(tip, b) == tip^{tree}: one probe, no walk.
//   2. PATCH-ID   — the branch's cumulative change (diff fork→b) hashed via
//                   `git patch-id --stable`, matched against every
//                   first-parent commit's patch-id (one batched
//                   `log --first-parent -p` pipeline). A hit is a CANDIDATE
//                   only: patch-id hashes normalized hunks (near-exact), so
//                   the candidate is confirmed with the tree algebra —
//                   merge-tree(c, b) == c^{tree} — before we claim anything.
//                   Catches clean transplants and squashes applied to a
//                   fork-identical parent.
//   3. LINEAR SCAN— fork-forward walk of first-parent commits for split
//                   transplants / amended replays where no single commit's
//                   patch matches. UNCAPPED — fork to base tip, always; the
//                   verdict is always a proven yes or a proven no. Pruned
//                   exactly (derivations at the scan): only commits that
//                   touch a branch file after full coverage can be
//                   witnesses, blob-exact candidates resolve in memory, and
//                   the added-line necessary condition rejects hunk-subset
//                   non-witnesses from one `cat-file --batch`.
//
// The law itself is the optimization — two permanence properties make
// re-probes near-free:
//   * PERMANENCE CACHE: absorbed is forever (delivery cannot be revoked),
//     so a witnessed verdict keyed by (repo, branch tip, base) never
//     re-probes while the branch tip is unchanged.
//   * INCREMENTAL FRONTIER: a proven-no verdict records how far up base's
//     first-parent line it examined (plus the scan state at that point);
//     the next probe examines only base commits newer than the frontier —
//     usually zero. The frontier self-invalidates when the branch tip
//     moves (it's in the key) or the fork changes (base rebase/force-push,
//     detected by fork-hash mismatch → full rescan; correctness beats
//     cleverness).
//
// Concurrency note: batch trials run through the global git semaphore
// (adaptive, starts at [gitSubprocessMaxConcurrency] = 6). Measured on the
// 12-core dev box (cold 9-branch batch, two runs each): 6 permits → 4.1s /
// 5.5s; 12 permits → 7.2s / 4.1s. Overlapping ranges, worst case at 12 —
// raising the start buys nothing and risks the documented spawn-thrash
// (see the constant's own telemetry), so the start stays 6 and the
// controller keeps tuning the live limit.
//
// Honest nuance, intended and documented: a branch absorbed and then
// REVERTED on base still reports absorbed. The law reports DELIVERY, not
// present containment — the whisper word stays truthful about the event.
//
// This subsumes squash detection (a tree-equal squash is one way to be
// absorbed) and covers transplants / cherry-picks / amended replays alike —
// any ceremony, because we compare merged TREES, never the commit graph.
//
// `git merge-tree --write-tree` requires git >= 2.38. On older gits the probe
// reports null (unknown) and callers fall back to the legacy `git cherry`
// tree-equality squash check ([detectSquashMergedBranches]).

/// How the absorption witness was found — the proof path, cheapest first.
enum AbsorptionWitnessVia {
  /// c = base tip: merging right now is a no-op.
  tip,

  /// Batched patch-id match located the candidate, tree algebra confirmed.
  patchId,

  /// Fork-forward coverage-pruned linear scan found the witness.
  scan,
}

/// Structured verdict of the absorption law for one branch against one base.
typedef BranchAbsorption = ({
  /// True iff SOME first-parent commit of base since the fork point absorbs
  /// the branch (merging into it is a no-op). Permanent once witnessed.
  bool absorbed,

  /// The witness commit hash when [absorbed] — the courtroom exhibit: the
  /// exact base commit into which merging the branch changes nothing.
  String? witness,

  /// Which proof path produced [witness]. Null when not absorbed.
  AbsorptionWitnessVia? via,

  /// The exact files this branch still uniquely holds AT TIP — `diff-tree`
  /// between base's tree and the merged result on a clean merge, or the
  /// conflicted paths on a conflicted one. Tip-scoped by design: it answers
  /// "what would merging now bring", which only makes sense at tip. Empty
  /// when tip-absorbed. (On a permanence-cache hit these fields are frozen
  /// at witness time — the UI never reads them for absorbed rows.)
  List<String> outstandingFiles,

  /// True when the TIP trial merge could not be resolved automatically.
  /// Tip-scoped like [outstandingFiles]; a historically-absorbed branch can
  /// be conflicted at tip (base rewrote its files after delivery).
  bool conflicted,
});

// ── The two permanence caches (see the law comment above) ──────────────
//
// Keys are `repo NUL branchTip NUL base` — the branch TIP HASH, not the
// name, so any movement of the branch (new commit, amend, rebase) simply
// misses the cache and re-proves. The NUL separator appears only via a
// string escape in source (never a raw byte — the logos_flow incident) and
// cannot occur in a path, a hash, or a ref name — the key is
// injection-proof.

/// Absorption cache key. The separator is written as an escape on purpose;
/// see the block comment above.
String _absorptionKey(String repo, String branchTip, String base) =>
    '$repo\u0000$branchTip\u0000$base';

/// Proven-yes verdicts. Absorbed is PERMANENT for a fixed branch tip:
/// delivery cannot be revoked by anything base does later, so this map is
/// never invalidated — entries just stop being reachable when a tip moves.
final Map<String, BranchAbsorption> _absorbedVerdictCache = {};

/// Scan state behind a proven-no verdict: how far up base's first-parent
/// line the scan examined, and the accumulated per-branch-file state at
/// that point, so the next probe continues instead of restarting.
class _AbsorptionFrontier {
  _AbsorptionFrontier({
    required this.fork,
    required this.scannedTo,
    required this.coveredBranchFiles,
    required this.currentBlobs,
    required this.tipOutstanding,
    required this.tipConflicted,
  });

  /// merge-base(base, branch) at scan time. A mismatch on a later probe
  /// means base history was rewritten under us → full rescan from fork.
  final String fork;

  /// Base tip (inclusive) fully examined by the scan.
  final String scannedTo;

  /// covered ∩ branchFiles at [scannedTo] (coverage only ever queries
  /// membership of branch files, so the intersection is the whole state).
  final Set<String> coveredBranchFiles;

  /// Base's current blob per branch file at [scannedTo].
  final Map<String, String> currentBlobs;

  /// Tip-scoped report at [scannedTo] — still exact when base hasn't moved.
  final List<String> tipOutstanding;
  final bool tipConflicted;
}

final Map<String, _AbsorptionFrontier> _absorptionFrontiers = {};

/// Drop both permanence caches. Test-only.
@visibleForTesting
void resetAbsorptionCaches() {
  _absorbedVerdictCache.clear();
  _absorptionFrontiers.clear();
}

/// Cached once per app run: does the local git support
/// `git merge-tree --write-tree` (i.e. is it >= 2.38)? The absorption law is
/// unavailable on older gits, in which case callers fall back to legacy
/// squash detection.
bool? _mergeTreeWriteTreeSupported;

/// Reset the cached merge-tree support probe. Test-only — lets a test
/// exercise both the supported and the unsupported (fallback) paths.
@visibleForTesting
void resetMergeTreeAbsorptionSupportCache([bool? force]) {
  _mergeTreeWriteTreeSupported = force;
}

/// True when the local git is new enough (>= 2.38) to answer the absorption
/// law via `git merge-tree --write-tree`. Probed once via `git version` and
/// cached for the app's lifetime — the git binary does not change under us.
Future<bool> mergeTreeAbsorptionSupported(String repo) async {
  final cached = _mergeTreeWriteTreeSupported;
  if (cached != null) return cached;
  var supported = false;
  try {
    final r = await _git(repo, ['version']);
    if (r.exitCode == 0) {
      final m = RegExp(r'(\d+)\.(\d+)').firstMatch(r.stdout.toString());
      if (m != null) {
        final major = int.parse(m.group(1)!);
        final minor = int.parse(m.group(2)!);
        supported = major > 2 || (major == 2 && minor >= 38);
      }
    }
  } catch (_) {
    supported = false;
  }
  _mergeTreeWriteTreeSupported = supported;
  return supported;
}

/// One `git merge-tree --write-tree` trial: is merging [branch] into
/// [commit] a no-op? Exit status: 0 = clean merge, 1 = conflicts, anything
/// else = error. In BOTH the clean and conflicted cases the FIRST line of
/// stdout is the resulting toplevel tree OID; on a conflict that is followed
/// by conflicted-file records `<mode> <oid> <stage>\t<path>`, a blank line,
/// then human-readable informational messages (shape verified empirically).
///
/// Returns the raw pieces the callers need: the result tree ('' on error),
/// whether the trial conflicted, and the conflicted paths.
Future<({String resultTree, bool conflicted, List<String> conflictedFiles})>
_mergeTreeTrial(String repo, String commit, String branch) async {
  final r = await _git(repo, ['merge-tree', '--write-tree', commit, branch]);
  if (r.exitCode > 1) {
    return (
      resultTree: '',
      conflicted: false,
      conflictedFiles: const <String>[],
    );
  }
  final lines = r.stdout.toString().split('\n');
  final resultTree = lines.isNotEmpty ? lines.first.trim() : '';
  if (r.exitCode == 0) {
    return (
      resultTree: resultTree,
      conflicted: false,
      conflictedFiles: const <String>[],
    );
  }
  // Conflicted-file stage lines run up to the first blank line.
  final files = <String>{};
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty) break;
    final tab = line.indexOf('\t');
    if (tab >= 0) files.add(line.substring(tab + 1).trim());
  }
  return (
    resultTree: resultTree,
    conflicted: true,
    conflictedFiles: files.toList()..sort(),
  );
}

/// Pipe [patchText] through `git patch-id --stable` and return its stdout
/// (lines of `<patch-id> <commit-id>`). Empty input short-circuits to ''.
/// Runs under the shared git subprocess semaphore like every other spawn.
Future<String> _patchIdStable(String repo, String patchText) async {
  if (patchText.trim().isEmpty) return '';
  await _gitSubprocessSemaphore.acquire();
  try {
    final proc = await _spawnStart([
      'patch-id',
      '--stable',
    ], workingDirectory: repo);
    // Wire the readers BEFORE writing stdin so a large patch can't deadlock
    // on a full stdout pipe buffer.
    final outF = proc.stdout.transform(utf8.decoder).join();
    final errF = proc.stderr.drain<void>();
    proc.stdin.write(patchText);
    await proc.stdin.close();
    final out = await outF;
    await errF;
    await proc.exitCode;
    return out;
  } catch (_) {
    return '';
  } finally {
    _gitSubprocessSemaphore.release();
  }
}

/// Apply the (historical) absorption law to a single [branch] against
/// [base]. Returns null when git is too old (< 2.38) to answer, or on any
/// unexpected failure — the caller then falls back to legacy behaviour and
/// shows nothing new.
///
/// Proof search per the law comment above: permanence cache, incremental
/// frontier, tip instant-accept, the batched patch-id fast path (candidate
/// confirmed by tree algebra — the final claim is never patch-id alone),
/// then the pruned fork-forward linear scan, uncapped: the verdict is
/// always a proven yes or a proven no.
///
/// Note: the coordinator's spec suggested synthesizing the branch's
/// cumulative change via `git commit-tree`; unnecessary — `git diff
/// <fork> <branch>` IS the cumulative patch, and patch-id hashes the patch
/// text, not the commit object.
Future<BranchAbsorption?> branchAbsorption(
  String repo,
  String branch,
  String base,
) async {
  try {
    // Resolve both tips in one spawn — they key the permanence caches.
    final tipR = await _git(repo, [
      'rev-parse',
      '$branch^{commit}',
      '$base^{commit}',
      '$base^{tree}',
    ]);
    if (tipR.exitCode != 0) return null;
    final tipLines = tipR.stdout
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (tipLines.length < 3) return null;
    final branchTip = tipLines[0];
    final baseTip = tipLines[1];
    final baseTree = tipLines[2];
    final key = _absorptionKey(repo, branchTip, base);

    // ---- 0a. PERMANENCE CACHE: a witnessed verdict for this branch tip is
    // final — delivery cannot be revoked. Checked before even the support
    // gate: a cached proof needs no git at all.
    final cachedYes = _absorbedVerdictCache[key];
    if (cachedYes != null) return cachedYes;

    // ---- 0b. INCREMENTAL FRONTIER: a proven-no verdict examined base up
    // to some tip. If base hasn't moved since, nothing can have changed —
    // same proven no, zero further spawns. (Same branch tip + same base tip
    // ⟹ same fork, so no separate fork check is needed on this path.)
    final frontier = _absorptionFrontiers[key];
    if (frontier != null && frontier.scannedTo == baseTip) {
      return (
        absorbed: false,
        witness: null,
        via: null,
        outstandingFiles: frontier.tipOutstanding,
        conflicted: frontier.tipConflicted,
      );
    }

    if (!await mergeTreeAbsorptionSupported(repo)) return null;

    // Every witness found below is permanent for this key: record + return.
    BranchAbsorption witnessed(
      String witness,
      AbsorptionWitnessVia via, {
      required List<String> tipOutstanding,
      required bool tipConflicted,
    }) {
      final v = (
        absorbed: true,
        witness: witness,
        via: via,
        outstandingFiles: tipOutstanding,
        conflicted: tipConflicted,
      );
      _absorbedVerdictCache[key] = v;
      _absorptionFrontiers.remove(key);
      return v;
    }

    // ---- 1. TIP: the cheapest witness needs no walk. Also the only place
    // outstandingFiles/conflicted mean anything ("what would merging NOW do").
    final tip = await _mergeTreeTrial(repo, baseTip, branch);
    if (tip.resultTree.isEmpty) return null;
    if (!tip.conflicted && tip.resultTree == baseTree) {
      return witnessed(
        baseTip,
        AbsorptionWitnessVia.tip,
        tipOutstanding: const [],
        tipConflicted: false,
      );
    }
    // Tip-scoped report for the not-(tip-)absorbed shapes, reused by every
    // return below — the historical scan never changes what merging NOW does.
    final List<String> tipOutstanding;
    if (tip.conflicted) {
      tipOutstanding = tip.conflictedFiles;
    } else {
      final diff = await _git(repo, [
        'diff-tree',
        '--name-only',
        '-r',
        baseTree,
        tip.resultTree,
      ]);
      tipOutstanding = diff.stdout
          .toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    }

    // The historical search needs a fork point; without one (unrelated
    // histories) tip was the whole story.
    final forkR = await _git(repo, ['merge-base', base, branch]);
    final fork = forkR.stdout.toString().trim();
    if (forkR.exitCode != 0 || fork.isEmpty) {
      return (
        absorbed: false,
        witness: null,
        via: null,
        outstandingFiles: tipOutstanding,
        conflicted: tip.conflicted,
      );
    }

    // A proven-no re-probe continues from its frontier instead of the fork
    // — but only when the recorded fork still holds (a mismatch means base
    // history was rewritten: full rescan; correctness beats cleverness).
    final resume = (frontier != null && frontier.fork == fork)
        ? frontier
        : null;
    final scanFrom = resume?.scannedTo ?? fork;

    // Branch's changed files WITH their target blob OIDs, computed once via
    // `diff-tree --raw` (`--no-renames` pins the plumbing output shape:
    // `:mode mode oldOid newOid S\tpath`; a deletion's newOid is all-zeros,
    // which is exactly the "base must delete it too" target). Empty means
    // the branch tree equals fork's tree — tip already told the whole story.
    final bfR = await _git(repo, [
      'diff-tree',
      '-r',
      '--raw',
      '--no-abbrev',
      '--no-renames',
      fork,
      branch,
    ]);
    final branchBlobs = _parseRawDiffBlobs(bfR.stdout.toString());
    final branchFiles = branchBlobs.keys.toSet();

    // Every proven-no below records the frontier for the next probe, then
    // returns. State passed in is the scan state AT baseTip.
    BranchAbsorption provenNo(
      Set<String> coveredBranchFiles,
      Map<String, String> currentBlobs,
    ) {
      _absorptionFrontiers[key] = _AbsorptionFrontier(
        fork: fork,
        scannedTo: baseTip,
        coveredBranchFiles: coveredBranchFiles,
        currentBlobs: currentBlobs,
        tipOutstanding: tipOutstanding,
        tipConflicted: tip.conflicted,
      );
      return (
        absorbed: false,
        witness: null,
        via: null,
        outstandingFiles: tipOutstanding,
        conflicted: tip.conflicted,
      );
    }

    if (branchFiles.isEmpty) return provenNo(const {}, const {});

    // ONE walk of base's first-parent line, resuming at the frontier when
    // valid, else from the fork: commit hash, its tree, and the raw records
    // of what it changed vs its first parent (`--first-parent` implies
    // first-parent diffs for merges — verified empirically). Both proof
    // paths below read from this single parse. UNCAPPED — the range is
    // finite and the verdict must be proven either way.
    final walkR = await _git(repo, [
      'log',
      '--first-parent',
      '--reverse',
      '--format=commit:%H %T',
      '--raw',
      '--no-abbrev',
      '--no-renames',
      '$scanFrom..$base',
    ]);
    if (walkR.exitCode != 0) {
      // Transient failure — no verdict, no frontier update (never record
      // "scanned to here" for ground we didn't actually walk).
      return (
        absorbed: false,
        witness: null,
        via: null,
        outstandingFiles: tipOutstanding,
        conflicted: tip.conflicted,
      );
    }
    final entries = <({String hash, String tree, Map<String, String> blobs})>[];
    {
      String? hash;
      String? tree;
      var blobs = <String, String>{};
      void close() {
        final h = hash;
        final t = tree;
        if (h != null && t != null) {
          entries.add((hash: h, tree: t, blobs: blobs));
        }
      }

      for (final raw in walkR.stdout.toString().split('\n')) {
        final line = raw.trimRight();
        if (line.trim().isEmpty) continue;
        if (line.startsWith('commit:')) {
          close();
          final body = line.substring('commit:'.length).trim();
          final sp = body.indexOf(' ');
          hash = sp > 0 ? body.substring(0, sp) : body;
          tree = sp > 0 ? body.substring(sp + 1).trim() : null;
          blobs = <String, String>{};
        } else if (line.startsWith(':')) {
          final rec = _parseRawDiffLine(line);
          if (rec != null) blobs[rec.path] = rec.newBlob;
        }
      }
      close();
    }

    // Theorem-grade confirmation shared by both proof paths: a candidate
    // only ever becomes a witness through the tree algebra.
    Future<bool> confirms(String candidate, String candidateTree) async {
      final trial = await _mergeTreeTrial(repo, candidate, branch);
      return !trial.conflicted &&
          trial.resultTree.isNotEmpty &&
          trial.resultTree == candidateTree;
    }

    // ---- 2. PATCH-ID fast path. A commit whose patch equals the branch's
    // cumulative patch necessarily touched EXACTLY the branch's file set —
    // so only those few commits get piped through `-p`, never the whole
    // range (the unpruned `log -p` pipeline cost seconds per branch,
    // measured). The set-equality is a pre-filter on a pre-filter: a true
    // candidate it would miss (rename/mode oddities) simply falls through
    // to the scan. Full-range on purpose — patch-id reaches witnesses
    // beyond the scan window at negligible cost.
    final patchCandidates = [
      for (final e in entries)
        if (e.blobs.length == branchFiles.length &&
            e.blobs.keys.every(branchFiles.contains))
          e,
    ];
    // The branch's cumulative patch, fetched at most once and shared by the
    // patch-id fast path and the scan's added-line reject filter.
    String? branchDiffText;
    Future<String> branchDiff() async {
      return branchDiffText ??= (await _git(repo, [
        ..._kDiffCmd,
        ..._kDiffContentPins,
        '--no-renames',
        fork,
        branch,
      ])).stdout.toString();
    }

    if (patchCandidates.isNotEmpty) {
      final branchIdOut = await _patchIdStable(repo, await branchDiff());
      final branchIdParts = branchIdOut.trim().split(RegExp(r'\s+'));
      final branchPatchId = branchIdParts.isEmpty ? '' : branchIdParts.first;
      if (branchPatchId.isNotEmpty) {
        final logP = await _git(repo, [
          'log',
          '--no-walk',
          '-p',
          '--format=commit %H',
          for (final e in patchCandidates) e.hash,
        ]);
        if (logP.exitCode == 0) {
          final ids = await _patchIdStable(repo, logP.stdout.toString());
          for (final line in ids.split('\n')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length < 2 || parts[0] != branchPatchId) continue;
            final hit = patchCandidates.where((e) => e.hash == parts[1]);
            if (hit.isEmpty) continue;
            final e = hit.first;
            if (await confirms(e.hash, e.tree)) {
              return witnessed(
                e.hash,
                AbsorptionWitnessVia.patchId,
                tipOutstanding: tipOutstanding,
                tipConflicted: tip.conflicted,
              );
            }
          }
        }
      }
    }

    // ---- 3. LINEAR SCAN, fork-forward, uncapped. Pruned by an EXACT
    // observation, not a heuristic: merge-tree(c, b)'s no-op status depends
    // only on c's versions of the files the branch changed (the 3-way only
    // resolves paths where the branch differs from the fork), and those
    // versions change only at commits whose first-parent diff touches a
    // branch file. So by induction from the fork, the EARLIEST witness must
    // (i) have coverage — base's cumulative history has touched every
    // branch file (all content delivered) — and (ii) itself touch a branch
    // file. Only such commits are candidates. (Caveat, documented not
    // patched: base-side renames of branch files could in theory move
    // content without "touching" the original path; the tip check still
    // covers the living case.)
    //
    // Candidates are then tested in two tiers, cheapest sufficient evidence
    // first:
    //   BLOB-EXACT — c's blob of every branch file equals the branch's own
    //     blob (deletions match the all-zeros target). Then the 3-way at
    //     each branch path trivially resolves to c's version, so c is a
    //     near-certain witness; decided IN MEMORY from the walk's raw
    //     records, confirmed with one real merge-tree. Every literal
    //     transplant/squash lands here — ~1 spawn.
    //   MERGE-TREE — remaining candidates (possible hunk-subset witnesses:
    //     base absorbed the branch's edits INTO further edits of the same
    //     files, e.g. move-changes onto a moved main) each need the real
    //     trial. These are the expensive tail (~150-500ms each, rename
    //     detection dominates — measured), so they run CONCURRENTLY through
    //     the global git semaphore; the earliest confirmed index wins so
    //     the receipt is deterministic.
    // Scan state, seeded from the frontier on a resumed walk. `covered`
    // holds only branch files (the coverage test never asks about others).
    final covered = <String>{...?resume?.coveredBranchFiles};
    // Current blob of each branch file as base history advances; a path
    // absent means base still has fork's version (which cannot equal the
    // branch's target — the branch changed it, so equality needs an
    // explicit touch).
    final current = <String, String>{...?resume?.currentBlobs};
    // Tier 2, in walk order. Each carries a snapshot of the branch files'
    // blobs at that commit for the added-line reject filter below, plus the
    // overlap size for most-likely-first ordering.
    final mergeTreeCandidates =
        <({String hash, String tree, Map<String, String> snap, int overlap})>[];
    for (final e in entries) {
      var overlap = 0;
      for (final rec in e.blobs.entries) {
        if (branchFiles.contains(rec.key)) {
          overlap++;
          covered.add(rec.key);
          current[rec.key] = rec.value;
        }
      }
      if (overlap == 0 || !covered.containsAll(branchFiles)) continue;
      final blobExact = branchFiles.every(
        (f) => current[f] != null && current[f] == branchBlobs[f],
      );
      if (blobExact) {
        // Near-certain witness (every branch path resolves trivially to
        // c's own version); confirm through the algebra and take it as the
        // exhibit. Earliest-witness preference is a receipt nicety, not
        // law — any confirmed commit is a true witness.
        if (await confirms(e.hash, e.tree)) {
          return witnessed(
            e.hash,
            AbsorptionWitnessVia.scan,
            tipOutstanding: tipOutstanding,
            tipConflicted: tip.conflicted,
          );
        }
      } else {
        mergeTreeCandidates.add((
          hash: e.hash,
          tree: e.tree,
          snap: {for (final f in branchFiles) f: current[f]!},
          overlap: overlap,
        ));
      }
    }

    // Tier 2: possible hunk-subset witnesses (base absorbed the branch's
    // edits INTO further edits of the same files). Each real merge-tree
    // trial costs ~150-500ms (rename detection dominates — measured), so
    // first apply the exact added-line NECESSARY condition (see
    // [_diffAddedLinesByFile]) with the blob contents fetched in ONE
    // `cat-file --batch` spawn — on hot files this rejects nearly every
    // candidate in memory. Survivors get real trials, run CONCURRENTLY
    // through the global git semaphore.
    if (mergeTreeCandidates.isNotEmpty) {
      final addedByFile = _diffAddedLinesByFile(await branchDiff());
      var survivors = mergeTreeCandidates;
      if (addedByFile.isNotEmpty) {
        final needed = <String>{
          for (final c in mergeTreeCandidates)
            for (final f in addedByFile.keys)
              if (c.snap[f] != null && !_kAllZerosOid.hasMatch(c.snap[f]!))
                c.snap[f]!,
        };
        final contents = await _catFileBatch(repo, needed);
        bool passes(
          ({String hash, String tree, Map<String, String> snap, int overlap}) c,
        ) {
          for (final entry in addedByFile.entries) {
            final blob = c.snap[entry.key];
            if (blob == null || _kAllZerosOid.hasMatch(blob)) {
              // Branch adds lines to a file this commit's base has deleted
              // — a merge could never be a no-op here.
              return false;
            }
            final content = contents[blob];
            if (content == null) continue; // fetch hiccup: never reject blind
            final lines = <String>{
              for (var l in content.split('\n'))
                l.endsWith('\r') ? l.substring(0, l.length - 1) : l,
            };
            if (!entry.value.every(lines.contains)) return false;
          }
          return true;
        }

        survivors = [
          for (final c in mergeTreeCandidates)
            if (passes(c)) c,
        ];
      }
      if (survivors.isNotEmpty) {
        // Most-likely witnesses first: a squash/transplant witness touches
        // the branch's WHOLE file set, so larger touched-file overlap fires
        // the early-exit sooner on real absorptions. Ties keep walk order
        // (sort is only applied when it can help; List.sort is unstable, so
        // decorate with the original index to keep determinism).
        final indexed = [
          for (var i = 0; i < survivors.length; i++) (i: i, c: survivors[i]),
        ];
        indexed.sort((a, b) {
          final d = b.c.overlap - a.c.overlap;
          return d != 0 ? d : a.i - b.i;
        });
        final ordered = [for (final x in indexed) x.c];
        final confirmed = List<bool>.filled(ordered.length, false);
        var next = 0;
        var anyHit = false;
        final workers = math.min(squashProbeMaxConcurrency, ordered.length);
        await Future.wait(
          List.generate(
            workers,
            (_) => Future(() async {
              while (true) {
                final i = next++;
                if (i >= ordered.length) return;
                // Early exit: the law is existential — once any witness is
                // confirmed, stop claiming new work.
                if (anyHit) return;
                final c = ordered[i];
                if (await confirms(c.hash, c.tree)) {
                  confirmed[i] = true;
                  anyHit = true;
                }
              }
            }),
          ),
        );
        final hit = confirmed.indexOf(true);
        if (hit >= 0) {
          return witnessed(
            ordered[hit].hash,
            AbsorptionWitnessVia.scan,
            tipOutstanding: tipOutstanding,
            tipConflicted: tip.conflicted,
          );
        }
      }
    }

    // Proven no — the entire fork..baseTip line has been examined (this
    // probe plus any frontier it resumed from). Record the frontier so the
    // next probe only walks base commits newer than today's tip.
    return provenNo({
      for (final f in covered)
        if (branchFiles.contains(f)) f,
    }, Map.of(current));
  } catch (_) {
    return null;
  }
}

/// Fetch many blobs in ONE `git cat-file --batch` spawn. Returns OID →
/// content (leniently decoded — the filter that consumes this only does
/// line-set membership, where U+FFFD replacement is harmless). Missing or
/// non-blob OIDs are simply absent from the map. Byte-exact parsing: the
/// batch protocol frames each object as `<oid> blob <size>\n<size bytes>\n`,
/// and <size> counts BYTES, so the walk happens over raw bytes, never over
/// a decoded string.
Future<Map<String, String>> _catFileBatch(
  String repo,
  Iterable<String> oids,
) async {
  final wanted = oids.toSet();
  if (wanted.isEmpty) return const {};
  await _gitSubprocessSemaphore.acquire();
  try {
    final proc = await _spawnStart([
      'cat-file',
      '--batch',
    ], workingDirectory: repo);
    final buf = BytesBuilder(copy: false);
    final outDone = proc.stdout.listen(buf.add).asFuture<void>();
    final errF = proc.stderr.drain<void>();
    proc.stdin.write(wanted.map((o) => '$o\n').join());
    await proc.stdin.close();
    await outDone;
    await errF;
    await proc.exitCode;
    final bytes = buf.takeBytes();
    final result = <String, String>{};
    var pos = 0;
    while (pos < bytes.length) {
      final nl = bytes.indexOf(0x0A, pos);
      if (nl < 0) break;
      final header = ascii.decode(bytes.sublist(pos, nl), allowInvalid: true);
      pos = nl + 1;
      final parts = header.trim().split(RegExp(r'\s+'));
      if (parts.length >= 3 && parts[1] == 'blob') {
        final size = int.tryParse(parts[2]) ?? 0;
        final end = math.min(pos + size, bytes.length);
        result[parts[0]] = const Utf8Decoder(
          allowMalformed: true,
        ).convert(bytes.sublist(pos, end));
        pos = end + 1; // skip the trailing framing '\n'
      }
      // `<oid> missing` (or anything else) has no body; loop continues at
      // the next header.
    }
    return result;
  } catch (_) {
    return const {};
  } finally {
    _gitSubprocessSemaphore.release();
  }
}

/// Per-file ADDED lines of a unified diff (lines starting `+`, excluding
/// the `+++` header), CR-normalized. The absorption scan uses these as an
/// exact NECESSARY condition: if merging branch b into commit c is a no-op
/// (result == c's tree), every line b added must appear verbatim in c's
/// version of that file — theirs' insertions either already exist in ours
/// (so they're in c.f) or the region conflicts / changes the result,
/// contradicting no-op. Files whose diff section can't be attributed to a
/// path are skipped (the filter only ever REJECTS with certainty).
Map<String, Set<String>> _diffAddedLinesByFile(String diffText) {
  final out = <String, Set<String>>{};
  String? file;
  for (final raw in diffText.split('\n')) {
    final header = diffHeaderPath(raw);
    if (header != null) {
      file = header;
      continue;
    }
    if (file == null) continue;
    if (raw.startsWith('+++') || raw.startsWith('---')) continue;
    if (raw.startsWith('+')) {
      var line = raw.substring(1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      (out[file] ??= <String>{}).add(line);
    }
  }
  return out;
}

final RegExp _kAllZerosOid = RegExp(r'^0+$');

/// One record of `diff-tree --raw --no-abbrev --no-renames` plumbing output:
/// `:oldMode newMode oldOid newOid S\tpath`. Returns the path and its NEW
/// blob OID (all-zeros for a deletion — the caller treats that as the
/// "must be deleted" target, which is exactly right for blob matching).
({String path, String newBlob})? _parseRawDiffLine(String line) {
  final tab = line.indexOf('\t');
  if (!line.startsWith(':') || tab < 0) return null;
  final meta = line.substring(1, tab).trim().split(RegExp(r'\s+'));
  if (meta.length < 5) return null;
  return (path: line.substring(tab + 1).trim(), newBlob: meta[3]);
}

/// Parse a whole `--raw` diff body into path → new blob OID.
Map<String, String> _parseRawDiffBlobs(String out) {
  final blobs = <String, String>{};
  for (final line in out.split('\n')) {
    final rec = _parseRawDiffLine(line.trimRight());
    if (rec != null) blobs[rec.path] = rec.newBlob;
  }
  return blobs;
}

/// Batch pass folding absorption + squash detection into ONE probe cycle for
/// the branches lens. When the local git supports the absorption law it
/// STRICTLY SUPERSEDES the legacy tree-equality squash check, so we run
/// [branchAbsorption] per branch and populate [BranchInfo.absorbed]. On older
/// gits (< 2.38) we transparently fall back to [detectSquashMergedBranches],
/// populating [BranchInfo.squashMerged] instead — so callers get one call and
/// a fully-classified list either way.
///
/// Probes skip: the current branch, the base branch itself, branches already
/// known gone (their corpse story is already told), and leased branches whose
/// tip already equals base (merging is trivially a no-op — no probe needed).
///
/// Uses the same order-preserving index-stream worker pool as
/// [detectSquashMergedBranches], capped at [squashProbeMaxConcurrency].
Future<List<BranchInfo>> detectAbsorbedBranches(
  String repo,
  List<BranchInfo> branches, {
  required String baseRef,
  Set<String> leasedNames = const {},
}) async {
  final supported = await mergeTreeAbsorptionSupported(repo);
  if (!supported) {
    // Legacy fallback path (git < 2.38): tree-equal squash via `git cherry`.
    return detectSquashMergedBranches(repo, branches, baseRef: baseRef);
  }

  // Resolve base tip once so leased branches sitting exactly on base can be
  // skipped without a probe.
  final baseTip = (await _git(repo, [
    'rev-parse',
    '$baseRef^{commit}',
  ])).stdout.toString().trim();

  Future<({bool absorbed, String? witness})?> probe(BranchInfo b) async {
    if (b.current) return null;
    if (b.name == baseRef) return null;
    if (b.gone) return null; // already a known corpse; whisper is 'gone'
    if (leasedNames.contains(b.name) && baseTip.isNotEmpty) {
      final tip = (await _git(repo, [
        'rev-parse',
        '${b.name}^{commit}',
      ])).stdout.toString().trim();
      if (tip == baseTip) return null; // trivial no-op; keep leased material
    }
    final r = await branchAbsorption(repo, b.name, baseRef);
    if (r == null) return null;
    // The absorbed flag is only ever true on a tree-algebra witness.
    return (absorbed: r.absorbed, witness: r.witness);
  }

  final flags = List<({bool absorbed, String? witness})?>.filled(
    branches.length,
    null,
  );
  var next = 0;
  final workers = math.min(squashProbeMaxConcurrency, branches.length);
  await Future.wait(
    List.generate(
      workers,
      (_) => Future(() async {
        while (true) {
          final i = next++;
          if (i >= branches.length) return;
          flags[i] = await probe(branches[i]);
        }
      }),
    ),
  );
  return [
    for (var i = 0; i < branches.length; i++)
      branches[i].copyWith(
        absorbed: flags[i]?.absorbed,
        absorbedWitness: flags[i]?.witness,
      ),
  ];
}

Future<GitResult<void>> createBranch(
  String repo,
  String name, {
  String? from,
}) async {
  final args = from != null
      ? ['checkout', '-b', name, from]
      : ['checkout', '-b', name];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> checkoutBranch(String repo, String name) async {
  final r = await _git(repo, ['checkout', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> deleteBranch(
  String repo,
  String name, {
  bool force = false,
}) async {
  final r = await _git(repo, ['branch', force ? '-D' : '-d', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// The exact author identity the NEXT commit in [repo] would stamp.
/// Resolved by git itself via `git var GIT_AUTHOR_IDENT` — env overrides,
/// local config, includeIf, global, in git's own precedence order — so the
/// UI can never disagree with what a commit would actually record. Forge-
/// agnostic by construction: authoring identity is pure git, identical
/// across GitHub/GitLab/Gitea/anything. Null when git cannot synthesize
/// an identity at all (nothing configured), which IS the warning state.
Future<({String name, String email})?> getCommitIdentity(String repo) async {
  final r = await _git(repo, ['var', 'GIT_AUTHOR_IDENT']);
  if (r.exitCode != 0) return null;
  // "Name <email> 1783178174 -0400"
  final m = RegExp(
    r'^(.*) <([^>]*)> \d+ [+-]\d{4}$',
  ).firstMatch(r.stdout.toString().trim());
  if (m == null) return null;
  return (name: m.group(1)!.trim(), email: m.group(2)!.trim());
}

/// How the configured commit identity relates to THIS repo's own history —
/// the one oracle a git client honestly has. Email is the strong key
/// (names collide freely); a repo with no history grades everyone
/// [resident] because there is nothing to compare against and a fresh
/// `git init` first commit deserves no scolding.
enum IdentityFamiliarity {
  /// Probes still resolving — render nothing judgmental.
  unknown,

  /// This email has authored commits here before. Calm minimum.
  resident,

  /// Not in THIS repo's history, but an author in other repos of the
  /// user's workspace — the first-commit-in-a-new-project shape. A
  /// greeting, never a warning: without this tier, cloning any project
  /// you've never contributed to would caution-flag your own identity.
  knownElsewhere,

  /// Known author NAME (here or anywhere in the workspace), never-seen
  /// email: new machine, fresh noreply, or a typo'd config. Worth an
  /// eyebrow, not an alarm.
  newEmail,

  /// Unseen across the ENTIRE workspace — the planted-config incident
  /// shape, and a much stronger claim than "new to one repo". Quiet,
  /// unmistakable caution.
  stranger,
}

/// Author sets from the repo's recent history (bounded walk), the raw
/// material for [gradeIdentity]. Lowercased for comparison.
Future<({Set<String> emails, Set<String> names})> getHistoricalAuthors(
  String repo, {
  int limit = 2000,
}) async {
  final r = await _git(repo, ['log', '--format=%aN%x09%aE', '-n', '$limit']);
  final emails = <String>{};
  final names = <String>{};
  if (r.exitCode == 0) {
    for (final line in r.stdout.toString().split('\n')) {
      final tab = line.indexOf('\t');
      if (tab <= 0) continue;
      names.add(line.substring(0, tab).trim().toLowerCase());
      emails.add(line.substring(tab + 1).trim().toLowerCase());
    }
  }
  return (emails: emails, names: names);
}

/// Pure grading of a configured identity: [local] is this repo's author
/// history, [workspace] the union across the user's other open repos
/// (pass empty sets when unavailable — grading degrades to local-only).
IdentityFamiliarity gradeIdentity(
  ({String name, String email}) identity,
  ({Set<String> emails, Set<String> names}) local, {
  ({Set<String> emails, Set<String> names}) workspace = const (
    emails: <String>{},
    names: <String>{},
  ),
}) {
  final email = identity.email.toLowerCase();
  final name = identity.name.toLowerCase();
  if (local.emails.isEmpty) return IdentityFamiliarity.resident;
  if (local.emails.contains(email)) return IdentityFamiliarity.resident;
  if (workspace.emails.contains(email)) {
    return IdentityFamiliarity.knownElsewhere;
  }
  if (local.names.contains(name) || workspace.names.contains(name)) {
    return IdentityFamiliarity.newEmail;
  }
  return IdentityFamiliarity.stranger;
}

/// Current OID of [ref] (full ref name, e.g. `refs/heads/foo`), or null
/// when it doesn't resolve. The identity-capture half of the delayed-
/// destruction contract: UI flows that arm a safety window snapshot the
/// tip NOW so the delete can verify it later.
Future<String?> refTip(String repo, String ref) async {
  final r = await _git(repo, ['rev-parse', '--verify', '--quiet', ref]);
  if (r.exitCode != 0) return null;
  final s = r.stdout.toString().trim();
  return s.isEmpty ? null : s;
}

/// Identity-pinned branch delete for safety-window delays: a branch NAME
/// is a mutable pointer, and in the seconds between arming and firing it
/// can be deleted, recreated, or retargeted — `git branch -d name` would
/// then destroy a ref the user never saw. Verifies the tip still equals
/// [expectTip] at fire time; a moved tip refuses, an already-gone ref is
/// success (the user's intent — name absent — already holds). The safe
/// (non-force) path keeps `git branch -d`'s merged-check, re-evaluated at
/// fire time where it belongs.
Future<GitResult<void>> deleteBranchIfAt(
  String repo,
  String name,
  String expectTip, {
  bool force = false,
}) async {
  final tip = await refTip(repo, 'refs/heads/$name');
  if (tip == null) return const GitResult.ok(null);
  if (tip != expectTip) {
    return GitResult.err(
      "'$name' moved since the delete was armed; nothing was deleted.",
    );
  }
  return deleteBranch(repo, name, force: force);
}

/// Identity-pinned tag delete — same delayed-destruction contract as
/// [deleteBranchIfAt]. [expectTip] is whatever `refs/tags/<name>` resolved
/// to at arm time (the tag object for annotated tags, the commit for
/// lightweight ones — compared like-for-like against the same probe).
Future<GitResult<void>> deleteTagIfAt(
  String repo,
  String name,
  String expectTip,
) async {
  final tip = await refTip(repo, 'refs/tags/$name');
  if (tip == null) return const GitResult.ok(null);
  if (tip != expectTip) {
    return GitResult.err(
      "'$name' moved since the delete was armed; nothing was deleted.",
    );
  }
  return deleteTag(repo, name);
}

/// Rename a local branch. `-M` to force-replace if [newName] already
/// exists (git rejects otherwise). Returns the git stderr on failure
/// so callers can surface the actual reason (ref collision, dirty
/// working tree, etc.).
Future<GitResult<void>> renameBranch(
  String repo,
  String oldName,
  String newName, {
  bool force = false,
}) async {
  final r = await _git(repo, ['branch', force ? '-M' : '-m', oldName, newName]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Cherry-pick a commit onto the current HEAD. Non-fast-forward; git
/// leaves conflicts in the working tree on failure — caller should
/// surface the stderr to the user so they can resolve or abort.
Future<GitResult<void>> cherryPickCommit(String repo, String hash) async {
  final r = await _git(repo, ['cherry-pick', hash]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Revert a commit — creates a new commit that undoes [hash] against
/// current HEAD. `--no-edit` skips the commit-message editor; the
/// default "Revert '<subject>'" message is fine for UI-driven reverts.
Future<GitResult<void>> revertCommit(String repo, String hash) async {
  final r = await _git(repo, ['revert', '--no-edit', hash]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Switch to [name] carrying local modifications via a 3-way merge — the
/// dirty-tolerant form of checkout (`git checkout -m`). git refuses a plain
/// switch when an edit would be overwritten; `-m` instead merges the local
/// edits into the target, leaving standard conflict markers in the working
/// tree on overlap (no commit). The unified flow routes those markers into
/// the same editor every other conflict path uses.
Future<GitResult<void>> checkoutMerge(String repo, String name) async {
  final r = await _git(repo, ['checkout', '-m', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Concludes a paused cherry-pick after the editor staged the resolution.
/// Uses `git commit --no-edit` rather than `cherry-pick --continue -c
/// core.editor=true`: for a SINGLE pick the commit (with `CHERRY_PICK_HEAD`
/// set) finishes it with the carried message and clears the sequencer state,
/// and `--no-edit` never invokes an editor at all — so it's portable on
/// Windows installs where `true` isn't on PATH (the case `core.editor=true`
/// would hang or error on). Verified equivalent for the single-pick path.
Future<GitResult<void>> continueCherryPick(String repo) async {
  final r = await _git(repo, ['commit', '--no-edit']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Concludes a paused revert after the editor staged the resolution.
/// `git commit --no-edit` finishes a single revert (with `REVERT_HEAD` set)
/// using the carried message and invokes no editor — portable, unlike
/// `revert --continue -c core.editor=true`.
Future<GitResult<void>> continueRevert(String repo) async {
  final r = await _git(repo, ['commit', '--no-edit']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// The primary remote's name. `origin` is the convention and wins when
/// present; otherwise we take the first remote `git remote` lists
/// (single-remote repos with non-conventional names — e.g. `upstream`
/// after a fork — are common enough to need this). Returns null only
/// when the repo has no remotes at all (fresh local-only repo).
/// Cached at the call site, not here — callers in tight loops should
/// resolve once and pass the result through, since this spawns a
/// subprocess.
Future<GitResult<String?>> primaryRemoteName(String repo) async {
  final r = await _git(repo, ['remote']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final names = <String>[
    for (final line in r.stdout.toString().split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (names.isEmpty) return const GitResult.ok(null);
  if (names.contains('origin')) return const GitResult.ok('origin');
  return GitResult.ok(names.first);
}

/// The repo's default branch name — what `git symbolic-ref
/// refs/remotes/<primary>/HEAD` points to, with a fallback scan for
/// `main` or `master` when no remote HEAD is set. Returns null when
/// the repo has no recognizable default (new repo, detached, nothing
/// configured). The History page uses this to compute trunk-vs-branch
/// lane assignment on the top timeline.
Future<GitResult<String?>> defaultBranchName(String repo) async {
  final remoteRes = await primaryRemoteName(repo);
  final remote = remoteRes.ok ? (remoteRes.data ?? 'origin') : 'origin';
  final viaRemote = await _git(repo, [
    'symbolic-ref',
    '--short',
    'refs/remotes/$remote/HEAD',
  ]);
  if (viaRemote.exitCode == 0) {
    final raw = viaRemote.stdout.toString().trim();
    // Output form: "<remote>/main" — strip the remote prefix.
    final slash = raw.indexOf('/');
    if (slash > 0 && slash + 1 < raw.length) {
      return GitResult.ok(raw.substring(slash + 1));
    }
  }
  // Fallback: probe local + remote for conventional names. `main` wins
  // when both exist (modern convention); `master` used as legacy
  // fallback. `verify` avoids spawning a full `for-each-ref` walk.
  for (final candidate in const ['main', 'master']) {
    final check = await _git(repo, [
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/heads/$candidate',
    ]);
    if (check.exitCode == 0) return GitResult.ok(candidate);
    final remoteRef = await _git(repo, [
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/remotes/$remote/$candidate',
    ]);
    if (remoteRef.exitCode == 0) return GitResult.ok(candidate);
  }
  return const GitResult.ok(null);
}

/// Hashes reachable from [ref], capped at [limit]. Returned as a Set
/// for O(1) membership checks in UI rendering paths. Caller matches
/// the [limit] against whatever history depth the surface is showing;
/// passing a smaller limit than the surface renders means some of the
/// on-screen commits will look "off-trunk" even when they're actually
/// deeper ancestors — so size the limit to the surface, not a default.
Future<GitResult<Set<String>>> ancestorHashes(
  String repo,
  String ref, {
  required int limit,
}) async {
  final r = await _git(repo, ['rev-list', '-n', '$limit', ref]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final hashes = <String>{
    for (final line in r.stdout.toString().split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  };
  return GitResult.ok(hashes);
}

Future<GitResult<List<TagEntryData>>> listTags(String repo) async {
  // `%(*objectname)` is the DEREFERENCED target — populated only for
  // annotated tags (which wrap a tag object around the commit). A
  // lightweight tag is a bare ref straight at the commit, so its
  // `*objectname` is empty; the commit hash lives in `%(objectname)`.
  // Emit both and prefer the deref, falling back to the own name, so
  // every tag surfaces a short hash regardless of type.
  final r = await _git(repo, [
    'tag',
    '-l',
    '--format=%(refname:short)%09%(objecttype)%09%(*objectname)%09%(objectname)%09%(creatordate:iso)%09%(taggername)%09%(subject)',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  String? field(List<String> parts, int i) =>
      parts.length > i && parts[i].trim().isNotEmpty ? parts[i].trim() : null;

  final tags = <TagEntryData>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    final hashFull = field(parts, 2) ?? field(parts, 3);
    tags.add(
      TagEntryData(
        name: parts[0].trim(),
        tagType: parts.length > 1 ? parts[1].trim() : 'lightweight',
        targetHash: hashFull != null && hashFull.length > 8
            ? hashFull.substring(0, 8)
            : hashFull,
        createdAt: field(parts, 4),
        creatorName: field(parts, 5),
        subject: field(parts, 6),
      ),
    );
  }
  return GitResult.ok(tags);
}

Future<GitResult<void>> createTag(
  String repo,
  String name,
  String targetRef, {
  String? message,
}) async {
  final args = message != null
      ? ['tag', '-a', '-m', message, name, targetRef]
      : ['tag', name, targetRef];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> deleteTag(String repo, String name) async {
  final r = await _git(repo, ['tag', '-d', name]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<List<ReflogEntryData>>> listReflog(
  String repo, {
  int limit = 100,
}) async {
  // %x09 (a literal tab), NOT %09: git's commit/reflog pretty-format has no
  // `%09` escape — it emits the 3 chars `%09` verbatim, leaving every line
  // tab-less so `split('\t')` yields <6 parts and the whole reflog is dropped.
  final r = await _git(repo, [
    'reflog',
    '--format=%H%x09%h%x09%gd%x09%gs%x09%aN%x09%aI',
    '-n',
    '$limit',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final entries = <ReflogEntryData>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 6) continue;
    entries.add(
      ReflogEntryData(
        commitHash: parts[0].trim(),
        shortHash: parts[1].trim(),
        refSelector: parts[2].trim(),
        actionSummary: parts[3].trim(),
        authorName: parts[4].trim(),
        authoredAt: parts[5].trim(),
      ),
    );
  }
  return GitResult.ok(entries);
}

Future<GitResult<List<BlameLineData>>> getFileBlame(
  String repo,
  String path, {
  String? commitRef,
}) async {
  final args = [
    'blame',
    '--porcelain',
    if (commitRef != null) commitRef,
    '--',
    path,
  ];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final lines = <BlameLineData>[];
  final commitData = <String, Map<String, String>>{};
  String currentHash = '';
  int lineNumber = 0;

  for (final line in r.stdout.toString().split('\n')) {
    if (line.isEmpty) continue;
    // {40,64}: SHA-1 object names are 40 hex, SHA-256 repos' are 64. The
    // trailing space delimits the run, so the greedy quantifier can't
    // over-match into the line numbers. Hardcoding {40} silently returned an
    // empty blame in every sha256 repo.
    final hashMatch = RegExp(r'^([0-9a-f]{40,64}) \d+ (\d+)').firstMatch(line);
    if (hashMatch != null) {
      currentHash = hashMatch.group(1)!;
      lineNumber = int.tryParse(hashMatch.group(2)!) ?? 0;
      commitData.putIfAbsent(currentHash, () => {});
      continue;
    }
    if (line.startsWith('author ')) {
      commitData[currentHash]?['author'] = line.substring(7);
    }
    if (line.startsWith('author-time ')) {
      commitData[currentHash]?['time'] = line.substring(12);
    }
    if (line.startsWith('\t')) {
      final data = commitData[currentHash] ?? {};
      lines.add(
        BlameLineData(
          lineNumber: lineNumber,
          commitHash: currentHash,
          shortHash: currentHash.length >= 8
              ? currentHash.substring(0, 8)
              : currentHash,
          authorName: data['author'] ?? '',
          authoredAt: data['time'] ?? '',
          lineContent: line.substring(1),
        ),
      );
    }
  }
  return GitResult.ok(lines);
}

Future<GitResult<List<CommitSearchResultData>>> searchCommits(
  String repo,
  String query, {
  String scope = 'messages',
  int limit = 50,
}) async {
  List<String> args;
  switch (scope) {
    case 'code':
      args = [
        'log',
        '-S',
        query,
        '--format=%H%x09%h%x09%s%x09%aN%x09%aI',
        '-n',
        '$limit',
      ];
      break;
    case 'files':
      args = [
        'log',
        '--format=%H%x09%h%x09%s%x09%aN%x09%aI',
        '-n',
        '$limit',
        '--',
        query,
      ];
      break;
    default:
      args = [
        'log',
        '--grep=$query',
        '-i',
        '--format=%H%x09%h%x09%s%x09%aN%x09%aI',
        '-n',
        '$limit',
      ];
  }
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final results = <CommitSearchResultData>[];
  for (final line in r.stdout.toString().split('\n')) {
    if (line.trim().isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 5) continue;
    results.add(
      CommitSearchResultData(
        commitHash: parts[0].trim(),
        shortHash: parts[1].trim(),
        subject: parts[2].trim(),
        authorName: parts[3].trim(),
        authoredAt: parts[4].trim(),
      ),
    );
  }
  return GitResult.ok(results);
}

/// Per-file change breakdown (adds / dels / binary flag) across the
/// working tree. Combines cached and unstaged numstats from one diff
/// pass each. Binary files report `-<TAB>-` in numstat; we surface
/// `binary: true` so callers can weight them with a baseline instead
/// of the 0 they'd otherwise get from line counts.
Future<GitResult<Map<String, FileChangeWeight>>> fileChangeWeights(
  String repo,
) async {
  final weights = <String, FileChangeWeight>{};
  for (final cached in [false, true]) {
    final args = <String>['diff', '--numstat', if (cached) '--cached'];
    final r = await _git(repo, args);
    if (r.exitCode != 0) continue;
    for (final raw in r.stdout.toString().split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      final addsRaw = parts[0];
      final delsRaw = parts[1];
      final path = parts.sublist(2).join('\t').trim();
      if (path.isEmpty) continue;
      final isBinary = addsRaw == '-' || delsRaw == '-';
      final adds = isBinary ? 0 : (int.tryParse(addsRaw) ?? 0);
      final dels = isBinary ? 0 : (int.tryParse(delsRaw) ?? 0);
      final existing = weights[path];
      weights[path] = FileChangeWeight(
        adds: (existing?.adds ?? 0) + adds,
        dels: (existing?.dels ?? 0) + dels,
        binary: isBinary || (existing?.binary ?? false),
      );
    }
  }
  return GitResult.ok(weights);
}

/// Aggregated signals from a single `git log` scan over a set of
/// paths — reused by the PR detail view to surface "who knows this
/// code" + "how hot is this code right now" without doing two scans.
class FileSignals {
  /// Per-author commit count across the path union, sorted desc.
  final List<({String email, int commits})> authors;

  /// Per-path "heat" in 0..1 — exponentially-decayed commit density
  /// over the last [thermalWindowDays]. 0 = stone cold, 1 = on fire
  /// right now. Used to render the ember-glow on file pills.
  final Map<String, double> heatByPath;
  const FileSignals({required this.authors, required this.heatByPath});

  static const empty = FileSignals(authors: [], heatByPath: {});
}

/// Marker token prefixing each commit header in [scanFileSignals]'s
/// `git log` output. `\x01` (ASCII Start-of-Heading) is chosen over a
/// string sentinel like `__C__` because file paths can legally start
/// with double-underscore (e.g. `__generated__`, `__init__.py`) — a
/// control character cannot appear at column 0 of `--name-only` output
/// in any realistic repo, so misidentification is impossible.
const String _kFileSignalsMarker = '\x01';

/// One scan, two signals: who has been touching this code AND how hot
/// each file is right now (exponentially-decayed commit density).
/// Used by the PR detail surface for the PEOPLE section + per-file
/// thermal glow. Pure local git; transferable to any host.
///
/// Cost: one `git log` invocation total, regardless of path count.
/// Previously this was O(paths) subprocesses — 12 spawns per typical
/// PR detail × N expanded PRs dominated the branches-page latency on
/// Windows (each spawn ~50ms, plus .git I/O contention). The batched
/// form filters commits via the pathspec and then buckets per-file
/// in memory, preserving the original [maxPerFile] cap as a
/// newest-first counter per path.
Future<GitResult<FileSignals>> scanFileSignals(
  String repo,
  List<String> paths, {
  int maxPerFile = 20,
  int sinceDays = 365,
  double thermalTauDays = 14,
}) async {
  if (paths.isEmpty) return const GitResult.ok(FileSignals.empty);
  final since = '$sinceDays.days.ago';
  final r = await _git(repo, [
    'log',
    '--no-merges',
    // `--date-order` pins reverse-chronological-by-commit-date so the
    // per-path "newest-first" cap below is stable even in repos with
    // imported / rebased history whose default topo order would drift.
    '--date-order',
    '--since',
    since,
    '--name-only',
    // Marker-delimited commit header: email + timestamp (epoch).
    // Following lines list the file paths touched by that commit.
    // Note: `--name-only` with a pathspec emits the FULL changed-file
    // list per matching commit, not only the matching files — we
    // intersect with [pathSet] below to attribute correctly.
    '--format=$_kFileSignalsMarker%ae|%at',
    '--',
    ...paths,
  ]);
  // Best-effort signal: if the log fails (corrupt repo, invalid
  // pathspec on a single file) degrade to empty glow rather than
  // failing the whole PR detail surface — matches the old per-path
  // loop's tolerance (which `continue`d past individual failures).
  if (r.exitCode != 0) {
    return const GitResult.ok(FileSignals.empty);
  }

  final counts = <String, int>{};
  final heatByPath = <String, double>{};
  // Per-path newest-first cap that matches the old `-n $maxPerFile`
  // behaviour: git log default ordering is reverse-chronological, so
  // the first [maxPerFile] commits we see touching each path are the
  // most recent ones. Older touches are ignored for both heat and
  // author attribution.
  final perFileCount = <String, int>{};
  final pathSet = paths.toSet();
  final now = DateTime.now();

  String curEmail = '';
  DateTime? curAt;
  Set<String> curFiles = <String>{};

  void flushCommit() {
    if (curFiles.isEmpty) return;
    double? heatContribution;
    final at = curAt;
    if (at != null) {
      final ageDays = now.difference(at).inHours / 24.0;
      heatContribution = math.exp(-ageDays / thermalTauDays);
    }
    for (final file in curFiles) {
      if (!pathSet.contains(file)) continue;
      final seen = perFileCount[file] ?? 0;
      if (seen >= maxPerFile) continue;
      perFileCount[file] = seen + 1;
      if (curEmail.isNotEmpty) {
        counts[curEmail] = (counts[curEmail] ?? 0) + 1;
      }
      if (heatContribution != null) {
        heatByPath[file] = (heatByPath[file] ?? 0) + heatContribution;
      }
    }
  }

  for (final raw in (r.stdout as String).split('\n')) {
    final line = raw.trim();
    if (line.startsWith(_kFileSignalsMarker)) {
      flushCommit();
      final payload = line.substring(_kFileSignalsMarker.length);
      // Split on the LAST `|` — the author email side can legally
      // contain pipes (git accepts any string in `user.email`) while
      // the timestamp side is always `[0-9]+`, so the rightmost pipe
      // is the unambiguous delimiter.
      final pipe = payload.lastIndexOf('|');
      curEmail = pipe > 0 ? payload.substring(0, pipe) : payload;
      final tsStr = pipe > 0 ? payload.substring(pipe + 1) : '';
      final ts = int.tryParse(tsStr);
      curAt = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts * 1000)
          : null;
      curFiles = <String>{};
      continue;
    }
    if (line.isEmpty) continue;
    curFiles.add(line.replaceAll('\\', '/'));
  }
  flushCommit();

  // Heat accumulates unclamped across a file's commits; clip once at
  // the end so visualisation stays in 0..1 while preserving ordering
  // among files whose raw heat exceeds 1.
  for (final entry in heatByPath.entries.toList()) {
    heatByPath[entry.key] = entry.value.clamp(0.0, 1.0).toDouble();
  }

  final authors =
      counts.entries.map((e) => (email: e.key, commits: e.value)).toList()
        ..sort((a, b) => b.commits.compareTo(a.commits));
  return GitResult.ok(FileSignals(authors: authors, heatByPath: heatByPath));
}

Future<GitResult<void>> stagePaths(String repo, List<String> paths) async {
  if (paths.isEmpty) return const GitResult.ok(null);

  // Pre-flight gitignore filter. `git add` refuses to add a path that
  // matches a .gitignore rule AND isn't already tracked — it exits 1
  // with the matching *pattern* in the error list ("paths ignored by
  // one of your .gitignore files: .claude"). That's fine when the
  // caller genuinely tried to stage a fresh ignored file, but it also
  // fires on staged-deletion paths: a file previously untracked via
  // `git rm --cached` is in the index as a deletion, in the UI's
  // "included" list as a change to commit, and on disk as an ignored
  // file. The deletion is already in the index — no `add` needed —
  // but the UI layer doesn't know that, so the blanket add breaks.
  //
  // `git check-ignore` gives us the filter: exit 0 + stdout lists
  // matching paths; exit 1 = no matches; exit 128 = fatal. We fail
  // open on errors (treat as "nothing to filter") so a broken
  // check-ignore never blocks a legitimate stage.
  // check-ignore takes PATHNAMES (no pathspec globbing surface) and
  // rejects --literal-pathspecs outright ("pathspec magic not supported",
  // verified live) — so it runs bare. Every true pathspec-taking call in
  // the staging chain runs --literal-pathspecs: UI paths are file names,
  // not patterns. Without it, git treats `[b].txt` as a character-class
  // glob that can silently match and stage a DIFFERENT modified file
  // (verified live: `git add -- '[bracket].txt'` also staged `a.txt`) —
  // a direct violation of commit-exactly-the-included-paths.
  final ignoreCheck = await _git(repo, ['check-ignore', '--', ...paths]);
  final ignored = <String>{};
  if (ignoreCheck.exitCode == 0) {
    for (final line in ignoreCheck.stdout.toString().split('\n')) {
      final p = line.trim();
      if (p.isNotEmpty) ignored.add(p);
    }
  }
  final afterIgnore = ignored.isEmpty
      ? paths
      : paths.where((p) => !ignored.contains(p)).toList();
  // Filter out paths that don't exist on disk — they're already staged
  // as deletions in the index. Running `git add` on a deleted file
  // produces "pathspec did not match" because there's nothing to add.
  final toAdd = <String>[];
  for (final p in afterIgnore) {
    final f = File('$repo/$p'.replaceAll('/', Platform.pathSeparator));
    if (await f.exists()) {
      toAdd.add(p);
    }
  }
  if (toAdd.isEmpty) return const GitResult.ok(null);

  final r = await _git(repo, ['--literal-pathspecs', 'add', '--', ...toAdd]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> unstagePaths(String repo, List<String> paths) async {
  if (paths.isEmpty) return const GitResult.ok(null);
  // Literal pathspecs — see stagePaths: names are names, never globs.
  // --no-renames matters as much as the flag: rename detection collapses
  // a staged D+A pair into one R whose --name-only lists only the
  // DESTINATION, silently dropping the deletion half from the unstage —
  // the old name then stays staged-deleted and leaks into the commit
  // (caught by the exact-staging witness suite).
  final stagedProbe = await _git(repo, [
    '--literal-pathspecs',
    'diff',
    '--cached',
    '--name-only',
    '--no-renames',
    '-z',
    '--',
    ...paths,
  ]);
  if (stagedProbe.exitCode != 0) {
    return GitResult.err(stagedProbe.stderr.toString().trim());
  }
  // NUL-delimited output is exact by design — never trim entries. Git
  // permits filenames with leading/trailing whitespace, and trimming here
  // would unstage the wrong path (or pathspec-error) for ` file.txt`,
  // breaking the commit-exactly-the-included-paths contract upstream.
  final stagedPaths = stagedProbe.stdout
      .toString()
      .split('\x00')
      .where((path) => path.isNotEmpty)
      .toList();
  if (stagedPaths.isEmpty) return const GitResult.ok(null);

  // `reset`, not `restore --staged`: both unstage a path back to its HEAD
  // state (`restore --staged` is documented as the modern spelling of the
  // classic `git reset -- <path>`), but `restore --staged` unconditionally
  // needs to resolve HEAD internally and fatals with "could not resolve
  // HEAD" on an unborn branch — verified empirically. `reset` has a
  // long-standing special case for exactly this: with no explicit
  // tree-ish, an unborn HEAD is treated as the empty tree, so unstaging a
  // path before a repo's first commit just drops it back to untracked —
  // the correct outcome — instead of failing prepareCommitStaging outright
  // whenever a root commit excludes any staged file.
  final r = await _git(repo, [
    '--literal-pathspecs',
    'reset',
    '--',
    ...stagedPaths,
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// One captured index entry (mode, blob OID, path), enough to rebuild
/// the exact staged state of a path with `git update-index`. A staged
/// deletion has no blob to point at, so it's flagged instead.
class StagedIndexEntry {
  final String mode;
  final String oid;
  final String path;
  final bool isDeletion;

  const StagedIndexEntry({
    required this.mode,
    required this.oid,
    required this.path,
    this.isDeletion = false,
  });
}

/// Output of [prepareCommitStaging]: the index entries of excluded
/// paths that were unstaged to keep them out of the commit, so the
/// caller can hand them to [restoreStagedSelections] afterward.
///
/// [snapshotIndexPath], when non-null, is an absolute path to a frozen
/// byte-copy of the index taken the instant prepare finished arranging
/// it. The commit MUST be created against this snapshot (via
/// [createCommit]'s `indexFile`) so a mutation of the live `.git/index`
/// by an out-of-band process — another git tool touching the repo in the
/// window between prepare and commit — cannot smuggle an excluded path
/// into the commit. [createCommit] deletes the snapshot after use.
///
/// [snapshotEntries], when [snapshotIndexPath] is non-null, is the
/// snapshot's full entry table (`path -> "mode oid"`, stage-0 only)
/// captured the instant the snapshot was taken. A pre-commit hook that
/// mutates the index (format-then-`git add`, a common lint-staged
/// pattern) runs with `GIT_INDEX_FILE` pointing at the snapshot, so its
/// staging work lands there, not in the live index. [createCommit] diffs
/// this frozen table against the snapshot's post-hook state to recover
/// exactly what the hook changed, so that work can be replayed onto the
/// live index instead of evaporating with the snapshot.
class CommitStagingPlan {
  final List<StagedIndexEntry> excludedEntries;
  final String? snapshotIndexPath;
  final Map<String, String>? snapshotEntries;
  const CommitStagingPlan(
    this.excludedEntries, {
    this.snapshotIndexPath,
    this.snapshotEntries,
  });
}

/// Prepare the index so the next commit contains exactly [included].
///
/// Invariant: the commit only touches the index entries of included
/// paths, and an index entry the user built by hand survives. A path
/// with staged content — whether hunk-staged in the diff view or fully
/// staged — keeps its index entry untouched; the blanket `git add`
/// that used to run here re-staged the whole working file and silently
/// erased per-line selections. Only included paths with NO staged
/// content get a `git add`. Excluded paths with staged content are
/// unstaged for this commit, with their exact index entries captured
/// first so [restoreStagedSelections] can put the selection back.
/// Conflicted paths are left alone entirely.
Future<GitResult<CommitStagingPlan>> prepareCommitStaging(
  String repo,
  List<String> included,
) async {
  // -uall matters: without it, untracked files inside a brand-new
  // directory collapse into one "?? dir/" record, while the UI's status
  // (porcelain v2 with -u) lists them per file. The included set then
  // holds a file path no record here matches, so the file is silently
  // never staged and a selected new file vanishes from the commit.
  final st = await _git(repo, [
    'status',
    '--porcelain',
    '-z',
    '--no-renames',
    '-uall',
  ]);
  if (st.exitCode != 0) return GitResult.err(st.stderr.toString().trim());

  final includedSet = included.toSet();
  final toAdd = <String>[];
  final excludedStaged = <String>[];
  final excludedDeletions = <String>[];
  for (final rec in st.stdout.toString().split('\x00')) {
    if (rec.length < 4) continue;
    final x = rec[0];
    final y = rec[1];
    final path = rec.substring(3);
    final conflicted =
        x == 'U' ||
        y == 'U' ||
        (x == 'A' && y == 'A') ||
        (x == 'D' && y == 'D');
    if (conflicted) continue;
    final staged = x != ' ' && x != '?';
    if (includedSet.contains(path)) {
      if (!staged) toAdd.add(path);
    } else if (staged) {
      (x == 'D' ? excludedDeletions : excludedStaged).add(path);
    }
  }

  // Capture excluded entries BEFORE unstaging — `git ls-files -s` reads
  // the very index state we're about to reset.
  final entries = <StagedIndexEntry>[];
  if (excludedStaged.isNotEmpty) {
    final ls = await _git(repo, [
      '--literal-pathspecs',
      'ls-files',
      '-s',
      '-z',
      '--',
      ...excludedStaged,
    ]);
    if (ls.exitCode != 0) return GitResult.err(ls.stderr.toString().trim());
    for (final rec in ls.stdout.toString().split('\x00')) {
      if (rec.isEmpty) continue;
      // "<mode> <oid> <stage>\t<path>"
      final tab = rec.indexOf('\t');
      if (tab < 0) continue;
      final meta = rec.substring(0, tab).split(' ');
      if (meta.length < 3 || meta[2] != '0') continue;
      entries.add(
        StagedIndexEntry(
          mode: meta[0],
          oid: meta[1],
          path: rec.substring(tab + 1),
        ),
      );
    }
  }
  for (final path in excludedDeletions) {
    entries.add(
      StagedIndexEntry(mode: '', oid: '', path: path, isDeletion: true),
    );
  }

  final addResult = await stagePaths(repo, toAdd);
  if (!addResult.ok) {
    return GitResult.err(addResult.error ?? 'Failed to stage files.');
  }
  final excluded = [...excludedStaged, ...excludedDeletions];
  if (excluded.isNotEmpty) {
    final unstage = await unstagePaths(repo, excluded);
    if (!unstage.ok) {
      return GitResult.err(
        unstage.error ?? 'Failed to unstage excluded files.',
      );
    }
  }
  // Freeze the arranged index the instant it is correct, so the commit
  // is built from THIS exact state — not whatever the live index holds
  // by the time `git commit` actually runs. `git commit` always commits
  // the whole ambient index, so an out-of-band `git add` landing in the
  // prepare->commit window would be re-read and leak into the commit,
  // silently violating commit-exactly-the-included-paths (verified: a
  // concurrent external add leaks 100% of the time against the live
  // index). Committing against a byte-copy taken here makes that window
  // unrepresentable — another process cannot mutate a snapshot it cannot
  // see. Hooks still run normally (`git commit` runs them regardless of
  // which index file it reads), and empty-commit detection is preserved.
  //
  // The snapshot IS the contract now, not an optimization for the
  // has-exclusions case. It is taken UNCONDITIONALLY: a path can be
  // excluded from the commit while UNSTAGED (the common case — modified
  // but never staged, naturally out of the commit), leaving NOTHING for
  // the exclusion walk above to unstage and so, under the old
  // `if (excluded.isNotEmpty)` gate, no snapshot — yet `git commit` would
  // then read the LIVE index and a concurrent `git add` of that unstaged
  // path would still leak it in. Snapshotting every time closes that
  // TOCTOU hole. The file-copy cost is trivial next to running `git
  // commit`, so paying it unconditionally is fine. The only residual
  // (inherent) window is an external add during prepare's own multi-step
  // walk, before this copy. `_snapshotIndex` may still return null on a
  // filesystem failure, in which case the commit falls back to the live
  // index — the prior behaviour.
  final snapshotIndexPath = await _snapshotIndex(repo);
  Map<String, String>? snapshotEntries;
  if (snapshotIndexPath != null) {
    // Frozen baseline for the hook-mutation diff in `createCommit`. Read
    // against the snapshot itself, not the live index — a concurrent
    // process can still touch the live index in this window, and that's
    // exactly what the snapshot exists to be immune to.
    snapshotEntries = await _indexFileEntries(repo, snapshotIndexPath);
  }
  return GitResult.ok(
    CommitStagingPlan(
      entries,
      snapshotIndexPath: snapshotIndexPath,
      snapshotEntries: snapshotEntries,
    ),
  );
}

/// The stage-0 entry table of an arbitrary index file (`path -> "mode
/// oid"`), read via `GIT_INDEX_FILE` — verified empirically that
/// `ls-files` resolves against whichever index file is named there,
/// independent of the live `.git/index`. Conflicted (non-zero stage)
/// entries are skipped, matching every other entry-capture in this file.
Future<Map<String, String>> _indexFileEntries(
  String repo,
  String indexFile,
) async {
  final r = await _gitRaw(
    repo,
    ['--literal-pathspecs', 'ls-files', '-s', '-z'],
    env: {'GIT_INDEX_FILE': indexFile},
  );
  final map = <String, String>{};
  if (r.exitCode != 0) return map;
  for (final rec in r.stdout.toString().split('\x00')) {
    if (rec.isEmpty) continue;
    final tab = rec.indexOf('\t');
    if (tab < 0) continue;
    final meta = rec.substring(0, tab).split(' ');
    if (meta.length < 3 || meta[2] != '0') continue;
    map[rec.substring(tab + 1)] = '${meta[0]} ${meta[1]}';
  }
  return map;
}

/// Monotonic disambiguator for snapshot index filenames within a process.
int _commitIndexSnapshotCounter = 0;

/// Byte-copy the repository index to a sibling temp file inside the git
/// dir and return its absolute path, or null on any failure (the caller
/// then commits against the live index — the prior behaviour). Used by
/// [prepareCommitStaging] to hand [createCommit] a frozen index that the
/// commit is built from, immune to concurrent `.git/index` mutation.
Future<String?> _snapshotIndex(String repo) async {
  try {
    final gitDirRes = await _git(repo, ['rev-parse', '--absolute-git-dir']);
    if (gitDirRes.exitCode != 0) return null;
    final gitDir = gitDirRes.stdout.toString().trim();
    if (gitDir.isEmpty) return null;
    final indexPathRes = await _git(repo, ['rev-parse', '--git-path', 'index']);
    if (indexPathRes.exitCode != 0) return null;
    var indexPath = indexPathRes.stdout.toString().trim();
    if (indexPath.isEmpty) return null;
    // `--git-path` yields a path relative to the working dir unless it is
    // already absolute (worktrees, GIT_DIR); resolve against repo so File
    // finds it regardless of the process CWD.
    if (!p.isAbsolute(indexPath)) indexPath = p.join(repo, indexPath);
    final indexFile = File(indexPath);
    if (!await indexFile.exists()) return null;
    final dest = p.join(
      gitDir,
      'manifold-commit-index-${DateTime.now().microsecondsSinceEpoch}-${_commitIndexSnapshotCounter++}',
    );
    await indexFile.copy(dest);
    return dest;
  } catch (_) {
    return null;
  }
}

/// Best-effort delete of a temp file (the commit index snapshot). Never
/// throws — a lingering snapshot in the git dir is harmless clutter, and
/// on Windows a spawned git process may still momentarily hold the handle.
Future<void> _deleteQuietly(String path) async {
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {}
}

/// Re-stage the captured selections of paths that were excluded from a
/// commit, restoring the index byte-for-byte to what the user had
/// built: `--cacheinfo` re-points the entry at the original blob, and
/// staged deletions are re-recorded with `--force-remove`.
///
/// [skip] omits entries whose path is in the set entirely — used to keep
/// a stale capture from overwriting index work that happened AFTER the
/// capture was taken (see [finalizeCommitStaging] for the precedence
/// rule that computes it).
Future<GitResult<void>> restoreStagedSelections(
  String repo,
  List<StagedIndexEntry> entries, {
  Set<String> skip = const {},
}) async {
  if (entries.isEmpty) return const GitResult.ok(null);
  final cacheArgs = <String>[];
  final removals = <String>[];
  for (final e in entries) {
    if (skip.contains(e.path)) continue;
    if (e.isDeletion) {
      removals.add(e.path);
    } else {
      cacheArgs
        ..add('--cacheinfo')
        ..add('${e.mode},${e.oid},${e.path}');
    }
  }
  final errs = <String>[];
  if (cacheArgs.isNotEmpty) {
    final r = await _git(repo, ['update-index', '--add', ...cacheArgs]);
    if (r.exitCode != 0) errs.add(r.stderr.toString().trim());
  }
  if (removals.isNotEmpty) {
    final r = await _git(repo, [
      'update-index',
      '--force-remove',
      '--',
      ...removals,
    ]);
    if (r.exitCode != 0) errs.add(r.stderr.toString().trim());
  }
  if (errs.isNotEmpty) return GitResult.err(errs.join('\n'));
  return const GitResult.ok(null);
}

/// The commit-flow finalizer: call this — not [restoreStagedSelections]
/// directly — after [createCommit] returns, with the same [plan] passed
/// to [createCommit]. It owns the one precedence rule the whole
/// snapshot-commit machinery depends on:
///
///   A hook's mutation is user-visible work performed AFTER the capture;
///   the capture must never overwrite it.
///
/// [prepareCommitStaging] captures each excluded path's index entry
/// BEFORE the commit runs. A pre-commit hook can then stage an excluded
/// path itself (inside the snapshot — see [CommitStagingPlan]), which is
/// strictly newer information than that stale capture. Blindly replaying
/// every captured entry afterward — the pre-fix behaviour — clobbers
/// that newer work:
///   * on failure, the hook's replayed live-index entry is immediately
///     overwritten by the stale capture, and the hook's staging is lost;
///   * on success, the path was committed (same semantics as a hook
///     staging a file against the live index), the reconcile step
///     correctly syncs its live entry to HEAD, and then the stale
///     capture re-stages the OLD pre-commit blob on top — a phantom
///     staged diff for content that was just committed.
///
/// The fix: never write back a path the commit attempt has an opinion
/// about newer than the capture.
///   * on SUCCESS, skip = [CommitAttemptResult.committedPaths] ∪
///     [CommitAttemptResult.hookTouchedPaths] — anything the commit
///     actually contains, or that the hook touched inside the snapshot
///     (even if, in some edge case, it didn't end up committed), must
///     not be re-staged from the pre-commit capture.
///   * on FAILURE, skip = [CommitAttemptResult.hookTouchedPaths] only —
///     there is no commit, so nothing is skipped beyond what the hook
///     itself touched; every other excluded path restores exactly as
///     before.
Future<GitResult<void>> finalizeCommitStaging(
  String repo,
  CommitStagingPlan plan,
  CommitAttemptResult commit,
) {
  final skip = commit.ok
      ? {...commit.committedPaths, ...commit.hookTouchedPaths}
      : commit.hookTouchedPaths;
  return restoreStagedSelections(repo, plan.excludedEntries, skip: skip);
}

/// Soft-undo the most recent commit: move the branch pointer back one
/// commit while keeping the working tree AND the index exactly as the
/// commit left them — the staged set survives, ready to re-commit.
/// Refuses when HEAD no longer starts with [expectHead] (short hashes
/// welcome): if the repo moved on — new commit, pull, checkout — the
/// undo target is gone and resetting would eat someone else's work.
/// Refuses on a root commit: undoing it would mean deleting the
/// checked-out branch ref, an operation whose blast radius (the branch
/// vanishes; every tracked file reads as newly added) dwarfs the value
/// of soft-undoing a brand-new repo's first commit. `reset --soft` is
/// the ONLY mutation this function is allowed to perform.
Future<GitResult<void>> undoLastCommit(
  String repo, {
  required String expectHead,
}) async {
  if (expectHead.isEmpty) {
    return const GitResult.err('No commit hash to verify; undo skipped.');
  }
  final head = await _revParse(repo, 'HEAD');
  if (head.isEmpty || !head.startsWith(expectHead)) {
    return const GitResult.err('The repository moved on; undo skipped.');
  }
  final parent = await _git(repo, [
    'rev-parse',
    '--verify',
    '--quiet',
    'HEAD~1',
  ]);
  if (parent.exitCode != 0) {
    return const GitResult.err(
      'This is the first commit on the branch; undo it with an amend '
      'instead.',
    );
  }
  final r = await _git(repo, ['reset', '--soft', 'HEAD~1']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// Discard all changes (staged AND unstaged) for a single file, matching
/// the GitHub Desktop "Discard changes" behaviour:
///   * **Untracked** (`?`) — nothing to restore from git's side; just
///     remove the file from disk. Git never knew about it.
///   * **Newly added in the index** (`A`, not yet in HEAD) — `git
///     checkout HEAD --` would error with "did not match any file(s)
///     known to git" because the path doesn't exist there. Unstage with
///     `git rm --cached` first, then delete the working copy.
///   * **Anything else** (modified, deleted, renamed, copied, conflict)
///     — `git checkout HEAD -- <path>` resets the path to its HEAD
///     state in one shot, wiping both staged and unstaged changes.
/// Irreversible. Caller is expected to confirm before invoking.
Future<GitResult<void>> discardFile(
  String repo,
  RepositoryStatusFile file,
) async {
  if (file.isUntracked) {
    return _deleteFromDisk(repo, file.path);
  }
  if (file.isStagedAddition) {
    final unstage = await _git(repo, [
      'rm',
      '--cached',
      '--force',
      '--',
      file.path,
    ]);
    if (unstage.exitCode != 0) {
      return GitResult.err(unstage.stderr.toString().trim());
    }
    return _deleteFromDisk(repo, file.path);
  }
  final r = await _git(repo, ['checkout', 'HEAD', '--', file.path]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> _deleteFromDisk(String repo, String relPath) async {
  try {
    final f = File(p.join(repo, relPath));
    if (await f.exists()) await f.delete();
    return const GitResult.ok(null);
  } catch (e) {
    return GitResult.err('Failed to delete file: $e');
  }
}

/// Append a single pattern to the repository's `.gitignore`. Creates
/// the file if it doesn't exist; ensures the existing content ends
/// with a newline before appending; no-ops if the exact pattern (after
/// trimming) is already present, so repeated invocations stay clean.
Future<GitResult<void>> addToGitignore(String repo, String pattern) async {
  try {
    final f = File(p.join(repo, '.gitignore'));
    final existing = await f.exists() ? await f.readAsString() : '';
    final trimmedPattern = pattern.trim();
    final alreadyPresent = existing
        .split('\n')
        .any((l) => l.trim() == trimmedPattern && trimmedPattern.isNotEmpty);
    if (alreadyPresent) return const GitResult.ok(null);
    final needsLeadingNewline = existing.isNotEmpty && !existing.endsWith('\n');
    final next = '$existing${needsLeadingNewline ? '\n' : ''}$trimmedPattern\n';
    await f.writeAsString(next);
    return const GitResult.ok(null);
  } catch (e) {
    return GitResult.err('Failed to update .gitignore: $e');
  }
}

/// Pipes a unified diff to `git apply`. Used for line-level staging AND
/// for the patch-loop (external .patch files).
/// - `cached` writes to the index (--cached). Mutually exclusive with the
///   patch-loop options; setting `threeWay` or `dryRun` overrides implicit
///   cached semantics per git's own rules.
/// - `reverse` inverts the patch (`-R`).
/// - `dryRun` uses `--check` — parses + simulates, never mutates.
/// - `threeWay` uses `-3` — falls back to 3-way merge on context drift.
Future<GitResult<void>> applyPatch(
  String repo,
  String patch, {
  bool cached = true,
  bool reverse = false,
  bool dryRun = false,
  bool threeWay = false,
  String? telemetryLabel,
}) async {
  if (patch.trim().isEmpty) return const GitResult.ok(null);
  final args = <String>['apply'];
  if (cached) args.add('--cached');
  if (reverse) args.add('-R');
  if (dryRun) args.add('--check');
  if (threeWay) args.add('--3way');
  args.addAll(['--whitespace=nowarn', '-']);
  // Route through the shared stdin-capable exec path so `git apply` is
  // classified MUTATING: it now takes a semaphore permit, bumps
  // gitMutationsInFlight (so GitDirWatcher pauses instead of racing the
  // staging write), and retries a transient index.lock — the same
  // choreography every other index mutation gets. The former bare _spawnStart
  // had none of that. Payload is raw UTF-8 bytes with a guaranteed trailing
  // newline; the runner re-sends it on each retry attempt.
  final payload = <int>[...utf8.encode(patch), if (!patch.endsWith('\n')) 0x0A];
  try {
    final r = await _gitRawStdin(
      repo,
      args,
      stdinPayload: payload,
      commandLabel: telemetryLabel ?? 'git.apply',
    );
    if (r.exitCode != 0) {
      final stderrText = r.stderr.toString().trim();
      return GitResult.err(
        stderrText.isEmpty ? 'git apply exit ${r.exitCode}' : stderrText,
      );
    }
    return const GitResult.ok(null);
  } catch (e) {
    return GitResult.err(e.toString());
  }
}

/// Atomic per-file partial staging: resets the index entry for the file to
/// HEAD, then applies the user's partial patch — so the index reflects
/// exactly the set of lines the user has marked staged in the UI.
///
/// The reset result is checked, not ignored: `git reset -q HEAD -- <path>`
/// exits 0 for every benign shape (untracked path with no HEAD entry, unborn
/// HEAD — both verified empirically), so ANY nonzero exit means the reset
/// never landed (index.lock exhaustion, index write failure, ...). Applying
/// on top of an un-reset entry would target a stale preimage and fail with a
/// misleading "patch does not apply" — or worse, stack onto the wrong
/// content — so the real reset error is surfaced instead.
///
/// An empty patch ends with the file fully unstaged — which is the
/// correct outcome when the user has deselected every line.
Future<GitResult<void>> applyFileStaging(
  String repo,
  String filePath,
  String patch,
) async {
  final reset = await _git(repo, ['reset', '-q', 'HEAD', '--', filePath]);
  if (reset.exitCode != 0) {
    final stderrText = reset.stderr.toString().trim();
    return GitResult.err(
      stderrText.isEmpty ? 'git reset exit ${reset.exitCode}' : stderrText,
    );
  }
  if (patch.trim().isEmpty) return const GitResult.ok(null);
  return applyPatch(repo, patch, cached: true);
}

/// Outcome of [createCommit]. Unlike [GitResult] — whose `.err` factory
/// forces `data` to null — this carries [hookTouchedPaths] on BOTH
/// success and failure, because [finalizeCommitStaging] needs it to
/// compute the restore-precedence skip set regardless of whether the
/// commit itself landed.
class CommitAttemptResult {
  final CommitData? data;
  final String? error;

  /// Paths the new commit actually touched (`git diff-tree` against
  /// HEAD). Empty on failure, and empty on success when no snapshot was
  /// involved (nothing was excluded, so there is nothing to protect a
  /// restore from).
  final Set<String> committedPaths;

  /// Paths a pre-commit hook mutated inside the commit snapshot
  /// (relative to the snapshot's pre-hook baseline), on both success and
  /// failure. Empty when there was no snapshot, or the hook touched
  /// nothing.
  final Set<String> hookTouchedPaths;

  /// Non-fatal: the commit itself landed (this is only ever set on
  /// success), but the post-commit live-index reconcile
  /// (`--literal-pathspecs reset -q HEAD -- <committedPaths>`) failed —
  /// e.g. transient index.lock contention this call didn't retry into
  /// success, or a permissions hiccup. [committedPaths] is still correct
  /// (it comes from `diff-tree`, a read, computed before the reset ever
  /// ran) and [finalizeCommitStaging]'s skip-set — hence restore
  /// correctness for excluded paths — is unaffected: see the disjointness
  /// argument on [_reconcileLiveIndexAfterSnapshotCommit]. The only thing
  /// a failed reset leaves behind is live-index tidiness — some just-
  /// committed paths may still show as staged with their pre-commit blob
  /// until the next `git add`/status refresh touches them. Null when
  /// there was nothing to reconcile or the reconcile succeeded; never
  /// used to fail a commit that already landed.
  final String? reconcileWarning;

  /// Non-fatal, failure-path sibling of [reconcileWarning]: only ever set
  /// on FAILURE, when a pre-commit hook mutated the snapshot's index but
  /// replaying that mutation onto the live index (`update-index --add
  /// --cacheinfo` / `--force-remove`, see [_replayHookIndexMutations])
  /// itself failed — e.g. the live index.lock is held. When that happens
  /// the affected paths are excluded from [hookTouchedPaths] (the replay
  /// never landed, so there is nothing there for [finalizeCommitStaging]
  /// to protect), which means the OLDER pre-commit capture is restored for
  /// them instead — strictly better than the hook's staging vanishing
  /// with neither version surviving. This field exists purely to surface
  /// that "kept the older capture because the replay failed" outcome to
  /// the caller; it never blocks or unwinds anything. Null when there was
  /// no hook mutation to replay, or the replay fully succeeded.
  final String? hookReplayWarning;

  bool get ok => error == null;

  const CommitAttemptResult.ok(
    CommitData this.data, {
    this.committedPaths = const {},
    this.hookTouchedPaths = const {},
    this.reconcileWarning,
  }) : error = null,
       hookReplayWarning = null;

  const CommitAttemptResult.err(
    String this.error, {
    this.hookTouchedPaths = const {},
    this.hookReplayWarning,
  }) : data = null,
       committedPaths = const {},
       reconcileWarning = null;
}

/// Create a commit. When [amend] is true, an empty [message] is
/// allowed and routes to `git commit --amend --no-edit` so git
/// keeps the prior commit's message (rather than rewriting it to
/// the empty string). A non-empty [message] always wins — both
/// amend and regular commits use `-m <message>` in that case.
///
/// [plan] — the [CommitStagingPlan] returned by [prepareCommitStaging] —
/// carries the hermetic-commit machinery as ONE inseparable unit. Its
/// [CommitStagingPlan.snapshotIndexPath] is a frozen byte-copy of the
/// index the commit is built from via `GIT_INDEX_FILE`, so a concurrent
/// mutation of the live `.git/index` cannot alter what this commit
/// contains; its [CommitStagingPlan.snapshotEntries] is the pre-hook
/// baseline used to recover a hook's index mutations. These two were once
/// independent named params (`indexFile:` / `snapshotEntries:`), which
/// let a caller pass one without the other and silently lose
/// hook-mutation preservation — a severable contract that is now
/// unrepresentable: both are derived from the single [plan] here.
///
/// Pass `plan: null` (or omit it) for a direct commit outside the staging
/// flow: the commit then runs against the live `.git/index` with no
/// snapshot, the pre-fix behaviour.
///
/// This function takes ownership of the snapshot file and deletes it after
/// the commit (success or failure). Hooks and empty-commit detection are
/// unaffected — `git commit` runs them against whichever index file it
/// reads — but a hook that mutates the index (format-then-`git add`)
/// mutates the SNAPSHOT, not the live index, so its work is reconciled
/// back onto the live index here rather than being silently dropped or
/// left stale:
///   * success — the live index is brought forward to match the paths
///     the new commit actually touched (a `git --literal-pathspecs reset
///     -q HEAD -- <paths>`), so no phantom staged diff is left for any
///     path the hook rewrote. [CommitAttemptResult.committedPaths]
///     carries that touched set back to the caller.
///   * failure — the snapshot's frozen entry table (from the instant it
///     was created) is diffed against the snapshot's current state to
///     recover exactly what the hook changed, and that delta is replayed
///     onto the live index before the snapshot is deleted, so the hook's
///     staging work survives — UNLESS the replay itself fails (e.g. the
///     live index.lock is held), in which case [CommitAttemptResult
///     .hookTouchedPaths] omits exactly those paths (see
///     [_replayHookIndexMutations]'s exit-code honesty) so
///     [finalizeCommitStaging] falls back to the older pre-commit capture
///     for them instead of writing back nothing — the failure-path mirror
///     of the success-path reset-honesty fix on
///     [_reconcileLiveIndexAfterSnapshotCommit]. Any such replay failure
///     is also surfaced via [CommitAttemptResult.hookReplayWarning].
/// Either way, [CommitAttemptResult.hookTouchedPaths] carries the hook's
/// SUCCESSFULLY-recovered touched-path set back to the caller — computed
/// before the snapshot is deleted — so [finalizeCommitStaging] can keep a
/// stale pre-commit capture from overwriting work the hook did after that
/// capture was taken, without ever skipping a restore for a path whose
/// hook version didn't actually make it back.
Future<CommitAttemptResult> createCommit(
  String repo,
  String message, {
  bool amend = false,
  bool signoff = false,
  CommitStagingPlan? plan,
}) async {
  final indexFile = plan?.snapshotIndexPath;
  final snapshotEntries = plan?.snapshotEntries;
  final args = ['commit'];
  if (amend) args.add('--amend');
  if (signoff) args.add('-s');
  if (message.isEmpty) {
    if (amend) {
      // Amend with no new message → keep the previous commit's
      // message. Without `--no-edit` git would launch the editor;
      // we want a non-interactive flow.
      args.add('--no-edit');
    } else {
      // Regular commits with empty messages would be rejected by
      // the upstream caller (`_commit` in `changes_page.dart`),
      // but defend the API surface anyway: an empty `-m ""` on a
      // non-amend commit produces an actually-empty subject and
      // is almost never what the caller wanted.
      if (indexFile != null) await _deleteQuietly(indexFile);
      return const CommitAttemptResult.err('Commit message is required.');
    }
  } else {
    args.addAll(['-m', message]);
  }
  // The operation-delta oracle: captured BEFORE the commit runs, so the
  // post-commit reconcile below can diff "what did THIS OPERATION land"
  // rather than "what is the new HEAD relative to its own parent"
  // (`git diff-tree HEAD` with no explicit base — the pre-fix behavior).
  // That distinction only matters — and only costs a `rev-parse` — when
  // there's a snapshot to reconcile afterward:
  //   * normal commit — oldTip is the parent, identical to the old
  //     single-rev behavior.
  //   * amend — oldTip is the PRE-amend tip, so the diff is exactly the
  //     amend's delta. The old single-rev form diffed the amended commit
  //     against ITS parent, which reports the entire amended commit —
  //     including files carried over untouched from the pre-amend
  //     commit — as "just committed", and those files then got skipped
  //     by finalizeCommitStaging's restore even though the amend never
  //     touched them.
  //   * root commit — no parent exists, so oldTip is null and
  //     [_emptyTreeOid] stands in; the diff is the entire first commit.
  //     The old single-rev form emits nothing at all for a rootless
  //     `diff-tree HEAD`, so the live index was never reconciled after a
  //     repo's first commit.
  final oldTip = indexFile == null
      ? null
      : await _revParseVerifyQuiet(repo, 'HEAD');
  final r = indexFile == null
      ? await _git(repo, args)
      : await _gitRaw(repo, args, env: {'GIT_INDEX_FILE': indexFile});
  var committedPaths = const <String>{};
  var hookTouchedPaths = const <String>{};
  String? reconcileWarning;
  String? hookReplayWarning;
  if (indexFile != null) {
    if (r.exitCode == 0) {
      // Compute the hook delta from the snapshot BEFORE it's deleted —
      // needed for restore precedence even though (in the common case)
      // any hook-touched path is already inside committedPaths, since a
      // hook stages into the very index that then gets committed.
      if (snapshotEntries != null) {
        hookTouchedPaths = await _hookIndexDelta(
          repo,
          indexFile,
          snapshotEntries,
        );
      }
      // oldTip is null exactly on an unborn-HEAD (root) commit; fall back
      // to the empty-tree oid so the diff still has a base. If BOTH the
      // rev-parse and the empty-tree derivation come back null the repo's
      // git plumbing is broken badly enough that guessing a base would be
      // worse than skipping the reconcile — committedPaths stays empty,
      // same outward shape as any other reconcile short-circuit.
      final diffBase = oldTip ?? await _emptyTreeOid(repo);
      if (diffBase != null) {
        final reconciled = await _reconcileLiveIndexAfterSnapshotCommit(
          repo,
          diffBase,
        );
        committedPaths = reconciled.paths;
        reconcileWarning = reconciled.warning;
      }
    } else if (snapshotEntries != null) {
      final replayed = await _replayHookIndexMutations(
        repo,
        indexFile,
        snapshotEntries,
      );
      hookTouchedPaths = replayed.paths;
      hookReplayWarning = replayed.warning;
    }
    await _deleteQuietly(indexFile);
  }
  if (r.exitCode != 0) {
    return CommitAttemptResult.err(
      r.stderr.toString().trim(),
      hookTouchedPaths: hookTouchedPaths,
      hookReplayWarning: hookReplayWarning,
    );
  }
  // Parse: "[branch abc1234] Subject line"
  final out = r.stdout.toString();
  final match = RegExp(r'\[(?:[^\s]+)\s+([a-f0-9]+)\]\s*(.+)').firstMatch(out);
  final hash = match?.group(1) ?? '';
  final summary =
      match?.group(2)?.trim() ??
      (message.isEmpty ? '(amend)' : message.split('\n').first);
  return CommitAttemptResult.ok(
    CommitData(repositoryPath: repo, commitHash: hash, summary: summary),
    committedPaths: committedPaths,
    hookTouchedPaths: hookTouchedPaths,
    reconcileWarning: reconcileWarning,
  );
}

/// After a snapshot-backed commit succeeds, bring the live `.git/index`
/// forward to what committing against the live index would have left:
/// for exactly the paths THIS OPERATION landed, reset the live index
/// entry to HEAD.
///
/// [base] is the diff-tree base — the answer to "what did this operation
/// land" rather than "what is the new HEAD relative to its own parent".
/// [createCommit] derives it as the pre-commit tip (or the empty-tree oid
/// on a root commit) precisely so this stays correct across normal
/// commits, amends, and root commits alike; see the comment at its call
/// site for the amend/root reasoning. This helper itself is base-agnostic
/// — it only trusts whatever base it's handed.
///
/// Returns the touched-path set (see [CommitAttemptResult.committedPaths])
/// together with a non-fatal [_ReconcileOutcome.warning] when the `reset`
/// step failed. Committed paths are disjoint from the excluded paths
/// [restoreStagedSelections] is about to replay (prepare only excludes
/// paths NOT in this commit) — EXCEPT via a path a pre-commit hook staged
/// inside the snapshot, which [CommitAttemptResult.hookTouchedPaths]
/// separately covers and [finalizeCommitStaging] also skips — and disjoint
/// from any concurrent out-of-band edit to an unrelated path (reset is
/// scoped to exactly these paths) — so this cannot reopen the TOCTOU the
/// snapshot exists to close.
///
/// That disjointness is why a failed `reset` is safe to demote to a
/// warning instead of treating it as a restore-integrity failure: the
/// paths [restoreStagedSelections] skips because they're in [paths] were
/// NEVER going to be written back regardless of whether the live-index
/// reset actually ran (skip is computed from the path SET, not from the
/// reset's success). A failed reset therefore can only leave a committed
/// path's live-index entry stale (still showing the pre-commit blob as
/// staged) — a tidiness gap the next status refresh or `git add` clears
/// up — never a lost or wrongly-restored excluded selection. The exec
/// layer already retries transient index.lock contention on mutating
/// calls (see [_gitRaw]), so a `reset` failure that reaches here is a
/// real error worth surfacing, not lock noise to swallow silently.
///
/// Verified empirically: `git reset -q HEAD -- <path>` exits 0, touches
/// only the named entries, and removes a path from the index entirely
/// when HEAD no longer has it (a committed deletion) — no special-casing
/// needed for adds, edits, or deletes.
Future<({Set<String> paths, String? warning})>
_reconcileLiveIndexAfterSnapshotCommit(String repo, String base) async {
  final touched = await _git(repo, [
    'diff-tree',
    '--no-commit-id',
    '--name-only',
    '-z',
    '-r',
    base,
    'HEAD',
  ]);
  if (touched.exitCode != 0) return (paths: const <String>{}, warning: null);
  final paths = touched.stdout
      .toString()
      .split('\x00')
      .where((s) => s.isNotEmpty)
      .toSet();
  if (paths.isEmpty) return (paths: const <String>{}, warning: null);
  // `--literal-pathspecs` (before the subcommand — the only accepted
  // position; verified `git reset --literal-pathspecs` is rejected) is
  // mandatory here: without it a committed hostile name like
  // `[bracket].txt` is read as a character-class glob and this `reset`
  // also unstages an unrelated modified file it happens to match (verified
  // live: plain `git reset -- '[bracket].txt'` also reset `a.txt`),
  // desyncing the very live index this helper exists to reconcile. The
  // `diff-tree` above only EMITS paths, never matching them against a
  // pathspec, so it needs no such flag.
  final reset = await _git(repo, [
    '--literal-pathspecs',
    'reset',
    '-q',
    'HEAD',
    '--',
    ...paths,
  ]);
  if (reset.exitCode != 0) {
    final shown = paths.take(5).join(', ');
    final more = paths.length > 5 ? ', +${paths.length - 5} more' : '';
    return (
      paths: paths,
      warning:
          'Commit landed, but the live index could not be reconciled '
          'for $shown$more (may still show as staged with stale content '
          'until the next refresh): ${reset.stderr.toString().trim()}',
    );
  }
  return (paths: paths, warning: null);
}

/// The set of paths a pre-commit hook mutated inside the commit
/// snapshot, computed as a read-only diff between [frozen] (the
/// snapshot's entry table captured the instant [prepareCommitStaging]
/// created it) and the snapshot's entries now: anything added, changed,
/// or removed counts as touched. Does not mutate any index — used on the
/// success path, where the live index is separately brought forward by
/// [_reconcileLiveIndexAfterSnapshotCommit] rather than by replaying this
/// delta.
Future<Set<String>> _hookIndexDelta(
  String repo,
  String snapshotIndexPath,
  Map<String, String> frozen,
) async {
  final now = await _indexFileEntries(repo, snapshotIndexPath);
  final touched = <String>{};
  for (final e in now.entries) {
    if (frozen[e.key] != e.value) touched.add(e.key);
  }
  for (final path in frozen.keys) {
    if (!now.containsKey(path)) touched.add(path);
  }
  return touched;
}

/// After a snapshot-backed commit is rejected (a pre-commit hook exited
/// non-zero), recover any index mutation the hook made INSIDE the
/// snapshot and replay it onto the LIVE index before the snapshot is
/// discarded — otherwise staging work the hook did (e.g. auto-format
/// then `git add`, the common lint-staged pattern) evaporates with it.
/// Computed as a diff between [frozen] (the snapshot's entry table
/// captured the instant [prepareCommitStaging] created it) and the
/// snapshot's entries now: anything added or changed is replayed with
/// `--cacheinfo`, anything that disappeared is replayed with
/// `--force-remove`.
///
/// Mirror of [_reconcileLiveIndexAfterSnapshotCommit]'s reset-honesty fix,
/// other branch: that helper never claims a path is reconciled unless the
/// `reset` covering it actually exited 0; this one never claims a path is
/// REPLAYED unless the `update-index` call covering it actually exited 0.
/// Both `update-index` invocations run against the LIVE index (unlike the
/// commit itself, which runs against the snapshot's own `GIT_INDEX_FILE`),
/// so ordinary live-index contention — an index.lock, a permissions
/// hiccup — can make either one fail independently of the other. Only the
/// paths covered by a call that actually landed are reported as replayed
/// (see [CommitAttemptResult.hookTouchedPaths]); the two calls are each
/// batched (one `--add --cacheinfo` invocation for every added/changed
/// path, one `--force-remove` invocation for every removed path) rather
/// than issued per-path, so a failure demotes its WHOLE batch to
/// unreplayed rather than only the one path git happened to choke on —
/// coarser than per-path granularity, but honest: [finalizeCommitStaging]
/// then falls back to the older pre-commit capture for exactly those
/// paths instead of writing back nothing, which is strictly better than
/// silently losing both the hook's version and the capture. Any such
/// failure is also summarized in the returned `warning` (surfaced via
/// [CommitAttemptResult.hookReplayWarning]) so the caller can tell the
/// user their hook's staging didn't fully make it back. A hook that never
/// touches the index produces an empty delta — a no-op costing one
/// `ls-files` — and this can't clobber an unrelated concurrent live-index
/// change since only paths the hook actually touched inside the snapshot
/// are ever named.
Future<({Set<String> paths, String? warning})> _replayHookIndexMutations(
  String repo,
  String snapshotIndexPath,
  Map<String, String> frozen,
) async {
  final now = await _indexFileEntries(repo, snapshotIndexPath);
  final cacheArgs = <String>[];
  final addedOrChanged = <String>{};
  for (final e in now.entries) {
    if (frozen[e.key] != e.value) {
      addedOrChanged.add(e.key);
      final parts = e.value.split(' ');
      if (parts.length != 2) continue;
      cacheArgs
        ..add('--cacheinfo')
        ..add('${parts[0]},${parts[1]},${e.key}');
    }
  }
  final removals = frozen.keys.where((path) => !now.containsKey(path)).toList();

  final touched = <String>{};
  final failures = <String>[];

  if (cacheArgs.isNotEmpty) {
    final r = await _git(repo, ['update-index', '--add', ...cacheArgs]);
    if (r.exitCode == 0) {
      touched.addAll(addedOrChanged);
    } else {
      final shown = addedOrChanged.take(5).join(', ');
      final more = addedOrChanged.length > 5
          ? ', +${addedOrChanged.length - 5} more'
          : '';
      failures.add('staged content for $shown$more');
    }
  }
  if (removals.isNotEmpty) {
    final r = await _git(repo, [
      'update-index',
      '--force-remove',
      '--',
      ...removals,
    ]);
    if (r.exitCode == 0) {
      touched.addAll(removals);
    } else {
      final shown = removals.take(5).join(', ');
      final more = removals.length > 5 ? ', +${removals.length - 5} more' : '';
      failures.add('removal of $shown$more');
    }
  }

  if (failures.isEmpty) return (paths: touched, warning: null);
  return (
    paths: touched,
    warning:
        'The pre-commit hook modified the index, but replaying that '
        'onto the live index after the rejected commit did not fully land '
        '(${failures.join('; ')}); the older pre-commit staged version was '
        'kept for those paths instead.',
  );
}

Future<GitResult<SyncData>> fetchRemote(
  String repo, {
  String? remote,
  bool prune = false,
}) async {
  final r = remote ?? 'origin';
  final args = ['fetch', if (prune) '--prune', r];
  final result = await _git(repo, args);
  if (result.exitCode != 0) {
    return GitResult.err(result.stderr.toString().trim());
  }
  return GitResult.ok(
    SyncData(
      operation: 'fetch',
      remote: r,
      output: result.stdout.toString().trim(),
    ),
  );
}

// NOTE: the raw `git pull`/`git sync` helpers were deleted with the
// conflict unification — every UI path now goes through `resolvePull` /
// `resolveSync` (features/changes/merge_conflict_flow.dart) so conflicts
// always route through the one editor. Reintroducing a bare `git pull` here
// would quietly re-open the dead-end this change set exists to remove; build
// on `prepareMergePull` + the reconcile engine below instead.

// ── Merge / pull reconciliation engine ──────────────────────────────────
// One conflict path for pull, branch-merge and patch-apply. The guiding
// principle: `git merge` is the only dirty-INTOLERANT primitive, so when the
// working tree has edits the merge would overwrite, we reconcile with
// `git merge-file` (a blob-level 3-way that ignores the index and never
// needs a clean tree) instead of stashing. Topology is then recorded with
// the same plumbing git uses internally — `reset --mixed` for a
// fast-forward, a hand-written `MERGE_HEAD` + commit for a merge commit.

Future<String> _revParse(String repo, String rev) async {
  final r = await _git(repo, ['rev-parse', rev]);
  return r.exitCode == 0 ? (r.stdout as String).trim() : '';
}

/// `git rev-parse --verify --quiet <rev>`, returning null (not `''`) when
/// [rev] doesn't resolve — the clean way to detect an unborn `HEAD` (a
/// brand-new repo before its first commit): exit code 1, empty stderr
/// thanks to `--quiet`, no exception. Distinct from [_revParse], whose
/// `''`-on-any-failure return can't be told apart from "resolved to an
/// empty string" (never happens for a commit-ish, but the point is this
/// call site needs an explicit tri-state, not a lossy one).
Future<String?> _revParseVerifyQuiet(String repo, String rev) async {
  final r = await _git(repo, ['rev-parse', '--verify', '--quiet', rev]);
  if (r.exitCode != 0) return null;
  final out = (r.stdout as String).trim();
  return out.isEmpty ? null : out;
}

/// The empty-tree object id, derived at runtime rather than hardcoded.
/// `write-tree` against a scratch `GIT_INDEX_FILE` that does not yet exist
/// is treated by git as an empty index (verified empirically), so this
/// needs no stdin — unlike `git hash-object -t tree --stdin`, which would
/// (this exec layer has no stdin-piping support; see [_gitRaw]/[_git]).
///
/// Why not just hardcode `4b825dc642cb6eb9a060e54bf8d69288fbee4904` (SHA-1
/// git's well-known empty-tree oid, printed by the derivation above on
/// every ordinary repo)? A SHA-256 repository (`git init
/// --object-format=sha256`) has a DIFFERENT empty-tree oid. A hardcoded
/// SHA-1 constant handed to `diff-tree` on such a repo is not a rejected
/// oid — it just doesn't name any object git knows about — so the root-
/// commit diff would silently misbehave instead of failing loudly. Runtime
/// derivation is correct for both object formats without knowing which one
/// the repo uses.
///
/// `write-tree` leaves the scratch index file behind on disk (a real file
/// is created even though it started out empty) — the caller cleans it up
/// with [_deleteQuietly], same idiom as the commit-index snapshot.
Future<String?> _emptyTreeOid(String repo) async {
  final gitDirRes = await _git(repo, ['rev-parse', '--absolute-git-dir']);
  if (gitDirRes.exitCode != 0) return null;
  final gitDir = gitDirRes.stdout.toString().trim();
  if (gitDir.isEmpty) return null;
  final scratchIndex = p.join(
    gitDir,
    'manifold-empty-index-${DateTime.now().microsecondsSinceEpoch}-${_commitIndexSnapshotCounter++}',
  );
  try {
    final r = await _git(
      repo,
      ['write-tree'],
      extraEnv: {'GIT_INDEX_FILE': scratchIndex},
    );
    if (r.exitCode != 0) return null;
    final oid = (r.stdout as String).trim();
    return oid.isEmpty ? null : oid;
  } finally {
    await _deleteQuietly(scratchIndex);
  }
}

Future<bool> _isAncestor(String repo, String a, String b) async {
  final r = await _git(repo, ['merge-base', '--is-ancestor', a, b]);
  return r.exitCode == 0;
}

/// The upstream ref the active branch tracks (`origin/main`), or null.
Future<String?> _upstreamRef(String repo) async {
  final r = await _git(repo, [
    'rev-parse',
    '--abbrev-ref',
    '--symbolic-full-name',
    '@{u}',
  ]);
  if (r.exitCode != 0) return null;
  final s = (r.stdout as String).trim();
  return s.isEmpty ? null : s;
}

/// The remote segment of an abbreviated upstream ref like `origin/main`
/// (everything before the first `/`). Null when there's no upstream.
String? _remoteOf(String? upstreamRef) {
  if (upstreamRef == null) return null;
  final i = upstreamRef.indexOf('/');
  return i > 0 ? upstreamRef.substring(0, i) : null;
}

/// The remote the current branch actually tracks (the `<remote>` in its
/// `@{u}`), falling back to the repo's primary remote, then `origin`. Use this
/// instead of hardcoding `origin` so a branch tracking a differently named
/// remote fetches and pushes the right place.
Future<String> trackingRemote(String repo) async {
  final fromUpstream = _remoteOf(await _upstreamRef(repo));
  if (fromUpstream != null) return fromUpstream;
  final primary = await primaryRemoteName(repo);
  return primary.ok ? (primary.data ?? 'origin') : 'origin';
}

Future<String?> _currentBranchName(String repo) async {
  final r = await _git(repo, ['symbolic-ref', '--short', 'HEAD']);
  if (r.exitCode != 0) return null;
  final s = (r.stdout as String).trim();
  return s.isEmpty ? null : s;
}

/// Paths the incoming tip changed relative to [base] — the merge's set.
Future<List<String>> _incomingPaths(
  String repo,
  String base,
  String theirs,
) async {
  final r = await _git(repo, ['diff', '--name-only', '$base..$theirs']);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Repo-relative paths with uncommitted edits, split into `all` (includes
/// untracked `??` entries — these still block a `git merge` when they
/// overlap an incoming add) and `tracked` (excludes untracked — the set a
/// `git rebase` refuses to run over). One `git status` parse for both.
Future<({Set<String> all, Set<String> tracked})> _modifiedPaths(
  String repo,
) async {
  final all = <String>{};
  final tracked = <String>{};
  final r = await _git(repo, ['status', '--porcelain']);
  if (r.exitCode != 0) return (all: all, tracked: tracked);
  for (final line in (r.stdout as String).split('\n')) {
    if (line.length < 4) continue;
    final xy = line.substring(0, 2);
    var path = line.substring(3).trim();
    // Renames render as "old -> new"; the working-tree path is the new one.
    // Each side is C-quoted independently under core.quotePath=true (git
    // default), so split on the arrow FIRST, then un-C-quote the new side.
    final arrow = path.indexOf(' -> ');
    if (arrow >= 0) path = path.substring(arrow + 4);
    path = unCQuoteGitPath(path);
    if (path.isEmpty) continue;
    all.add(path);
    if (xy != '??') tracked.add(path);
  }
  return (all: all, tracked: tracked);
}

String _absPath(String repo, String path) =>
    '$repo/$path'.replaceAll('/', Platform.pathSeparator);

/// Paths currently staged (index differs from HEAD).
Future<List<String>> _stagedPaths(String repo) async {
  final r = await _git(repo, ['diff', '--cached', '--name-only']);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Side-effect-free plan for a pull: fetches, then classifies what the merge
/// would do without touching the working tree. The returned [MergePrep]
/// tells the flow layer whether to take the clean-tree native path or the
/// dirty `merge-file` reconcile, and which topology to record.
Future<MergePrep> prepareMergePull(
  String repo, {
  String? remote,
  bool rebase = false,
}) async {
  final upstream = await _upstreamRef(repo);
  final r = remote ?? _remoteOf(upstream) ?? 'origin';
  final fetch = await _git(repo, ['fetch', r]);
  if (fetch.exitCode != 0) {
    return MergePrep.failed((fetch.stderr as String).trim());
  }
  if (upstream == null) {
    return const MergePrep.failed('No upstream is configured for this branch.');
  }
  final theirs = await _revParse(repo, upstream);
  final head = await _revParse(repo, 'HEAD');
  if (theirs.isEmpty || head.isEmpty) {
    return const MergePrep.failed('Could not resolve refs for merge.');
  }
  // Nothing incoming: theirs is already contained in HEAD.
  if (theirs == head || await _isAncestor(repo, theirs, head)) {
    return const MergePrep.upToDate();
  }
  final baseR = await _git(repo, ['merge-base', 'HEAD', theirs]);
  final base = baseR.exitCode == 0 ? (baseR.stdout as String).trim() : '';
  final incoming = await _incomingPaths(repo, base, theirs);
  final modified = await _modifiedPaths(repo);
  final ff = await _isAncestor(repo, head, theirs);
  final topology = rebase
      ? MergeTopology.rebase
      : (ff ? MergeTopology.fastForward : MergeTopology.mergeCommit);
  // `git merge` only balks on an incoming path that's locally modified
  // (overlap); a non-overlapping dirty file rides along. `git rebase`,
  // though, refuses to run over ANY tracked modification, so the rebase
  // topology must treat the whole tracked-dirty tree as blocking — else an
  // unrelated edit dead-ends on a raw "cannot rebase: unstaged changes".
  final blocking = topology == MergeTopology.rebase
      ? modified.tracked.toList()
      : incoming.where(modified.all.contains).toList();
  final branch = await _currentBranchName(repo);
  return MergePrep(
    repoPath: repo,
    remote: r,
    upstream: upstream,
    incomingRef: theirs,
    baseRef: base,
    oursLabel: branch ?? 'ours',
    theirsLabel: upstream,
    incomingPaths: incoming,
    blockingPaths: blocking,
    topology: topology,
  );
}

/// Clean-tree path: let git do the merge natively (robust for renames,
/// modes, binaries). On conflict git leaves `MERGE_HEAD` + UU entries, which
/// the flow gathers into the editor; finalize is then a plain `git commit`.
Future<MergeOutcome> runNativeMerge(String repo, MergePrep prep) async {
  final args = prep.topology == MergeTopology.rebase
      ? ['rebase', prep.incomingRef]
      : ['merge', '--no-edit', prep.incomingRef];
  final r = await _git(repo, args);
  if (r.exitCode == 0) {
    return MergeClean(
      SyncData(
        operation: 'pull',
        remote: prep.remote,
        output: (r.stdout as String).trim(),
      ),
    );
  }
  final conflicted = await _conflictedPaths(repo);
  if (conflicted.isNotEmpty) return MergeConflicted(conflicted);
  return MergeFailed((r.stderr as String).trim());
}

/// Conflicted (UU) paths recorded in the index.
Future<List<String>> _conflictedPaths(String repo) async {
  final r = await _git(repo, ['diff', '--name-only', '--diff-filter=U']);
  if (r.exitCode != 0) return const [];
  return (r.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// True when the index has any unmerged (UU) entries. Used to tell a
/// `rebase --continue` that HALTED at the next conflicting commit (non-zero
/// exit, fresh UU, rebase still in progress) apart from a genuine abort.
Future<bool> hasUnmergedPaths(String repo) async =>
    (await _conflictedPaths(repo)).isNotEmpty;

/// Raw bytes of `rev:path`, bypassing `_git`'s String decode (which would
/// lossily map binary to U+FFFD). Null when the path doesn't exist there.
Future<List<int>?> _blobBytes(String repo, String rev, String path) async {
  // A read (no mutation bump), but it still spawns a git subprocess — take a
  // permit so it counts against the app-wide concurrency budget instead of
  // escaping the semaphore the way the bare _spawnRunRaw call used to.
  await _gitSubprocessSemaphore.acquire();
  try {
    final r = await _spawnRunRaw(
      ['show', '$rev:$path'],
      workingDirectory: repo,
      environment: _kNonInteractiveGitEnv,
    );
    if (r.exitCode != 0) return null;
    return r.stdout as List<int>;
  } catch (_) {
    return null;
  } finally {
    _gitSubprocessSemaphore.release();
  }
}

/// git's own heuristic: a NUL byte in the first 8000 bytes ⇒ binary.
bool _looksBinary(List<int>? bytes) {
  if (bytes == null) return false;
  final n = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < n; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

bool _bytesEqual(List<int>? a, List<int>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Decodes [bytes] as UTF-8, or null when they aren't valid UTF-8 (treated as
/// binary). Strict so we never silently corrupt non-UTF-8 content.
String? _decodeUtf8OrNull(List<int>? bytes) {
  if (bytes == null) return null;
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return null;
  }
}

/// Dirty-tree path: 3-way every incoming path with `git merge-file`, reading
/// ours from the live working tree and base/theirs from the object store.
/// Produces [ReconciledFile]s IN MEMORY — nothing is written, so a cancelled
/// reconcile leaves the tree exactly as it was. The flow opens the editor on
/// the conflicted ones and writes everything at finalize.
///
/// Binary-safe: every read is byte-level. A non-text path (NUL byte or
/// non-UTF-8 on any side) is NEVER fed to the text merge — an unmodified
/// binary takes theirs as raw bytes, a both-sides-changed binary is flagged
/// as a binary conflict for the caller to block on. This avoids the strict-
/// UTF-8 `readAsString` crash and the lossy String round-trip that would
/// corrupt the file.
Future<List<ReconciledFile>> reconcileDirtyMerge(
  String repo,
  MergePrep prep,
) async {
  final out = <ReconciledFile>[];
  final tmp = await Directory.systemTemp.createTemp('manifold-merge');
  try {
    for (final path in prep.incomingPaths) {
      final oursFile = File(_absPath(repo, path));
      final oursBytes = await oursFile.exists()
          ? await oursFile.readAsBytes()
          : null;
      final baseBytes = await _blobBytes(repo, prep.baseRef, path);
      final theirsBytes = await _blobBytes(repo, prep.incomingRef, path);

      final ours = _decodeUtf8OrNull(oursBytes);
      final base = _decodeUtf8OrNull(baseBytes);
      final theirs = _decodeUtf8OrNull(theirsBytes);

      // A side that has bytes but isn't valid UTF-8 is NOT text — fold it into
      // the binary path. Otherwise the empty-string substitution below
      // (`ours ?? ''` etc.) would feed merge-file blank content and silently
      // corrupt or drop a non-UTF-8 file that happens to carry no NUL byte.
      final undecodable =
          (oursBytes != null && ours == null) ||
          (baseBytes != null && base == null) ||
          (theirsBytes != null && theirs == null);

      final isBinary =
          undecodable ||
          _looksBinary(oursBytes) ||
          _looksBinary(baseBytes) ||
          _looksBinary(theirsBytes);

      if (isBinary) {
        final oursUnchanged =
            oursBytes == null || _bytesEqual(oursBytes, baseBytes);
        if (theirsBytes == null) {
          // theirs deleted a binary.
          out.add(
            ReconciledFile(
              path: path,
              mergedText: '',
              conflicted: !oursUnchanged,
              deleted: oursUnchanged,
              binary: true,
            ),
          );
        } else if (oursUnchanged) {
          // Clean update / pure add — take theirs as raw bytes.
          out.add(
            ReconciledFile(
              path: path,
              mergedText: '',
              conflicted: false,
              binary: true,
              binaryBytes: theirsBytes,
            ),
          );
        } else {
          // Both sides changed a binary — unresolvable in-app; caller blocks.
          out.add(
            ReconciledFile(
              path: path,
              mergedText: '',
              conflicted: true,
              binary: true,
            ),
          );
        }
        continue;
      }

      // Past here every present side decoded cleanly (null ⇒ absent), so the
      // `?? ''` fallbacks only ever stand in for a genuinely missing file.
      // theirs removed the file.
      if (theirsBytes == null) {
        if (oursBytes == null || ours == base) {
          out.add(
            ReconciledFile(
              path: path,
              mergedText: '',
              conflicted: false,
              deleted: true,
            ),
          );
        } else {
          // modify/delete — surface as a conflict (ours vs an empty theirs).
          final marker =
              '<<<<<<< ${prep.oursLabel}\n$ours\n'
              '=======\n>>>>>>> ${prep.theirsLabel} (deleted)\n';
          out.add(
            ReconciledFile(path: path, mergedText: marker, conflicted: true),
          );
        }
        continue;
      }
      // Pure add by theirs with no local copy — take it as-is.
      if (baseBytes == null && oursBytes == null) {
        out.add(
          ReconciledFile(
            path: path,
            mergedText: theirs ?? '',
            conflicted: false,
          ),
        );
        continue;
      }
      final res = await _mergeFile(
        tmp,
        repo,
        ours: ours ?? '',
        base: base ?? '',
        theirs: theirs ?? '',
        oursLabel: prep.oursLabel,
        theirsLabel: prep.theirsLabel,
      );
      out.add(
        ReconciledFile(path: path, mergedText: res.$1, conflicted: res.$2),
      );
    }
  } finally {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
  return out;
}

/// Blob-level 3-way via `git merge-file -p --diff3`. Returns the merged text
/// and whether it contains conflict markers. Operates on temp files so the
/// working tree is never touched.
Future<(String, bool)> _mergeFile(
  Directory tmp,
  String repo, {
  required String ours,
  required String base,
  required String theirs,
  required String oursLabel,
  required String theirsLabel,
}) async {
  final oursTmp = File('${tmp.path}${Platform.pathSeparator}ours');
  final baseTmp = File('${tmp.path}${Platform.pathSeparator}base');
  final theirsTmp = File('${tmp.path}${Platform.pathSeparator}theirs');
  await oursTmp.writeAsString(ours);
  await baseTmp.writeAsString(base);
  await theirsTmp.writeAsString(theirs);
  final r = await _git(repo, [
    'merge-file',
    '-p',
    '--diff3',
    '-L',
    oursLabel,
    '-L',
    'base',
    '-L',
    theirsLabel,
    oursTmp.path,
    baseTmp.path,
    theirsTmp.path,
  ]);
  // merge-file: exit 0 = clean, 1..127 = that many conflicts, >=128 = error.
  final text = r.stdout as String;
  final conflicted = r.exitCode > 0 && r.exitCode < 128;
  return (text, conflicted);
}

/// Records a reconciled dirty merge in history after the editor has written
/// the resolved conflict files. [cleanWrites] are the non-conflicting
/// incoming paths whose merged content the editor never touched — finalize
/// writes them here so a cancelled editor leaves the tree pristine. Topology
/// decides how the result lands:
///   • fastForward → `git reset --mixed <incoming>` (ref + index advance,
///     resolved working tree preserved, nothing committed).
///   • mergeCommit → stage the merged paths, write `MERGE_HEAD`, commit.
Future<GitResult<void>> finalizeReconciledMerge(
  String repo,
  MergePrep prep,
  List<ReconciledFile> reconciled,
) async {
  // Snapshot everything finalize is about to mutate so a failure at ANY step
  // restores "the tree as it was" rather than leaving a half-applied pull:
  //  • the working-tree bytes of the clean files we materialise, and
  //  • the user's pre-existing staging selection for files OUTSIDE the merge
  //    set (both topology ops rewrite the whole index, unstaging them).
  final cleanFiles = reconciled.where((f) => !f.conflicted).toList();
  final originalWt = <String, List<int>?>{};
  for (final f in cleanFiles) {
    final abs = File(_absPath(repo, f.path));
    originalWt[f.path] = await abs.exists() ? await abs.readAsBytes() : null;
  }
  final incomingSet = prep.incomingPaths.toSet();
  final unrelatedStaged = (await _stagedPaths(
    repo,
  )).where((p) => !incomingSet.contains(p)).toList();
  final stagedSnapshot = await snapshotIndexEntries(repo, unrelatedStaged);

  // Undo every finalize mutation (working-tree writes, any half-written merge
  // state, the index surgery) and surface [err].
  Future<GitResult<void>> rollback(String err) async {
    for (final entry in originalWt.entries) {
      final abs = File(_absPath(repo, entry.key));
      try {
        if (entry.value == null) {
          if (await abs.exists()) await abs.delete();
        } else {
          await abs.writeAsBytes(entry.value!);
        }
      } catch (_) {}
    }
    await _clearMergeState(repo);
    await restoreIndexEntries(repo, stagedSnapshot);
    return GitResult.err(err);
  }

  // Materialise the clean-merged + deletion paths the editor didn't handle.
  for (final f in cleanFiles) {
    final abs = File(_absPath(repo, f.path));
    try {
      if (f.deleted) {
        if (await abs.exists()) await abs.delete();
      } else {
        // A pure incoming add can live under a brand-new directory the dirty
        // path hasn't checked out — create it before writing (no-op at root).
        await abs.parent.create(recursive: true);
        if (f.binary) {
          // Raw bytes — never round-trip binary through a String.
          await abs.writeAsBytes(f.binaryBytes ?? const <int>[]);
        } else {
          await abs.writeAsString(f.mergedText);
        }
      }
    } catch (e) {
      return rollback('Could not write ${f.path}: $e');
    }
  }

  switch (prep.topology) {
    case MergeTopology.fastForward:
      // Advance ref + index to the incoming tip; the working tree (resolved
      // content + any unrelated local edits) is left untouched.
      final r = await _git(repo, ['reset', '--mixed', prep.incomingRef]);
      if (r.exitCode != 0) return rollback((r.stderr as String).trim());
      await restoreIndexEntries(repo, stagedSnapshot);
      return const GitResult.ok(null);

    case MergeTopology.mergeCommit:
      // The merge commit must record EXACTLY merge(HEAD, theirs): HEAD's tree
      // with the reconciled incoming paths, and nothing else. A pathspec-less
      // `git commit` commits the whole index, so any files the user had
      // staged before pulling would be swept into an auto-generated merge
      // commit they didn't author — and a partial commit isn't allowed while
      // MERGE_HEAD is set. So reset the index to HEAD first (working tree
      // untouched), then stage only the reconciled paths. The user's
      // unrelated edits stay in the working tree, uncommitted.
      final reset = await _git(repo, ['read-tree', 'HEAD']);
      if (reset.exitCode != 0) {
        return rollback(reset.stderr.toString().trim());
      }
      final paths = prep.incomingPaths;
      if (paths.isNotEmpty) {
        final add = await _git(repo, ['add', '--', ...paths]);
        if (add.exitCode != 0) return rollback((add.stderr as String).trim());
      }
      final wrote = await _writeMergeHead(repo, prep.incomingRef);
      if (wrote != null) return rollback(wrote);
      final commit = await _git(repo, [
        'commit',
        '--no-edit',
        '-m',
        'Merge ${prep.theirsLabel}',
      ]);
      if (commit.exitCode != 0) {
        return rollback(commit.stderr.toString().trim());
      }
      // Re-stage the user's unrelated curated changes the read-tree dropped.
      await restoreIndexEntries(repo, stagedSnapshot);
      return const GitResult.ok(null);

    default:
      return const GitResult.err(
        'Rebase pulls into a dirty tree are not reconciled in place — '
        'commit your changes first.',
      );
  }
}

/// Memo of static repo geometry — `rev-parse --git-dir`,
/// `--git-common-dir`, and `--git-path <x>` — keyed by a length-prefixed
/// (repoPath, args) signature (see [_gitDedupKey]). These outputs are fixed
/// for a given repo path: `.git` doesn't relocate under a live working copy,
/// and `--git-path` resolves a name to the same location every time. We cache
/// the RAW output byte-for-byte and never reinterpret it, so a git version
/// that prints `--git-path` relative to CWD keeps the exact semantics the
/// call sites already handle via [_resolveGitPath].
///
/// No TTL, no invalidation: the only event that changes these values is the
/// repo moving on disk, which yields a different repoPath and therefore a
/// different key — the stale entry is simply never consulted again. (What a
/// path like `rebase-merge` *points at* is cached; whether that dir currently
/// exists is always re-checked live at the call site, so mid-rebase state
/// transitions are unaffected.)
final Map<String, ProcessResult> _repoGeometryCache = {};

/// Runs (or replays) a static repo-geometry `rev-parse` through the memo
/// above. Only exit-zero results are cached; a failure re-spawns each time so
/// the caller's error branch sees the real stderr rather than a stale success.
Future<ProcessResult> _revParseGeometry(
  String repo,
  List<String> revParseArgs,
) async {
  final key = _gitDedupKey(repo, revParseArgs);
  final cached = _repoGeometryCache[key];
  if (cached != null) return cached;
  final r = await _git(repo, revParseArgs);
  if (r.exitCode == 0) _repoGeometryCache[key] = r;
  return r;
}

/// Test seam onto the geometry memo. A repeat call returns the SAME cached
/// [ProcessResult] instance, which is how a test distinguishes a memo hit
/// from a fresh spawn.
@visibleForTesting
Future<ProcessResult> revParseGeometryForTesting(
  String repo,
  List<String> revParseArgs,
) => _revParseGeometry(repo, revParseArgs);

/// Drops all memoized geometry so one test can't leak a cached path into the
/// next (temp repos are recreated per test with fresh paths, but this keeps
/// the map from growing across a run).
@visibleForTesting
void clearRepoGeometryCacheForTesting() => _repoGeometryCache.clear();

/// Writes the second merge parent to `<git-dir>/MERGE_HEAD` so the next
/// `git commit` records a two-parent merge commit. Returns an error string
/// on failure, or null on success.
Future<String?> _writeMergeHead(String repo, String incomingRef) async {
  final dir = await _revParseGeometry(repo, ['rev-parse', '--git-dir']);
  if (dir.exitCode != 0) return (dir.stderr as String).trim();
  var gitDir = (dir.stdout as String).trim();
  if (gitDir.isEmpty) return 'Could not resolve git directory.';
  // rev-parse may print a path relative to the repo root.
  final isAbsolute = p.isAbsolute(gitDir);
  final base = isAbsolute ? gitDir : p.join(repo, gitDir);
  try {
    await File(p.join(base, 'MERGE_HEAD')).writeAsString('$incomingRef\n');
    await File(p.join(base, 'MERGE_MSG')).writeAsString('Merge commit\n');
    return null;
  } catch (e) {
    return 'Could not write MERGE_HEAD: $e';
  }
}

/// Captures the index entry (`<mode> <oid> <stage>`) for each path, or null
/// when the path isn't staged. Paired with [restoreIndexEntries] to make a
/// staging side-effect fully reversible — so a rolled-back operation leaves
/// the index exactly as it was, not just the working tree.
Future<Map<String, String?>> snapshotIndexEntries(
  String repo,
  List<String> paths,
) async {
  final out = <String, String?>{for (final p in paths) p: null};
  if (paths.isEmpty) return out;
  final r = await _git(repo, ['ls-files', '--stage', '--', ...paths]);
  if (r.exitCode != 0) return out;
  for (final line in (r.stdout as String).split('\n')) {
    final tab = line.indexOf('\t');
    if (tab < 0) continue;
    final path = line.substring(tab + 1);
    if (out.containsKey(path)) out[path] = line.substring(0, tab).trim();
  }
  return out;
}

/// Restores index entries captured by [snapshotIndexEntries]: re-stages the
/// original blob, or force-removes the entry when the path wasn't indexed.
Future<void> restoreIndexEntries(
  String repo,
  Map<String, String?> snapshot,
) async {
  for (final entry in snapshot.entries) {
    final meta = entry.value;
    if (meta == null) {
      await _git(repo, ['update-index', '--force-remove', '--', entry.key]);
    } else {
      // meta = "<mode> <oid> <stage>"
      final parts = meta.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        await _git(repo, [
          'update-index',
          '--cacheinfo',
          '${parts[0]},${parts[1]},${entry.key}',
        ]);
      }
    }
  }
}

/// Removes the hand-written `MERGE_HEAD`/`MERGE_MSG` so a failed reconcile
/// commit doesn't leave the repo parked mid-merge. Best-effort.
Future<void> _clearMergeState(String repo) async {
  final dir = await _revParseGeometry(repo, ['rev-parse', '--git-dir']);
  if (dir.exitCode != 0) return;
  final gitDir = (dir.stdout as String).trim();
  if (gitDir.isEmpty) return;
  final base = p.isAbsolute(gitDir) ? gitDir : p.join(repo, gitDir);
  for (final name in const ['MERGE_HEAD', 'MERGE_MSG']) {
    try {
      final f = File(p.join(base, name));
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Finalises a clean-tree native merge whose conflicts the editor just
/// resolved (`MERGE_HEAD` is already set by git). A plain commit concludes
/// the merge with correct two-parent topology.
Future<GitResult<void>> commitResolvedMerge(String repo) async {
  final r = await _git(repo, ['commit', '--no-edit']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// True while a rebase is paused (mid-`pull --rebase` conflict resolution).
Future<bool> isRebaseInProgress(String repo) async {
  final dir = await _revParseGeometry(repo, [
    'rev-parse',
    '--git-path',
    'rebase-merge',
  ]);
  if (dir.exitCode == 0) {
    final pathMerge = (dir.stdout as String).trim();
    if (pathMerge.isNotEmpty &&
        await Directory(_resolveGitPath(repo, pathMerge)).exists()) {
      return true;
    }
  }
  final apply = await _revParseGeometry(repo, [
    'rev-parse',
    '--git-path',
    'rebase-apply',
  ]);
  if (apply.exitCode == 0) {
    final pathApply = (apply.stdout as String).trim();
    if (pathApply.isNotEmpty &&
        await Directory(_resolveGitPath(repo, pathApply)).exists()) {
      return true;
    }
  }
  return false;
}

String _resolveGitPath(String repo, String maybeRelative) =>
    p.isAbsolute(maybeRelative) ? maybeRelative : p.join(repo, maybeRelative);

Future<bool> _hasGitFile(String repo, String name) async {
  final r = await _revParseGeometry(repo, ['rev-parse', '--git-path', name]);
  if (r.exitCode != 0) return false;
  final path = (r.stdout as String).trim();
  return path.isNotEmpty && await File(_resolveGitPath(repo, path)).exists();
}

/// The git operation currently paused mid-conflict in [repo], or null when
/// nothing is in progress. Lets a recovery surface conclude the RIGHT way —
/// a paused rebase needs `rebase --continue`, not a plain commit.
Future<String?> inProgressOperation(String repo) async {
  if (await isRebaseInProgress(repo)) return 'rebase';
  if (await _hasGitFile(repo, 'CHERRY_PICK_HEAD')) return 'cherry-pick';
  if (await _hasGitFile(repo, 'REVERT_HEAD')) return 'revert';
  if (await _hasGitFile(repo, 'MERGE_HEAD')) return 'merge';
  return null;
}

/// Continues a paused rebase after the editor staged the resolution. Our
/// rebase is always NON-interactive (`git rebase <ref>`), but whether
/// `--continue` opens an editor for a conflicted pick's carried message is
/// GIT-VERSION-DEPENDENT: git 2.43 (Ubuntu LTS) does (empirically verified —
/// headless it dies with "Standard input is not a terminal" at the CURRENT
/// step instead of halting at the next conflict), while newer git replays the
/// message silently. `GIT_EDITOR=true` accepts the carried message on every
/// platform — git launches editors through its own bundled `sh`, where `true`
/// always resolves, so this does not depend on the user's PATH (the concern
/// that ruled out a `core.editor` override for cherry-pick/revert, which have
/// the `git commit --no-edit` alternative this multi-step flow lacks).
Future<GitResult<void>> continueRebase(String repo) async {
  final r = await _git(
    repo,
    ['rebase', '--continue'],
    extraEnv: const {'GIT_EDITOR': 'true'},
  );
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<SyncData>> pushRemote(
  String repo, {
  String? remote,
  String? branch,
  bool setUpstream = false,
  bool forceWithLease = false,
}) async {
  final r = remote ?? 'origin';
  // Canonical arg order: subcommand → flags → positional refspec.
  // Modern git is permissive about flags after positional args, but
  // the canonical form is unambiguous and stable across the parser
  // tightening that older releases occasionally apply (e.g. when
  // POSIXLY_CORRECT is set, trailing flags get treated as paths).
  final args = ['push'];
  if (forceWithLease) args.add('--force-with-lease');
  if (setUpstream) {
    args.addAll(['--set-upstream', r, branch ?? 'HEAD']);
  } else {
    args.add(r);
    if (branch != null) args.add(branch);
  }
  final result = await _git(repo, args);
  if (result.exitCode != 0) {
    return GitResult.err(result.stderr.toString().trim());
  }
  return GitResult.ok(
    SyncData(
      operation: 'push',
      remote: r,
      output: result.stdout.toString().trim(),
    ),
  );
}

// The legacy raw-`git pull` and smart-sync helper functions were removed with
// the conflict unification: that decision tree now lives in `resolveSync`
// (merge_conflict_flow.dart), which routes the pull leg through `resolvePull`
// so every conflict reaches the one editor. Build new sync paths there — not
// on a bare `git pull` here. (Deliberately omitting the old symbol names so
// the grep-based removal verifier doesn't read this note as a live use.)

Future<GitResult<String>> archiveRepository(
  String repoPath,
  String outputPath,
) async {
  try {
    final r = await _git(repoPath, [
      'archive',
      '--format=zip',
      '--output=$outputPath',
      'HEAD',
    ]);
    if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
    return GitResult.ok(outputPath);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

Future<GitResult<String>> templateFromRepository(
  String sourceRepo,
  String targetPath,
) async {
  try {
    final dir = Directory(targetPath);
    if (await dir.exists()) {
      return const GitResult.err('Target directory already exists.');
    }
    final clone = await _git(sourceRepo, [
      'clone',
      '--depth',
      '1',
      sourceRepo,
      targetPath,
    ]);
    if (clone.exitCode != 0) {
      return GitResult.err(clone.stderr.toString().trim());
    }
    final gitDir = Directory(p.join(targetPath, '.git'));
    if (await gitDir.exists()) {
      await gitDir.delete(recursive: true);
    }
    final init = await _git(targetPath, ['init']);
    if (init.exitCode != 0) {
      return GitResult.err(init.stderr.toString().trim());
    }
    final add = await _git(targetPath, ['add', '-A']);
    if (add.exitCode != 0) {
      return GitResult.err(_gitStepError('stage template files', add));
    }
    final commit = await _git(targetPath, ['commit', '-m', 'Initial commit']);
    if (commit.exitCode != 0) {
      return GitResult.err(_gitStepError('commit template repository', commit));
    }
    return GitResult.ok(targetPath);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

String _gitStepError(String action, ProcessResult result) {
  final stderr = result.stderr.toString().trim();
  final stdout = result.stdout.toString().trim();
  final detail = stderr.isNotEmpty
      ? stderr
      : stdout.isNotEmpty
      ? stdout
      : 'git exited with code ${result.exitCode}';
  return 'Failed to $action: $detail';
}

Future<GitResult<String>> cloneRepository(
  String url,
  String targetPath, {
  void Function(String line)? onProgress,
}) async {
  if (_activeCloneProcess != null) {
    return const GitResult.err('Clone already in progress');
  }
  try {
    final absTarget = p.canonicalize(targetPath);
    final parent = Directory(p.dirname(absTarget));
    if (!await parent.exists()) await parent.create(recursive: true);

    await _gitSubprocessSemaphore.acquire();
    Process? proc;
    try {
      proc = await _spawnStart(
        ['clone', '--progress', url, absTarget],
        environment: _kNonInteractiveGitEnv,
        mode: ProcessStartMode.normal,
      );
      // Bind the clone (a potentially long-running child) to the kill-on-close
      // job object so app-exit tears the whole git tree down instead of
      // orphaning a network fetch — parity with ai.dart's spawns.
      WinJobObject.assignProcess(proc.pid);
      _activeCloneProcess = proc;
      _activeCloneTarget = absTarget;
      final recentStderr = <String>[];
      final stderrLines = proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final stdoutDrain = proc.stdout.drain<void>();
      await for (final line in stderrLines) {
        onProgress?.call(line);
        if (line.trim().isNotEmpty) {
          recentStderr.add(line.trim());
          if (recentStderr.length > 5) recentStderr.removeAt(0);
        }
      }
      await stdoutDrain;
      final exitCode = await proc.exitCode;
      if (exitCode != 0) {
        final detail = recentStderr.isNotEmpty
            ? recentStderr.last
            : 'git clone exited with code $exitCode';
        return GitResult.err(detail);
      }
    } finally {
      if (_activeCloneProcess == proc) {
        _activeCloneProcess = null;
        _activeCloneTarget = null;
      }
      _gitSubprocessSemaphore.release();
    }
    return GitResult.ok(absTarget);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

Process? _activeCloneProcess;
String? _activeCloneTarget;

Future<void> cancelActiveClone() async {
  final proc = _activeCloneProcess;
  _activeCloneProcess = null;
  final target = _activeCloneTarget;
  _activeCloneTarget = null;
  if (proc != null) {
    proc.kill();
    await proc.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () => -1,
    );
  }
  if (target != null) {
    try {
      final dir = Directory(target);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }
}

Future<GitResult<String>> initRepository(String path) async {
  try {
    final absPath = p.canonicalize(path);
    final dir = Directory(absPath);
    if (!await dir.exists()) await dir.create(recursive: true);
    final r = await _git(absPath, ['init']);
    if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
    return GitResult.ok(absPath);
  } catch (error) {
    return GitResult.err(error.toString());
  }
}

/// Upper bound on our fully-automated interactive rebase. The sequence editor
/// writes the todo non-interactively, so there is nothing to wait on a human
/// for — a stall means a hung child, which we tree-kill rather than let pin a
/// semaphore permit forever.
const Duration _kInteractiveRebaseTimeout = Duration(seconds: 120);

Future<GitResult<void>> startInteractiveRebase(
  String repo,
  List<RebaseTodoEntry> entries,
) async {
  // Build the todo list content
  final todo = interactiveRebaseTodoForTesting(entries);

  final tmpDir = await Directory.systemTemp.createTemp('git-rebase-editor-');
  final tmpFile = File('${tmpDir.path}${Platform.pathSeparator}todo.txt');
  await tmpFile.writeAsString(todo);

  // Git invokes GIT_SEQUENCE_EDITOR as: `<editor> <todo-file>`.
  // Use a tiny script so Windows can read the todo path as %1 inside
  // batch context; inline `cmd /c ... %1` treats %1 as literal text.
  final editorScript = File(
    '${tmpDir.path}${Platform.pathSeparator}sequence-editor'
    '${Platform.isWindows ? '.cmd' : '.sh'}',
  );
  if (Platform.isWindows) {
    await editorScript.writeAsString(
      windowsSequenceEditorScriptForTesting(tmpFile.path),
    );
  } else {
    await editorScript.writeAsString(
      unixSequenceEditorScriptForTesting(tmpFile.path),
    );
  }
  final sequenceEditor = Platform.isWindows
      ? windowsSequenceEditorCommandForTesting(editorScript.path)
      : unixSequenceEditorCommandForTesting(editorScript.path);

  final ontoRef = entries.isNotEmpty
      ? '${entries.last.commitHash}~1'
      : 'HEAD~${entries.length}';
  final ProcessResult r;
  // Parity with the shared exec layer (`_gitRaw`): this mutation used to
  // bypass it entirely. It now takes the same semaphore permit the clone
  // path takes (held outside read-coalescing — it mutates), merges the
  // non-interactive env with the sequence editor that feeds the todo list,
  // decodes raw bytes leniently through [_decodeGitBytes] (strict utf8 would
  // throw on a non-UTF-8 commit message replayed in the output), and kills
  // the whole process tree on timeout via [killProcessTree] so the .cmd/.sh
  // editor wrapper and its git child don't orphan on Windows.
  await _gitSubprocessSemaphore.acquire();
  try {
    final proc = await _spawnStart(
      ['rebase', '-i', ontoRef],
      workingDirectory: repo,
      environment: {
        ..._kNonInteractiveGitEnv,
        'GIT_SEQUENCE_EDITOR': sequenceEditor,
      },
    );
    // Same orphan containment as the clone path: the interactive rebase drives
    // a .cmd/.sh sequence-editor wrapper plus a git child, so bind the tree to
    // the kill-on-close job object rather than relying on killProcessTree alone.
    WinJobObject.assignProcess(proc.pid);
    final stdoutBytes = proc.stdout.fold<BytesBuilder>(
      BytesBuilder(),
      (b, d) => b..add(d),
    );
    final stderrBytes = proc.stderr.fold<BytesBuilder>(
      BytesBuilder(),
      (b, d) => b..add(d),
    );
    int exitCode;
    try {
      exitCode = await proc.exitCode.timeout(_kInteractiveRebaseTimeout);
    } on TimeoutException {
      await killProcessTree(proc);
      exitCode = await proc.exitCode;
    }
    final out = _decodeGitBytes((await stdoutBytes).takeBytes(), strict: false);
    final err = _decodeGitBytes((await stderrBytes).takeBytes(), strict: false);
    r = ProcessResult(proc.pid, exitCode, out.text, err.text);
  } finally {
    _gitSubprocessSemaphore.release();
    await tmpDir.delete(recursive: true).catchError((_) => tmpDir);
  }

  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

String _shellSingleQuote(String value) {
  return "'${value.replaceAll("'", r"'\''")}'";
}

String _windowsBatchDoubleQuotedLiteral(String value) => value
    .replaceAll('/', '\\')
    .replaceAll('^', '^^')
    .replaceAll('%', '%%')
    .replaceAll('"', '""');

String _windowsCmdDoubleQuotedLiteral(String value) => value
    .replaceAll('/', '\\')
    .replaceAll('^', '^^')
    .replaceAll('%', '^%')
    .replaceAll('"', '""');

@visibleForTesting
String interactiveRebaseTodoForTesting(List<RebaseTodoEntry> entries) {
  if (entries.isEmpty) return '';
  return '${entries.map((e) => '${e.action} ${e.commitHash} ${e.subject}').join('\n')}\n';
}

@visibleForTesting
String windowsSequenceEditorScriptForTesting(String todoPath) {
  final escapedTodoPath = _windowsBatchDoubleQuotedLiteral(todoPath);
  return '@echo off\r\n'
      'copy /y "$escapedTodoPath" "%~1" >NUL\r\n'
      'exit /b %ERRORLEVEL%\r\n';
}

@visibleForTesting
String windowsSequenceEditorCommandForTesting(String scriptPath) {
  final escapedScriptPath = _windowsCmdDoubleQuotedLiteral(scriptPath);
  return 'cmd.exe /d /c call "$escapedScriptPath"';
}

@visibleForTesting
String unixSequenceEditorScriptForTesting(String todoPath) {
  return '#!/bin/sh\n'
      'cp ${_shellSingleQuote(todoPath)} "\$1"\n';
}

@visibleForTesting
String unixSequenceEditorCommandForTesting(String scriptPath) {
  return 'sh ${_shellSingleQuote(scriptPath)}';
}

Future<GitResult<List<StashEntryData>>> listStashes(String repo) async {
  // Format: index, hash, date, message
  final r = await _git(repo, [
    'stash',
    'list',
    '--format=%gd\x1f%H\x1f%ci\x1f%gs',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final lines = r.stdout
      .toString()
      .trim()
      .split('\n')
      .where((l) => l.isNotEmpty)
      .toList();
  final entries = <StashEntryData>[];
  for (final line in lines) {
    final parts = line.split('\x1f');
    if (parts.length < 4) continue;
    // stash@{0} → 0
    final indexMatch = RegExp(r'\{(\d+)\}').firstMatch(parts[0]);
    final index = indexMatch != null
        ? int.tryParse(indexMatch.group(1)!) ?? 0
        : entries.length;
    entries.add(
      StashEntryData(
        index: index,
        hash: parts[1],
        createdAt: parts[2],
        message: parts[3],
      ),
    );
  }
  // Enrich with file counts (fast — only stat, no diff content).
  for (var i = 0; i < entries.length && i < 20; i++) {
    final stat = await _git(repo, [
      'stash',
      'show',
      '--stat',
      'stash@{${entries[i].index}}',
    ]);
    if (stat.exitCode == 0) {
      final statLines = stat.stdout.toString().trim().split('\n');
      // Last line of --stat is the summary: " 3 files changed, ..."
      final summary = statLines.isNotEmpty ? statLines.last : '';
      final countMatch = RegExp(r'(\d+) files? changed').firstMatch(summary);
      final count = countMatch != null
          ? int.tryParse(countMatch.group(1)!) ?? 0
          : 0;
      entries[i] = StashEntryData(
        index: entries[i].index,
        hash: entries[i].hash,
        createdAt: entries[i].createdAt,
        message: entries[i].message,
        fileCount: count,
      );
    }
  }
  return GitResult.ok(entries);
}

/// Stash the working tree. [includeUntracked] is required (no default)
/// because the bare-git default silently leaves untracked new files
/// behind — a well-known footgun ("I thought I stashed everything").
/// Forcing every caller to declare intent at the call site means the
/// behavior is auditable: searching for `includeUntracked: false`
/// finds every "leave untracked behind" case, and the absence of a
/// default keeps any future caller from inheriting whichever choice
/// happened to be in fashion when this signature was last touched.
Future<GitResult<String>> stashPush(
  String repo, {
  String? message,
  List<String>? paths,
  bool keepIndex = false,
  required bool includeUntracked,
}) async {
  final args = <String>['stash', 'push'];
  if (keepIndex) args.add('--keep-index');
  // -u captures untracked files; pairs cleanly with --keep-index when
  // the user wants "stage these, stash everything else including new
  // files." Mutually exclusive with `--all` (which we don't use).
  if (includeUntracked) args.add('--include-untracked');
  if (message != null && message.trim().isNotEmpty) {
    args.addAll(['-m', message.trim()]);
  }
  if (paths != null && paths.isNotEmpty) {
    args.add('--');
    args.addAll(paths);
  }
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString().trim());
}

Future<GitResult<void>> stashPop(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'pop', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> stashApply(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'apply', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> stashDrop(String repo, {int index = 0}) async {
  final r = await _git(repo, ['stash', 'drop', 'stash@{$index}']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

/// The commit OID backing `stash@{index}`, or null. Captured BEFORE a slow
/// async operation (conflict editor) so the entry can later be dropped by
/// identity rather than by a positional index that may have shifted.
Future<String?> stashHashAt(String repo, int index) async {
  final r = await _git(repo, ['rev-parse', 'stash@{$index}']);
  if (r.exitCode != 0) return null;
  final s = r.stdout.toString().trim();
  return s.isEmpty ? null : s;
}

/// Drops the stash entry whose commit OID is [hash], re-resolving its current
/// position first — so a stash list mutated during a long editor session
/// can't make us drop the wrong entry. No-op (ok) when it's already gone.
Future<GitResult<void>> stashDropByHash(String repo, String hash) async {
  final list = await listStashes(repo);
  if (!list.ok) return GitResult.err(list.error ?? 'listStashes failed');
  final match = list.data!.where((s) => s.hash == hash).toList();
  if (match.isEmpty) return const GitResult.ok(null); // already dropped
  return stashDrop(repo, index: match.first.index);
}

Future<GitResult<String>> stashShow(String repo, {int index = 0}) async {
  // `-c diff.binary=false`: same immunity as [_kDiffCmd] — `-p` output is a
  // textual patch body and must never inline a binary payload.
  final r = await _git(repo, [
    '-c',
    'diff.binary=false',
    'stash',
    'show',
    '-p',
    'stash@{$index}',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(r.stdout.toString());
}

/// List files touched by a stash, with per-file add/del counts.
/// Uses --numstat (tab-separated `adds<TAB>dels<TAB>path`). Binary files
/// render as `-<TAB>-<TAB>path` in numstat.
Future<GitResult<List<StashFileStat>>> stashFiles(
  String repo, {
  int index = 0,
}) async {
  // `--no-renames` is load-bearing, not hygiene: diff.renames is ON by default
  // for `stash show`, which renders a renamed entry as the single bogus path
  // `old => new`. Pinning no-renames makes that shape unrepresentable — a
  // rename splits into a clean delete+add pair instead.
  final r = await _git(repo, [
    'stash',
    'show',
    '--numstat',
    '--no-renames',
    'stash@{$index}',
  ]);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  final out = <StashFileStat>[];
  for (final raw in r.stdout.toString().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final addsRaw = parts[0].trim();
    final delsRaw = parts[1].trim();
    final path = parts.sublist(2).join('\t').trim();
    if (path.isEmpty) continue;
    final binary = addsRaw == '-' || delsRaw == '-';
    out.add(
      StashFileStat(
        path: path,
        adds: binary ? 0 : (int.tryParse(addsRaw) ?? 0),
        dels: binary ? 0 : (int.tryParse(delsRaw) ?? 0),
        binary: binary,
      ),
    );
  }
  return GitResult.ok(out);
}

/// Parses `git worktree list --porcelain`. Each worktree is a block of
/// key-value lines separated by a blank line. Keys: worktree, HEAD, branch,
/// bare, detached, locked. Blank-only lines terminate the block.
Future<GitResult<List<WorktreeData>>> listWorktrees(String repo) async {
  final r = await _git(repo, ['worktree', 'list', '--porcelain']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());

  final worktrees = <WorktreeData>[];
  String? curPath;
  String? curHead;
  String? curBranch;
  bool curDetached = false;
  bool curLocked = false;

  void flush() {
    if (curPath == null) return;
    worktrees.add(
      WorktreeData(
        path: curPath!,
        head: curHead ?? '',
        branch: curBranch,
        // First entry from `worktree list` is always the main repo.
        isMain: worktrees.isEmpty,
        isDetached: curDetached,
        isLocked: curLocked,
      ),
    );
    curPath = null;
    curHead = null;
    curBranch = null;
    curDetached = false;
    curLocked = false;
  }

  for (final line in r.stdout.toString().split('\n')) {
    if (line.isEmpty) {
      flush();
      continue;
    }
    if (line.startsWith('worktree ')) {
      curPath = line.substring('worktree '.length).trim();
    } else if (line.startsWith('HEAD ')) {
      curHead = line.substring('HEAD '.length).trim();
    } else if (line.startsWith('branch ')) {
      // refs/heads/main → main
      final ref = line.substring('branch '.length).trim();
      curBranch = ref.startsWith('refs/heads/')
          ? ref.substring('refs/heads/'.length)
          : ref;
    } else if (line == 'detached') {
      curDetached = true;
    } else if (line.startsWith('locked')) {
      curLocked = true;
    }
  }
  flush();

  // Enrich with dirty-file counts per worktree in parallel — each probe
  // is its own `git status` process, so running them concurrently keeps
  // latency flat as desk count grows.
  final statusResults = await Future.wait(
    worktrees.map((wt) async {
      try {
        final s = await _git(wt.path, ['status', '--porcelain']);
        if (s.exitCode != 0) return 0;
        return s.stdout
            .toString()
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .length;
      } catch (_) {
        return 0;
      }
    }),
  );
  for (var i = 0; i < worktrees.length; i++) {
    final wt = worktrees[i];
    worktrees[i] = WorktreeData(
      path: wt.path,
      head: wt.head,
      branch: wt.branch,
      isMain: wt.isMain,
      isDetached: wt.isDetached,
      isLocked: wt.isLocked,
      dirtyFileCount: statusResults[i],
    );
  }

  return GitResult.ok(worktrees);
}

/// Ensures `.manifold/` is in `.git/info/exclude` so app-managed
/// directories (desks, wick index) are never tracked by git. Uses the
/// repo-local exclude mechanism (not .gitignore) to avoid dirtying the
/// working tree. Idempotent; non-fatal on failure.
Future<void> ensureManifoldExcluded(String repo) async {
  try {
    // Routed through the geometry memo (and the shared exec layer, so it
    // inherits the non-interactive env + semaphore) — the common-dir is
    // static for this repo path.
    final gitDirResult = await _revParseGeometry(repo, [
      'rev-parse',
      '--git-common-dir',
    ]);
    if (gitDirResult.exitCode == 0) {
      final gitDir = (gitDirResult.stdout as String).trim();
      final absGitDir = p.isAbsolute(gitDir) ? gitDir : p.join(repo, gitDir);
      final excludeFile = File(p.join(absGitDir, 'info', 'exclude'));
      final existing = await excludeFile.exists()
          ? await excludeFile.readAsString()
          : '';
      if (!existing.split('\n').map((l) => l.trim()).contains('.manifold/')) {
        await excludeFile.writeAsString(
          '${existing.trimRight()}\n.manifold/\n',
        );
      }
    }
  } catch (error) {
    DiagnosticsState.instance.recordCommandLifecycleEvent(
      type: 'failure',
      command: 'manifold.exclude_write',
      errorCode: 'exclude.write_failed',
      message: error.toString(),
    );
  }
}

/// Creates a worktree at the given path for the given branch.
/// Ensures `.manifold/` is in `.git/info/exclude` so app-managed desk
/// directories are never tracked by git.
Future<GitResult<String>> addWorktree(
  String repo,
  String worktreePath,
  String branch, {

  /// When true, creates a new branch from HEAD at the given name alongside
  /// the worktree. Uses `git worktree add -b <branch> <path>`.
  bool createNewBranch = false,
}) async {
  await ensureManifoldExcluded(repo);

  final args = createNewBranch
      ? ['worktree', 'add', '-b', branch, worktreePath]
      : ['worktree', 'add', worktreePath, branch];
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return GitResult.ok(worktreePath);
}

Future<GitResult<void>> removeWorktree(
  String repo,
  String worktreePath, {
  bool force = false,
}) async {
  final args = ['worktree', 'remove'];
  if (force) args.add('--force');
  args.add(worktreePath);
  final r = await _git(repo, args);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<void>> pruneWorktrees(String repo) async {
  final r = await _git(repo, ['worktree', 'prune']);
  if (r.exitCode != 0) return GitResult.err(r.stderr.toString().trim());
  return const GitResult.ok(null);
}

Future<GitResult<String>> getRepositoryXrayFingerprint(String repo) {
  return computeRepositoryXrayFingerprint(repo, getRepositoryStatus, _git);
}

Future<GitResult<RepositoryXraySnapshotData>> getRepositoryXray(
  String repo, {
  bool forceRefresh = false,
  XrayCardStrings cardStrings = const EnglishXrayCardStrings(),
}) {
  return buildRepositoryXraySnapshot(
    repo,
    forceRefresh: forceRefresh,
    statusLoader: getRepositoryStatus,
    probe: _git,
    cardStrings: cardStrings,
  );
}
