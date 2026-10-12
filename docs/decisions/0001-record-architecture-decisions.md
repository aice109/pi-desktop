# ADR-0001: Record architecture decisions with ADRs

[English](0001-record-architecture-decisions.md) · [简体中文](0001-record-architecture-decisions.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

The project is at its initial stage and will keep introducing modules, transports, and UI compositions.
Without a record of trade-offs, future collaborators (including AI agents) will relitigate settled
questions or accidentally undo existing constraints.

## Options

1. **ADRs**: lightweight Markdown documents, append-only, numbered.
2. **Wiki / external docs**: separated from code, drifts, harder to search.
3. **Commit messages only**: fragmented, hard to survey globally.

## Decision

Use ADRs under `docs/decisions/`, with rules and a template in that folder's README. Significant
trade-offs must be recorded before implementation.

## Consequences

- Upside: traceable decisions, explicit constraints, easier collaboration and agent context.
- Downside: requires discipline and a pre-commit check.
- Follow-up: `AGENTS.md` and `docs/README.md` document the trigger rules.
