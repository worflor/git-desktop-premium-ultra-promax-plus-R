# Test-Hardening Round 3 — Crash Consistency, Concurrency Chaos, Hostile Gitconfig (2026-07-09)

> **2026-07-10 RESOLUTION PASS — ALL FINDINGS FIXED AT ROOT.** Every OPEN finding below
> (T1–T4, C1–C3, G1–G10) plus the second-wave findings (R1–R5, below) was fixed in lib/
> and its pinned test permanently ARMED as a regression guard; laws whose polarity the
> fixes legitimately inverted were rewritten to assert the fixed contract (see
> "Resolution pass" at the end). One intentional skip survives:
> `_aiModelCacheUnreachableSkip` (library-private, network-gated; save path rides
> `writeFileAtomic` by review). The historical bodies below are the record; the
> resolution section is authoritative for current status.

Three NEW bug classes added to the fuzz suite, each structurally invisible to the prior
harness (which was single-threaded, instantaneous, clean-environment, and whole-write):

1. **Crash consistency** — `test/fuzz/torn_write_crash_consistency_test.dart` +
   `test/support/io_faults.dart`. A journaling `IOOverrides` records every byte a store
   writes, then replays **every crash prefix** (per-op, per-byte-cut) into a fresh dir and
   asserts `load()` lands on old-state or new-state — never garbage, never a wipe.
2. **Concurrency chaos** — `test/fuzz/concurrency_chaos_test.dart` +
   `test/support/chaos.dart`. The app's first true-concurrency suite: seeded-jitter racing
   of real op pairs on scratch repos with invariant oracles (linearizability-lite). The git
   semaphore is a *throttle, not a mutex* — nothing serializes two logical ops on one repo.
3. **Hostile gitconfig differential** — `test/fuzz/hostile_gitconfig_differential_test.dart`
   + `test/support/hostile_config.dart`. Three techniques: (A) behavioral differential
   (one repo, config-swapped arms, parsed output must be invariant), (B) argv-pinning lint
   via the GitSpawn seam (makes the whole class unrepresentable once flags are pinned),
   (C) synthetic hostile-stdout injection for axes unproducible portably (gpg signatures).

House conventions throughout: laws not goldens; genuine bugs pinned as
`_knownFinding*Skip` tests that go red when unskipped; `MANIFOLD_FUZZ=<n>` scaling;
corpus + seed reproduction. Every finding below was **unskip-verified** to fail for its
documented reason. Suites are OS-portable and run on Windows and WSL2 Linux.

**Status legend:** `OPEN` = documented + pinned by test, not fixed. `PIN` = intentional
documentation of a hole (test passes by asserting the hole exists). `OBSERVATION` =
behavior within the store's documented contract, recorded so it isn't "found" again.

---

## Summary table

| # | Severity | File | Bug | Status | Documenting test |
|---|----------|------|-----|--------|------------------|
| T1 | HIGH | settings_store.dart:693, ai_settings_store.dart:282, review_ratchet_store.dart:66, local_telemetry_store.dart:25 | Non-atomic snapshot persist — crash mid-write destroys prior state (B20 class) | OPEN | torn_write_crash_consistency_test.dart |
| T2 | HIGH | ai_settings_store.dart:256-277 | `load()` re-persists defaults over a corrupt file — destroys evidence + user data | OPEN | torn_write_crash_consistency_test.dart |
| T3 | MED | nudge_ledger.dart:156-165 | Torn append tail swallows the NEXT record (missing last-byte guard its sibling has) | OPEN | torn_write_crash_consistency_test.dart |
| T4 | HIGH | ai_audit_store.dart:112 (+ same shape command_telemetry_store.dart:346) | Torn multibyte UTF-8 bricks the log: strict `readAsLines()` throws on reads AND writes until manual deletion | OPEN | torn_write_crash_consistency_test.dart |
| T5 | OBSERVATION | engram_file_index_cache.dart:137-138 | Windows delete-then-rename window can LOSE the cache file (benign-by-contract: empty cache) | OBSERVATION | torn_write_crash_consistency_test.dart |
| C1 | HIGH | desk_pr_store.dart:220-234 + manifold_refs.dart:312-328 | `create()` has NO CAS on a fresh ref (`oldSha: null` → unconditional update-ref): two concurrent creates both "succeed", one silently clobbered | OPEN | concurrency_chaos_test.dart |
| C2 | MED | git.dart:4837-4845 (applyFileStaging) + 4791 (applyPatch bypass) | Concurrent per-file staging collides on index.lock with NO retry (~60% repro) — staged selection silently fails | OPEN | concurrency_chaos_test.dart |
| C3 | MED | shadow_coupling_cache.dart:104-129 | Unlocked load→mergeWith→save cycle loses updates, violating mergeWith's "never regress" contract | OPEN | concurrency_chaos_test.dart |
| C4 | PIN | git.dart:4768-4829 + repository_state.dart:261-270 | `applyPatch` never bumps `gitMutationsInFlight` → GitDirWatcher refresh can land mid-apply (watcher-pause hole, deterministic pin) | PIN | concurrency_chaos_test.dart |
| G1 | HIGH | git.dart:1141 (getRepositoryStatus) | porcelain-v2 path never un-C-quoted: non-ASCII filename renders as `"caf\303\251.txt"` — can't stage/diff | OPEN | hostile_gitconfig_differential_test.dart |
| G2 | MED | git_diff_paths.dart (patchSidePath) | `diff.mnemonicPrefix=true` → filePath becomes `w/…` (no `--src/--dst-prefix` pinning) | OPEN | hostile_gitconfig_differential_test.dart |
| G3 | HIGH | git.dart:2214-2386 diff family + diff_models.dart:346 | `color.diff=always` → ANSI-prefixed +/- lines misclassified; whole diff view + line staging break (no `--no-color`/`--no-ext-diff`) | OPEN | hostile_gitconfig_differential_test.dart |
| G4 | MED | git.dart:1358/1372 (bulkGetCommitDetails) | `--raw`/`--numstat` paths never un-C-quoted → mojibake file lists per commit | OPEN | hostile_gitconfig_differential_test.dart |
| G5 | MED | file_coupling.dart:1069 | C-quoted raw path × `replaceAll('\\','/')` → phantom node `caf/303/251.txt` poisons the co-change graph | OPEN | hostile_gitconfig_differential_test.dart |
| G6 | MED | git.dart:6496 (stashFiles) | `diff.renames` → `orig.txt => renamed.txt` taken VERBATIM as one path | OPEN | hostile_gitconfig_differential_test.dart |
| G7 | MED | content-diff invocations | argv lint: missing `--no-color` | OPEN | hostile_gitconfig_differential_test.dart (Technique B) |
| G8 | MED | content-diff invocations | argv lint: missing `--no-ext-diff` (`diff.external` replaces the diff body entirely) | OPEN | hostile_gitconfig_differential_test.dart (Technique B) |
| G9 | MED | commit-log invocations | argv lint: missing `--no-show-signature` | OPEN | hostile_gitconfig_differential_test.dart (Technique B) |
| G10 | MED | git.dart:1218 (_parseCommitLogLines) | `log.showSignature=true` gpg lines shift the fixed 8-line window → garbage hashes/authors (synthetic injection) | OPEN | hostile_gitconfig_differential_test.dart (Technique C) |

**Positive results (armed, passing):** atomic stores (AiApiKeysStore, ShadowCouplingCache
save) never expose torn bytes; CommandTelemetryStore's torn-tail guard holds;
cross-file blast radius is zero; DeskPrStore `_mutate` retrying-CAS loses nothing under
8-way concurrency; sequential id alloc stays monotonic; the subprocess semaphore ceiling
holds under 20-way load; disjoint concurrent write/stage ops commute safely; blame /
branches / reflog / `-z` invocations are config-invariant across all seven axes.

**Notable non-finding:** `diff.noprefix=true` self-repairs in the full `parseUnifiedDiff`
pipeline (the `+++` line recovers the path before any body line is emitted) — initially
pinned as a finding, unskip-verification showed zero divergence, now an armed invariance
law with an inline note.

---

## Converging fix shapes (for the resolution pass — NOT applied yet)

- **T1/T2**: one shared atomic-snapshot write helper (tmp + flush + rename — the
  AiApiKeysStore choreography) swept through the four non-atomic stores; AiSettingsStore
  additionally stops re-persisting defaults from `load()`.
- **T3**: copy CommandTelemetryStore's last-byte probe into NudgeLedger.
- **T4**: tolerant line reads (`utf8.decode(allowMalformed: true)` or utf8_exact/json_safety
  readers) in ai_audit_store and command_telemetry_store loaders.
- **C1**: pass the zero-oid as `oldSha` for fresh-ref creates so the CAS actually rejects
  the loser.
- **C2/C4**: route `applyPatch` through the gated `_git` path (semaphore + index.lock retry
  + `gitMutationsInFlight`), which fixes the collision AND the watcher-pause hole at once.
- **C3**: per-repo-key async mutex around the shadow-cache read-modify-write.
- **G1/G4/G5**: run paths through the existing `unCQuoteGitPath` (git_diff_paths.dart is
  already the single source of truth; these three parse sites just never call it).
- **G2/G3/G6-G10**: argv pinning at the invocation layer — `--no-color --no-ext-diff`
  on the diff family, `--no-show-signature` on the log family, `--src-prefix=a/
  --dst-prefix=b/` (or `-c diff.mnemonicPrefix=false`), `--no-renames` on `stash show`.
  The Technique-B lint laws then keep the class unrepresentable: any future unpinned
  invocation fails the lint.

## Reproduction

- Default: `flutter test test/fuzz/<suite>_test.dart`
- Deep: `MANIFOLD_FUZZ=3 flutter test test/fuzz/<suite>_test.dart`
- Any finding: flip its `_knownFinding*Skip` const to `false` → red with the documented
  mechanism. Seeds default 0x5EED; failures print seed + tape and persist to test/corpus/.
- Linux: sync the WSL worktree (`/root/manifold-osdiff`, wsl_runner.dart mechanics — sync
  `lib/`, `test/support/`, `test/fuzz/`) and run the same three files under
  `PATH=/root/flutter/bin:$PATH`.

---

## Second wave (2026-07-10) — upgrades that found more

Four suite upgrades built after a first-principles self-review, and what they caught:

- **Deterministic barrier scheduler** (`test/support/git_barrier.dart` +
  `test/fuzz/deterministic_interleaving_test.dart`): holds subprocess spawns at the
  GitSpawn seam, turning probabilistic races into 100%-reproducible schedules; plus
  isolate-based cross-process simulation (each `Isolate.run` gets its own statics —
  a faithful second app process).
  - **R1 (SEVERE, deterministic):** `allocSequentialId` fresh-ref path used
    `updateRef(oldSha: null)` (unconditional) and skips the remote reservation offline —
    two processes both allocated id 1 every run. Duplicate desk/PR ids.
- **Ground-truth anchors** in the gitconfig differential (absolute expected-content
  assertions — the differential alone is blind to "both arms wrong the same way"):
  - **R2 (HIGH, shipped broken):** `listReflog` returned `[]` on every repo, always —
    its format used `%09`, which is NOT a pretty-format escape (`%x09` is); zero tabs →
    every line dropped. Both differential arms agreed on `[]`, so only an anchor saw it.
  - **R3 (HIGH, shipped broken, found during the fix):** `searchCommits` had the same
    `%09` bug — commit search returned empty results in production.
- **Power-loss crash model** (flush-aware write-reordering in `io_faults.dart`):
  confirmed `flush:true` tmp+rename stores are genuinely power-loss durable;
  - **R4 (MED):** `EngramFileIndexCache` tmp write was unflushed (power-loss surface)
    on top of its delete-then-rename Windows loss window (T5). Empirical probe: Dart
    `File.rename` DOES atomically replace on Windows — delete-first was never needed.
  - **R5 (MED, by inspection + new seam):** `PaletteState._loadUsageSync` committed four
    maps sequentially with eager casts — a wrong-typed later field left a silent franken
    half-load (swallowed catch).
- **Repo-shape × surface sweep** (`test/fuzz/repo_shape_surface_test.dart`, 40 cells):
  all clean — linked worktrees (`.git` as a FILE), submodules, detached HEAD, orphan,
  unborn all parse correctly. Good news, now pinned.

## Resolution pass (2026-07-10) — fix shapes as landed

- **`lib/backend/atomic_write.dart` (new):** `writeFileAtomic`/`writeFileAtomicString` —
  tmp + `flush:true` (real fsync) + rename (atomic replace both OSes; bounded retry on
  Windows sharing violations; on final failure target intact, tmp left). Swept through
  SettingsStore, AiSettingsStore (+4 prompt files), ReviewRatchetStore,
  LocalTelemetryStore, the ai.dart model cache, and EngramFileIndexCache (which also
  lost its delete-first step) → T1, T5, R4 gone; LAW 3 tightened to strict {S1,S2}.
- **AiSettingsStore.load:** returns defaults in memory on parse failure, never
  re-persists over the corrupt file (T2).
- **NudgeLedger:** CommandTelemetryStore's last-byte torn-tail probe copied in (T3).
- **AiAuditStore/CommandTelemetryStore loaders:** lenient `utf8.decode(allowMalformed)`
  + manual split — a torn multibyte tail degrades to one skipped line (T4).
- **ShadowCouplingCache.save:** per-key serialized save-as-merge — under the lock it
  re-loads disk state and folds the incoming data iff same `headHash` (a new head
  supersedes, matching `mergeWith`'s freshness policy) (C3).
- **applyPatch/applyFileStaging:** `_gitRaw`'s choreography extracted to
  `_runGitChoreographed` (semaphore, mutation counting, index.lock retry) + a
  stdin-capable `_gitRawStdin`; `apply` classifies as mutating. `_blobBytes` wrapped in
  the semaphore. Closes C2, C4/D1 (watcher-pause + unretried-lock) in one stroke.
- **Zero-oid CAS:** "create" can no longer be expressed as an unconditional
  `update-ref` — DeskPrStore/DeskIssueStore creates and `allocSequentialId` pass the
  zero oid when expecting absence; alloc retries a lost CAS (bounded, jittered) so the
  loser takes the next id (C1/D2, R1).
- **Parsers/argv:** `unCQuoteGitPath` at the status (v2+v1), bulk-details, and
  file-coupling parse sites (G1, G4, G5); `--no-renames` on `stash show` (G6);
  `--no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/` on every diff body,
  `--no-ext-diff` on `git show`, `--no-show-signature` on every commit log (G2, G3,
  G7–G9) — with the argv-lint laws keeping the class unrepresentable; `%09` → `%x09` in
  `listReflog` AND `searchCommits` (R2, R3), pinned by anchors;
  `_parseCommitLogLines` additionally skips `gpg:` record-start lines (G10,
  defense-in-depth).
- **PaletteState:** parse extracted to pure `@visibleForTesting parsePaletteUsage`
  (throws on any malformed field — all-or-nothing), maps committed together (R5).

Verification: all five fuzz suites green at default and MANIFOLD_FUZZ=3, concurrency
suites 3/3 stable, whole-app analyze clean, full suites green on Windows and WSL2 Linux
(counts in the session record).

## Cross-OS closure wave (2026-07-10, full-suite gauntlet fallout)

Running the FULL suite on both OSes after the resolution pass surfaced one final
wave — every item root-fixed and re-verified green on Windows AND WSL2 Linux:

- **W1 (LIB, Linux product bug):** `GitDirWatcher._onRawEvent` filtered move events
  by source basename only; git updates HEAD via `HEAD.lock → HEAD` rename, which
  Linux inotify delivers as ONE move event with the `.lock` on the path side — so
  **checkouts were invisible to the watcher on Linux** (stale UI). Fix: accept a
  `FileSystemMoveEvent` whose DESTINATION basename matches.
- **W2 (LIB, Linux/git-version product bug):** `continueRebase` — git 2.43 (Ubuntu
  LTS) opens an EDITOR for a conflicted pick's `--continue` (empirically verified;
  newer git doesn't), so headless it died at the current step ("Standard input is
  not a terminal") instead of halting at the next conflict. Fix: scoped
  `GIT_EDITOR=true` (git launches editors via its own sh, where `true` always
  resolves — PATH-independent).
- **W3 (LIB, introduced by this round's own fix, caught by the gauntlet):**
  `writeFileAtomic` used a FIXED `<target>.tmp` name — two PROCESSES writing the
  same store raced the rename (loser: errno 2). Fix: unique `<target>.<pid>.<seq>.tmp`;
  `AiApiKeysStore` (same fixed-name pattern, pre-existing) swept onto the helper
  with a `beforeRename` permissions hook.
- **W4 (tests, cross-OS):** test-written git hooks lacked the executable bit —
  POSIX git silently SKIPS them (git-for-Windows execs via sh regardless), so all
  hook scenarios were vacuously green on Windows and red on Linux (8 tests across
  commit_staging + merge_session). Fix: chmod +x helper at every hook-write site.
- **W5 (tests, portability):** codex live probe now gates on RUNNABILITY not PATH
  presence (WSL interop exposes the broken Windows npm shim); the orrery real-data
  test derives the repo root from CWD instead of a hardcoded `C:/` path; the
  permit-release-on-timeout test uses `git daemon --port=0` (blocks forever) since
  a fast Linux `rev-parse` finished before the deadline await began, skipping the
  timeout branch entirely.
- **Theme ratchets:** the orrery feature's 3 post-baseline violations converted to
  tokens (`AppRadii`/`AppMotion`/`CircleBorder`) — counters back at baseline, no
  baseline raised.
- **Load-flake accounting:** every remaining full-suite failure (19 on Windows, 6
  overlapping on Linux) passes in isolation at `--concurrency=1` — the documented
  timing-budget/subprocess-storm contention class, not code defects.

Final verification: whole-app `flutter analyze` clean; targeted suites for every
fix green on Windows (+52) and WSL2 Linux (+75 ~2); the six new fuzz suites green
at default and MANIFOLD_FUZZ=3 on both OSes.

## Feature-coverage round (2026-07-10) — three-scout sweep + six fix/coverage waves

After the cross-OS closure, three read-only Sonnet scouts mapped every untested surface
(UI flows, app-state wiring, backend public API). Six Opus waves then closed the gaps at
root — 3 real bugs fixed, 1 already-fixed bug verified+pinned, plus new guards:

- **SECRET GATE (real defensive hole).** `isSensitivePath`/`detectLikelySecretInPrompt`
  (ai.dart) — the gate stopping user secrets from reaching a third-party LLM — had 12+
  false-negatives. Added SSH DSA/ECDSA keys, `.git-credentials`, `.npmrc`/`.pypirc`,
  `.netrc`, `.pgpass`, docker registry auth (scoped, not blanket config.json), PuTTY
  keys, GnuPG secret keyring; token regexes for Stripe **live** keys (`sk_live_` —
  underscore the old `sk-` dash-pattern could never match), GitLab PAT, npm, PGP block,
  Slack app/refresh. Fixed the `.env.example` false-positive. `test/backend/secret_gate_test.dart`
  (154 tests + no-false-positive fuzz law).
- **HISTORY-SURGERY CONFIRM GATE (real bug, high stakes).** `SurgeryState.confirmationComplete`
  used `.trim().toUpperCase() == 'PURGE'` — accepted `"purge"`, `" PURGE "`, `"PURGE\n"`
  as the sole barrier before an irreversible history rewrite + force-push. Fixed to exact
  `== 'PURGE'`. Force-push loop verified already-correct (separate pushed/errors), now pinned.
  `test/features/history_surgery/surgery_state_test.dart` (21 tests, gate truth-table).
- **UNBOUNDED CACHE LEAK (real bug).** `FileCouplingState`/`RepoEmbeddingState`/`LogosGitState`
  defined `invalidateAllExcept` but nothing called it (only xray was wired) — per-repo
  coupling/embedding/Logos artifacts accumulated for the session. Centralized eviction in
  `workspace_shell.evictInactiveRepoCaches` (all four move together — "forgot a store"
  unrepresentable). `test/app/per_repo_cache_eviction_test.dart` (red→green proof).
- **PALETTE build-phase bug** — already fixed at HEAD (phase-aware `notifyListeners`
  deferral); verified load-bearing, added scoring/selection/usage coverage, rewrote the
  stale finding comment into an armed guard.
- **CONFLICT-RESOLUTION logic extracted** from MergeConflictEditor build closures into
  pure `applyConflictResolution`/`resolveEasyConflicts`; byte-exact "no choice corrupts or
  leaks a marker" invariant incl. CRLF + no-trailing-newline.
- **IRREVERSIBLE GIT MUTATIONS** (discard/stash/push/worktree/tag/cherry-pick/revert) —
  28 tests, no bugs found; headline guard: `--force-with-lease` proven to reject on a
  moved remote (never silently downgrades to a clobbering force). failNth choreography
  sweep confirms no half-deleted stashes / orphaned worktree state.
- **CLOCK SEAM** — new `lib/backend/clock.dart` (`Clock`/`SystemClock`, test-only
  `FakeClock`). Migrated the 2s head cache, 60min shadow freshness, telemetry retention,
  and ai.dart 30min/24h provider caches to injectable time; exact-boundary tests run in
  zero wall-clock. Pure refactor (production = SystemClock = DateTime.now()). Also pinned
  the previously-untested telemetry p50/p95 aggregation. Dartdoc steers future TTLs to the
  seam. Un-migrated (future pass): worktree_state 3s, ai_settings 45s, thermal_accumulator,
  workspace_shell debounces.

Known follow-ups flagged, not done: `cloneRepository`/`startInteractiveRebase` spawn via
`_spawnStart` (startOverride) so GitFaultScript can't crash-inject them — needs a
Process-start fault seam; forge CLIs (gh/glab) have no spawn-override seam so their ~35
mutating functions remain untestable cheaply; AI feature entry points (generateCommitMessage/
runAsk/runMuse/…) covered at their `*ForTesting` seams but not end-to-end.

## Cross-OS closure — feature-coverage round (2026-07-10, full-suite gauntlet)

The full Windows + WSL2 gauntlet after the feature-coverage waves surfaced genuine
issues Windows had masked (leak_tracker's GC-forced detection is timing-sensitive, so
undisposed dart:ui resources only tripped on Linux). All root-fixed, re-verified on both:

- **orrery TextPainter leak (LIB):** `orrery_timeline.dart:_paintCaption` built a fresh
  `TextPainter` per caption per repaint and never disposed it. `tp.dispose()` after paint.
- **orrery Image/Picture leaks (tests):** the four orrery preview tests created `ui.Image`
  (via `boundary.toImage`/`recorder.endRecording().toImage`) and `Picture` objects and
  never disposed them (21 undisposed Images flagged). Disposed every image + picture after
  its bytes are read.
- **encodeBranch lone-surrogate assert (LIB):** `desk_pr_store.encodeBranch`'s strict
  `decodeBranch(encoded) == branch` round-trip assert crashed on a lone unpaired surrogate
  (`0xD83D`) — which UTF-8 legitimately can't represent, so it degrades to U+FFFD. The test
  contract is "degrades WITHOUT crashing." Fixed to compare against the UTF-8-normalized
  input (`utf8DecodeExact(utf8.encode(branch), allowMalformed: true)`): identity for every
  well-formed name (injectivity guarantee unchanged), graceful for the malformed case.
- **refFor numeric contract (test adaptation):** the typed-ref-algebra effort tightened
  `LiveManifoldRef.issue(id)` to reject `id <= 0` ("issue ids start at 1" — illegal state
  unrepresentable). The pre-existing fuzz test still fuzzed `[-1M, 1M]` and expected success
  at 0. Narrowed the fuzz domain to the real `id >= 1` and added an explicit "refFor rejects
  a non-positive id" pin for the tightened precondition.
- **WSL sync harness:** the sync script copied `lib/` + `test/` but not `pubspec.yaml`/
  `pubspec.lock`, so a parallel effort's new `analyzer` dependency was absent on Linux and
  `source_laws_test.dart`/`law_corpus.dart` failed to COMPILE. Sync now carries pubspec.

Load-flake accounting unchanged: the remaining full-run failures on both OSes
(theme ratchet under concurrent file-handle contention, subprocess-storm backend tests,
jank wall-clock budgets) all pass in isolation at `--concurrency=1`.

**Definitive run (all fixes in):** Windows full `-22`, all confirmed load-flakes (pass at
`--concurrency=1`). WSL2 Linux full `-3` → state_model + gitea_api 2s-delay (both load,
pass serialized) + the split-pill verdict-badge image leak (now fixed). Every genuine
cross-OS failure root-fixed and re-verified green on both OSes; nothing remains but
documented concurrency contention.

## External-review findings — SHA-256 + atomic durability (2026-07-10)

A Manifold code review (codex/gpt-5.6-terra) flagged two real defects in shared
primitives; both root-fixed and verified on Windows + WSL2 Linux, plus a third same-class
gap found during the fix:

- **Typed OID layer excluded SHA-256 repos.** `manifold_ref_types.dart:_isOid` hard-required
  40 hex; SHA-256 repos have 64-hex object names, so every Manifold ref op (writeBlob/mkTree/
  commitTree/resolveRef/listRefs) threw `ArgumentError` on valid git output. The load-bearing
  subtlety: git's null OID is width-matched (64 zeros in a sha256 repo), and `update-ref`/
  `--force-with-lease` REJECT a wrong-width zero — so the zero-OID create-CAS my REFS work
  relies on was also broken. Fixed: `_isOid` accepts 40 or 64 hex; `Oid.zeroFor(sample)`
  mints a width-correct null OID; `updateRef` normalizes a zero `oldSha` to the companion
  `newSha`'s width at the chokepoint (create-CAS auto-correct on both formats without callers
  knowing the algorithm); the alloc + reconcile leases likewise sized. Proven by a real
  `--object-format=sha256` ScratchRepo driving DeskPrStore.create→read→CAS-reject end-to-end.
- **atomic_write overstated crash durability.** `writeFileAtomic` flushed the temp file and
  renamed but never fsync'd the parent directory, while its dartdoc claimed power-loss
  durability — false on ext4-class filesystems where a rename persists only on a dir fsync.
  Fixed (delivered, not just documented): a best-effort POSIX parent-dir fsync via dart:ffi
  (`open(dir,O_RDONLY)`→`fsync`→`close` through `DynamicLibrary.process()`), Windows no-op
  (NTFS journals rename metadata), fully swallowed on failure (rename already succeeded).
  dartdoc now states the precise three-part guarantee. FFI path verified rc=0 on real ext4
  under WSL2; clean no-op on Windows.
- **Blame parser (same class, found during fix).** `git.dart:4107` blame porcelain regex
  hardcoded `[0-9a-f]{40}`, so blame silently returned empty in every sha256 repo. Widened
  to `{40,64}` (trailing space delimits the run); pinned by a SHA-1/SHA-256 blame test.

Verification: whole-app analyze clean; new tests (OID types, sha256 end-to-end, blame both
formats, durability) + the crash-consistency suite green on Windows (`+40`) and WSL2 Linux
(`+100` incl. ref-namespace + both desk stores). One sanctioned edit outside the OID layer:
source_laws L1's "FFI confined to win_job_object.dart" allowset gained atomic_write.dart.

## Manifold self-review pass (2026-07-10) — dogfooding `manifold review`

Ran Manifold's own AI code review (`manifold review`, codex/gpt-5.6-terra, IPC bridge to the
running GUI) over the whole working tree. Verdict Block, 1 finding + 1 observation — both
root-fixed, each with Fable consulted for the judgment call before implementing:

- **BLOCK — analyzer dev-dep broke the declared SDK floor.** The source-law effort added
  `analyzer: ^10.0.1` (needs Dart ^3.9), but pubspec declared `sdk: >=3.3.0`, making
  `flutter pub get` unsatisfiable on 3.3–3.8. Fable's call: raise the floor (a) — this is an
  app (`publish_to: none`), not a consumed library; the Flutter toolchain pins Dart, Flutter
  3.22 already ships Dart 3.4, so the 3.3 floor was archaeology. Isolating the dep into a
  sub-package (c) would drop the source-law suite out of the default `flutter test` sweep
  (rot); downgrading (b) risks parsing new syntax with an old analyzer. Fixed: `sdk:
  >=3.9.0 <4.0.0`, `flutter: >=3.35.0`, README synced. `pub get` resolves.
- **OBSERVATION — palette usage persistence was a torn-write path.** `_persistUsage` wrote
  via bare `writeAsString` fire-and-forget on every command execution. Fable's reframe: the
  fsync-latency worry is a mirage (already async on the IO pool, UI never waits), and the
  real bug is that fire-and-forget-per-execution lets two writes interleave and tear the file
  WITHOUT a crash. Fixed: route through the shared `writeFileAtomic` + a fixed-window
  coalescing debounce (≤1s staleness) + single-flight drain + flush-on-dispose (no
  "atomic-lite" variant — that re-adds the bug class as API surface). `dispose` made
  idempotent. Pinned by a new atomic-persist round-trip test.

Fable was consulted one-shot (non-agentic, advice-only) per fix; the orchestration and
implementation were done here. Re-review confirms clean.

### Re-review → clean, + observation follow-ups (2026-07-11)

The first two `manifold review` runs re-reported the (already-fixed) findings because the
long-running GUI instance served a STALE diff — a genuine footgun in the CLI→GUI bridge
(the app's cached working-tree view doesn't refresh on working-tree edits, since the git
watcher only watches `.git/`). Workaround: relaunch the app (fresh process re-reads the
working tree), then re-review. The fresh review came back **Ready | 82, zero findings** —
the code was correct all along; the tool was showing stale data.

Two advisory OBSERVATIONS (not defects) closed for thoroughness:
- **Typed-ref migration compiles everywhere** — confirmed by a clean whole-app
  `flutter analyze` (no call site outside the touched files passes a bare `String` where a
  `Commitish`/`Oid`/`MetadataRemote` is now required).
- **Commit-log argv pins centralized** — `--no-show-signature` was a bare literal at 5
  git.dart `git log` sites; extracted to a shared `_kCommitLogPins` const (mirroring the
  existing `_kDiffContentPins`) so a new commit-log call site spreads one source of truth.
  Behavior-identical (same values); git.dart analyzes clean and the argv-lint + parser laws
  still pass.
