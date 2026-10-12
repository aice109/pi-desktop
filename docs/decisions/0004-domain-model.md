# ADR-0004: SwiftData domain model (Session / Message)

[English](0004-domain-model.md) · [简体中文](0004-domain-model.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

The scaffold shipped only the Xcode template `Item` model. Building the session list and message
stream requires real domain models. [architecture.md](../architecture.md) plans `Session`, `Message`,
`ToolCall`, and `AppSettings`, and states that model changes are significant and require an ADR.

[ADR-0003](0003-pi-transport-and-sandbox.md) chose subprocess transport; the eventual
transport→event mapping will populate these models. The first iteration needs the smallest set that
supports "list sessions → open a session → see and append messages".

## Options

1. **Keep one denormalized model** — minimal, but cannot express ordering or roles cleanly, and is a dead end.
2. **`Session` + `Message` with a cascade relationship** (chosen) — matches the domain, gives stable
   identity, and supports incremental append later.
3. **Add `ToolCall` + `AppSettings` now** — the complete target model, but premature: the `ToolCall`
   shape depends on an event model that does not exist yet.

## Decision

Option 2. Introduce two SwiftData models:

- **`Session`** — `id` (UUID, unique), `title`, `createdAt`, `updatedAt`, `workingDirectory?`,
  `status` (`active` / `archived`), and `messages` (cascade delete, inverse `Message.session`).
- **`Message`** — `id` (UUID, unique), `role` (`user` / `assistant` / `tool`), `content`,
  `createdAt`, and `session` (inverse).

Enums are persisted by `String` raw value (Codable) so new cases decode against old data.
`Session.append(_:)` appends a message and keeps `updatedAt` in sync. `ToolCall` and `AppSettings`
are deferred to later ADRs once the event model from ADR-0003 lands.

## Consequences

- Replaces the template `Item`; the on-disk store shape changes. The app is **unreleased**, so a
  one-time store reset is acceptable and no migration is shipped. Future schema changes must use
  `VersionedSchema` + `SchemaMigrationPlan` and a new ADR.
- Models are nonisolated: verified under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (`@Model` classes
  are not forced onto the main actor), so they can later be used from a background `ModelActor`
  without changes.
- Deleting a `Session` cascades to its `Message`s.
- The domain `id: UUID` gives the agent layer (ADR-0003 events reference `SessionID` / `MessageID`) a
  stable handle independent of SwiftData's `persistentModelID`.

## Related

- [architecture.md](../architecture.md) — module layout and data model
- [pi-agent.md](../pi-agent.md) — event model that will populate these models
- [ADR-0003](0003-pi-transport-and-sandbox.md) — transport and sandbox
