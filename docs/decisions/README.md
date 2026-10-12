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
