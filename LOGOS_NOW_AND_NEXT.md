# Logos now and next

## North star

Logos is no longer aiming to be a top-K related-file ranker.

The current direction is:

- a local-first evidence-routing engine
- with typed transport
- multiscale support and surprise
- motion-compensated inquiry
- explicit witnesses and sidecars
- and a north star of retrieving the smallest trustworthy evidence packet that changes a downstream decision

## What is real in code now

Main engine:

- [logos_git.dart](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\lib\backend\logos_git.dart)
- [logos_git_integrity.dart](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\lib\backend\logos_git_integrity.dart)
- [pr_shape.dart](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\lib\backend\pr_shape.dart)
- [ai.dart](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\lib\backend\ai.dart)

### Operator structure already present

- symmetric evidence diffusion over `graph`
- separate directed `transportGraph`
- typed transport lanes with source/target roles
- transport frontier edges surfaced as explicit objects
- semantic-motion summary:
  - warp coverage
  - innovation mass
  - compensated change ratio
  - scene cut hint
- inquiry planning:
  - transport-frontier first
  - innovation residual fallback

### Evidence state already present

- `support`
- `ambient`
- `surplus`
- `integrity`
- `utility`
- `lowFrequencySupport`
- `highFrequencySurprise`
- `higherOrderLift`
- `reducibilityGap`
- `transportPull`
- `transportedSupport`
- `innovationResidual`

### Witness and sidecar state already present

- typed `LogosEvidenceWitness`
- typed `LogosMetricSidecar`
- witness syndrome
- flow diagnostics
- metric sidecars such as:
  - `generated-source-map`
  - `manifest-lockfile-map`
  - `test-fixture-map`
  - `hyperedge-route`
  - `integrity-boundary`

## What landed in the latest tranche

### Witness-from-carrier residuals

Logos now tracks the inverse of motion innovation:

- `innovationResidual = support - transportedSupport` when unexplained novelty remains
- `witnessResidual = transportedSupport - support` when the carrier predicts a witness/companion more strongly than the admitted support field explains

That turns carrier prediction into a native diagnostic instead of only a prompt hint.

### Expanded typed witness lanes

`logos_git_integrity.dart` now recognizes additional directional witness families:

- `source <-> test`
- `source <-> doc`
- `source <-> migration`

Alongside the existing:

- `source <-> generated`
- `manifest <-> lockfile`
- `source <-> fixture`

### Query-level witness residual summary

`LogosEvidenceQueryResult` now carries `witnessResidual`:

- predicted mass
- residual mass
- coverage
- frontier paths
- dominant kinds

### Inquiry path improvement

When a frontier target is both transport-admitted and witness-deficient, inquiry now prefers:

- `missing source->test witness`

over the weaker generic:

- `transport frontier source->test`

### Downstream integration

`PrShape` and `LogosCommitShape` now preserve:

- witness residual predicted mass
- witness residual mass
- witness residual coverage
- witness residual frontier
- witness residual kinds

So the prompt sink and PR-shape sink can carry this seam without reconstructing it ad hoc.

### Normalization hardening

Transport frontier gating now considers normalized transported support, not only raw transport mass. This prevents low-mass but concentrated carrier flow from disappearing.

## Validation status

Focused tests passed:

- [logos_git_test.dart](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\test\backend\logos_git_test.dart)
- [pr_shape_test.dart](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\test\backend\pr_shape_test.dart)

Windows build passed:

- [git_desktop.exe](C:\Users\mini server\Documents\Projects\git-desktop-premium-ultra-promax-plus-R\apps\desktop-flutter\build\windows\x64\runner\Release\git_desktop.exe)

The release binary was launched after the build.

## What Logos is still not

The main representational ceiling is still real:

- the hot path is still mostly pairwise
- the main diffusion graph is still effectively symmetric
- higher-order structure is still a sidecar, not an escalated operator
- witness-from-carrier still depends on typed lanes and transport admission, not a full multichannel field model
- flow diagnostics are still summary-level, not explicit edge-flow objects

## Most important remaining gap

Typed transport lanes can now describe more witness families than the structural candidate frontier always materializes.

That means the next serious operator fix is:

- ensure taxonomy-backed transport lanes can seed transport adjacency when the pair is semantically valid even if CC / directory / well evidence is weak

In plain terms:

- a lane should not just exist as metadata
- it should have a principled path into the operator

## Least-delusional next steps

### Build next

1. transport candidate materialization
- let typed carrier lanes seed transport adjacency more natively
- avoid taxonomy-only witness claims that the operator could never actually carry

2. explicit witness-from-carrier for more channels
- tests
- docs
- migrations
- later config/operational witnesses

3. geometry-aware review ordering
- carrier before witness
- source before generated
- source before tests/docs/migrations
- innovation frontier before generic hotness

4. semantic keyframes / scene cuts
- use compensated change ratio to decide when caches and masks should be rebuilt instead of patched

### Build after that

5. true edge-flow / Hodge objects in PR shape and X-Ray
6. hyperedge escalation beyond sidecars
7. proof-budget / quorum / danger controller
8. self-generated gradient navigation

## Short synthesis

Logos now has the first native pieces of a motion-compensated, typed, witness-aware evidence engine.

The current best reading is:

- `graph` tells us where semantic mass belongs
- `transportGraph` tells us how carrier structure can move or imply companions
- `innovationResidual` tells us what transport failed to explain
- `witnessResidual` tells us what transport predicted but the admitted evidence field failed to support

That is the correct direction.

The next leap is not another score.

It is giving typed transport a more native operator foothold, so the witness field is carried by structure instead of merely annotated after the fact.
