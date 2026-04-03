# ADR 0001 - Stack Decision

## Status
Accepted

## Context
We need a cross-platform desktop app that can replace GitHub Desktop while improving:
- Startup and runtime performance
- Large-diff rendering
- Local AI integration
- Developer velocity for a solo maintainer

## Decision
We will use:
- Tauri for desktop shell/runtime
- Rust for backend services and system integration
- System Git CLI as the primary Git engine through a Rust provider layer
- Optional forge adapters for host-specific workflows (for example GitHub via gh when available)
- Optional git2 acceleration only for targeted read-heavy operations after profiling
- Solid.js + TypeScript + Vite for UI
- Pretext as the core text layout engine for diff rendering, paired with virtualized DOM and canvas rendering surfaces
- Rust child process adapters for AI CLI integration

## Why This Stack
### Tauri over Electron
- Smaller binaries and lower RAM overhead due to native webview
- Better native feel with less runtime bulk

### Rust + system Git CLI as primary engine
- Maximizes compatibility with real-world repositories and edge-case behavior
- Reuses existing credential helper and SSH agent flows users already trust
- Keeps core Git workflows host-agnostic across GitHub/GitLab/Bitbucket/self-hosted remotes

### Optional git2 for targeted acceleration
- Can reduce overhead for selected read-heavy operations
- Must not replace primary GitProvider in V1
- Must be gated by profiler evidence and parity tests

### Solid.js over React (initially)
- Fine-grained reactivity can reduce UI overhead on heavy update surfaces
- Good TypeScript ergonomics and fast startup

### Pretext-first renderer architecture
- Pretext provides DOM-free measurement and line layout APIs that map well to huge diff workloads.
- We can share one layout engine across multiple rendering surfaces (DOM and canvas).
- This keeps line mapping behavior consistent when switching render modes.

### Canvas/Virtualized renderer over raw DOM for huge diffs
- Prevents DOM explosion with very large files/hunks
- Enables stable scroll performance and predictable paint cost

### Local AI CLI adapter model
- Avoid mandatory API key handling in app
- Leverage user-installed tools and existing authentication
- Keep model/provider choice user-controlled

## Trade-offs
- Rust and Tauri increase systems complexity vs pure web stack
- Git CLI orchestration requires robust command execution, parsing, and error mapping
- Canvas text rendering requires custom selection/copy/search ergonomics
- Local AI CLIs are heterogeneous and require robust adapters

## Mitigations
- Introduce abstraction layers (GitProvider, AiProvider)
- Build fixture-based compatibility tests across Git versions and platforms
- Add ForgeProvider abstraction so host-specific features are optional extensions
- Use OS-native credential helpers and SSH agents as the default auth path
- Implement staged render surfaces (DOM for small/medium diffs, canvas for huge diffs) using the same Pretext line-layout pipeline
- Pin Pretext version and gate upgrades with benchmark and accuracy checks
- Keep a minimal emergency fallback layout path if Pretext initialization fails at runtime
- Add adapter contract tests for each AI CLI integration

## Consequences
- Strong long-term performance posture
- Higher initial architecture investment
- Better chance of sustained competitive UX vs mainstream desktop Git tools
- Platform-agnostic core workflows with optional forge-specific enhancements

Implementation details are defined in [docs/architecture/diff-rendering-architecture.md](docs/architecture/diff-rendering-architecture.md).
VCS and auth details are defined in [docs/architecture/vcs-auth-strategy.md](docs/architecture/vcs-auth-strategy.md).
Research evidence is captured in [docs/research/pretext-evaluation.md](docs/research/pretext-evaluation.md).
