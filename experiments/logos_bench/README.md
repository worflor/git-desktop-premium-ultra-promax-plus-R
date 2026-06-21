# logos_bench — cold-build scaling harness

Measures `LogosGit.buildFromStats` wall-clock + per-phase scaling under
plain `dart` (no Flutter runtime). lib/** is never touched.

## Run

    dart --packages=experiments/logos_bench/package_config.json \
         experiments/logos_bench/headline.dart

(run from the repo root)

## Why a custom package_config + flutter_stub

The orchestrator brief claimed the buildFromStats import-closure is
Flutter-free. It is NOT: `logos_git.dart -> file_coupling.dart ->
correlatedness_hunk_sort.dart -> logos_hunks.dart -> engram_bootstrap.dart`
imports `package:flutter/services.dart show rootBundle`, which transitively
pulls `dart:ui` and fails under plain `dart`. The closure also reaches
`diagnostics_state.dart` (foundation.dart) and the `shared_preferences`
pub dep (services.dart MethodChannel).

`flutter_stub/` is a minimal pure-Dart `package:flutter` providing only the
compile-time symbols that closure references (rootBundle, ChangeNotifier,
MethodChannel, compute, the meta annotations, kDebugMode). Every
platform/asset method THROWS if called — but buildFromStats never calls
them, so this is a pure link-time satisfier, not a behavioural change.
`package_config.json` here is a copy of the app's config with the `flutter`
entry redirected to `flutter_stub/`.

If the engine is ever refactored so logos_git's closure genuinely avoids
Flutter, drop the stub and point `--packages` at the app's own
`.dart_tool/package_config.json`.

## scoreloop_candidates.dart — candidate-assembly isolation

Isolates the per-node candidate-Set assembly (logos_git.dart:2640-2711),
the hypothesized superlinear culprit in scoreLoop. Reproduces the exact
pre-loop precompute (sorted nodePaths, pathToId, pathSegments, dirIndex,
transportRoles, transportSeedIndex) and the exact assembly block using only
public symbols (TransportRoles, FileCouplingMatrix.jaccardKeysOf). For
useEngram=false this is the COMPLETE candidate set the engine builds.

Baseline `<int>{}`-per-node vs an optimized reused membership-epoch buffer
(Int32List, O(1) reset via epoch bump) + reused output lists. Proves the
two produce bit-for-bit identical candidate id lists (membership AND
insertion order) for every node before timing, so the downstream min-heap
tie-handling stays identical.

Result: 1.5-1.7x faster at n>=5000, allocation eliminated. BUT the 5k->20k
per-add superlinear knee (~1.37 baseline) survives in the optimized version
too (~1.40) -> that knee is a memory-hierarchy/GC-regime effect, not
HashSet churn. The Set allocation is a real removable constant, not the
root of the superlinearity.
