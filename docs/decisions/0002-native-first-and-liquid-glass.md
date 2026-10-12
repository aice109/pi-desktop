# ADR-0002: Native-first, Liquid Glass, ask before third-party/custom

[English](0002-native-first-and-liquid-glass.md) · [简体中文](0002-native-first-and-liquid-glass.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators (per user requirement)

## Context

PiDesktop should be a lightweight, long-term maintainable client that matches macOS look and feel.
Casually adding third-party dependencies or hand-drawn components brings bundle bloat, maintenance
burden, visual inconsistency, and licensing risk. The user explicitly required native components, a
Liquid Glass look, and approval before introducing third-party or custom components.

## Options

1. **Native-first + system Liquid Glass + ask before changes** (this decision).
2. **No restrictions; add dependencies/components as needed**: flexible short-term, uncontrolled long-term.
3. **Ban all third-party/custom**: too rigid; some cases genuinely lack a native solution.

## Decision

Choose option 1:

- **Native-first**: prefer SwiftUI / AppKit / Foundation / SwiftData; don't reinvent built-ins.
- **Liquid Glass**: follow macOS Liquid Glass with the system APIs (`.glassEffect()`,
  `GlassEffectContainer`, `.buttonStyle(.glass)`, `NSGlassEffectView`); never fake it with custom blur.
- **Ask before adding**: third-party dependencies, custom components replacing native capabilities, and
  non–SF Symbols assets require explaining the reason, options, and impact, then explicit approval
  (plus an ADR when warranted) before implementation.

## Consequences

- Upside: consistent look, controllable dependencies, better maintainability and accessibility.
- Downside: a few needs may have limited native support and require exploration or user consultation.
- Follow-up: codified as hard rules in `AGENTS.md` §2, `docs/design-system.md`, and
  `docs/coding-conventions.md`.
