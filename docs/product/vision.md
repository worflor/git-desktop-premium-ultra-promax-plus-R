# Product Vision

## Problem Statement
Existing desktop Git clients are often either:
- Easy but slow/limited for power users
- Powerful but hostile in UX

Developers in 2026 expect a tool that is both fast and intelligent.

## Vision
Create a Git desktop app that feels native-fast, handles huge diffs smoothly, and offers practical AI assistance without forcing cloud lock-in.

## Target Users
- Solo and small-team developers shipping quickly
- Power users who need advanced Git operations without CLI context switching every minute
- Developers working in large monorepos and code review-heavy workflows

## Core Jobs To Be Done
1. Understand what changed quickly.
2. Create clean commits with confidence.
3. Resolve branches/integration work without fear.
4. Get useful AI feedback directly in-context.

## Non-Negotiable UX Outcomes
- "I can see what matters in seconds."
- "I never wait on the app for normal Git actions."
- "AI helps me think; it does not hijack my workflow."

## Product Boundaries (V1)
In scope:
- Local repo management and daily Git workflows
- Visual diffing with high performance for large changes
- Local AI review and explanation tools
- Cross-platform desktop support via Tauri

Out of scope for V1:
- Hosted collaboration platform replacement
- PR creation/review feature parity with web for every provider
- Full plugin marketplace

## Differentiators
- Performance-first architecture (Rust + system Git provider + low-overhead UI)
- Structured AI adapter layer for local CLIs
- Explicit trust model: user controls command execution and data flow
- High-signal UI with configurable information density
