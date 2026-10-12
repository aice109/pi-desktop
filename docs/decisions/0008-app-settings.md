# ADR-0008: Application preferences in UserDefaults

[English](0008-app-settings.md) · [简体中文](0008-app-settings.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

PiDesktop needs user preferences (appearance, whether to reopen the last session on launch, whether to
show the usage footer, whether to confirm before deleting a session). The project already persists
domain data in SwiftData (`Session` / `Message` / `ToolCall`, [ADR-0004](0004-domain-model.md),
[ADR-0006](0006-tool-calls.md)), so the default instinct would be one more `@Model`.

Preferences are different from domain data: they are a single, flat, app-wide record with no
relationships, no queries, and no history. They are also read during `App.init` before a
`ModelContainer` is available (the appearance must be known when the first window is built).

## Options

1. **A SwiftData `AppSettings` model** — consistent with the rest of persistence, but drags a schema
   change/migration and a container dependency into startup for four booleans, and still needs a
   "single row" convention that SwiftData does not provide.
2. **A `UserDefaults`-backed `@Observable` store** (chosen) — the macOS-native home for preferences
   (`NSUserDefaults` has always been the preferences store), no schema, no migration, available
   before the container, trivially testable with a custom suite.
3. **A JSON file in Application Support** — hand-rolled persistence and serialization; only worth it
   for structured, versioned data.

## Decision

Option 2. `AppSettingsStore` (`Core/Stores/AppSettingsStore.swift`) is a `@MainActor @Observable`
class writing through to `UserDefaults` under the `settings.*` keys, exposed to the UI via
`SettingsView` (the SwiftUI `Settings` scene, so ⌘, works) and the environment.

Preferences are deliberately limited to **UI / client behaviour**. Anything that belongs to the agent
(model, thinking level, session name, tool permissions) stays in pi and is reached over the RPC
transport — PiDesktop never keeps a second source of truth for it (see [ADR-0005](0005-workspace-and-pi-sessions.md)).

## Consequences

- Settings live outside the SwiftData schema; `Session`-related migrations never touch preferences.
- `lastSessionPath` (used to restore the previously open session) is a preference, not a
  relationship; it is written when a session is opened and ignored if the file no longer exists.
- `UserDefaults` is not transactional, but preferences are individually idempotent values, so
  torn writes are not a concern.
- Tests get a clean store via `UserDefaults(suiteName:)`; no container is needed.

## Related

- [ADR-0004](0004-domain-model.md) — SwiftData domain model
- [ADR-0005](0005-workspace-and-pi-sessions.md) — pi owns session state
