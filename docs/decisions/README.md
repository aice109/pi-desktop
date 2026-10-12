# Architecture Decision Records (ADRs)

[English](README.md) · [简体中文](README.zh-CN.md)

This folder records significant technical and design decisions using **ADRs**.

## When to write an ADR

Write an ADR **before implementing** when any of these apply:

- Adding any **third-party dependency** (SPM / CocoaPods / binary / vendored source).
- Writing a **custom component** that replaces an existing system capability.
- Changing the core framework, transport, data model, or persistence approach.
- Any wide-reaching, expensive-to-reverse trade-off.

## Rules

- **Append-only**: don't edit a decided ADR. To overturn it, add a new ADR marked `Supersedes ADR-XXXX`
  and add `Superseded by ADR-XXXX` to the top of the old one.
- **Increment numbers**: `0001-xxx.md`, `0002-xxx.md`, …
- **Naming**: `NNNN-short-lowercase-title.md`.
- Register new ADRs in the list below.

## Template

```markdown
# ADR-NNNN: <title>

- Status: Proposed | Accepted | Superseded by ADR-XXXX
- Date: YYYY-MM-DD
- Deciders: <names/agents>

## Context
The problem, constraints, and goals.

## Options
1. Option A: description + pros/cons
2. Option B: description + pros/cons

## Decision
Which option and why.

## Consequences
Upsides, downsides, costs, follow-ups.
```

## Decisions

| # | Title | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions with ADRs | Accepted |
| [0002](0002-native-first-and-liquid-glass.md) | Native-first, Liquid Glass, ask before third-party/custom | Accepted |
| [0003](0003-pi-transport-and-sandbox.md) | pi transport and app sandbox / entitlements | Accepted |
| [0004](0004-domain-model.md) | SwiftData domain model (Session / Message) | Accepted |
| [0005](0005-workspace-and-pi-sessions.md) | Workspace-scoped pi sessions | Accepted |
| [0006](0006-tool-calls.md) | Persist tool calls and render them as cards | Accepted |
| [0007](0007-reasoning.md) | Persist assistant reasoning | Accepted |
| [0008](0008-app-settings.md) | Application preferences in UserDefaults | Accepted |
