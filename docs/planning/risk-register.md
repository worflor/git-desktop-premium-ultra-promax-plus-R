# Risk Register

## R-001: system Git orchestration and parsing fragility
Impact: high
Likelihood: medium
Mitigation:
- Standardize command wrapper with structured output/error parsing
- Maintain fixture tests across OS and Git versions
- Keep command-level retry and remediation hints for transient failures

## R-002: Large-diff renderer complexity
Impact: high
Likelihood: medium
Mitigation:
- Ship dual renderer strategy (DOM virtualized first, canvas at threshold)
- Build targeted perf benchmarks early

## R-003: AI CLI ecosystem instability
Impact: medium
Likelihood: high
Mitigation:
- Strict adapter interface and per-provider contract tests
- Feature degrade gracefully when provider unavailable

## R-004: Auth and credential handling edge cases
Impact: high
Likelihood: medium
Mitigation:
- Use OS credential store
- Add explicit diagnostics and actionable error messaging

## R-005: Solo maintainer bandwidth
Impact: high
Likelihood: high
Mitigation:
- Timebox features to value slices
- Control scope with phase gates and exit criteria
- Defer non-critical polish until core loop is excellent

## R-006: Cross-platform packaging friction
Impact: medium
Likelihood: medium
Mitigation:
- Set up CI packaging checks early
- Keep platform-specific code paths isolated

## R-007: Pretext dependency maturity risk
Impact: medium
Likelihood: medium
Mitigation:
- Pin Pretext version and gate upgrades with correctness + performance CI checks
- Build fixture corpus that stresses unicode, bidi, long lines, and font variance
- Keep emergency fallback layout path for runtime resilience and diagnostics

## R-008: Forge adapter fragmentation
Impact: medium
Likelihood: medium
Mitigation:
- Keep ForgeProvider optional and capability-driven
- Ensure core Git workflows never depend on host-specific adapters
- Add adapter contract tests and graceful degraded UX states
