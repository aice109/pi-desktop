# ADR-0012: Per-environment SwiftData store paths

[English](0012-environment-isolated-storage.md) · [简体中文](0012-environment-isolated-storage.zh-CN.md)

- Status: Accepted
- Date: 2026-10-17
- Deciders: project collaborators

## Context

PiDesktop runs **without App Sandbox** (`ENABLE_APP_SANDBOX = NO`), so its SwiftData store does not
live in a per-bundle container. SwiftData's default `ModelConfiguration` writes
`~/Library/Application Support/default.store` — a single, shared path. Changing only the Debug bundle
id (to `io.github.aice109.PiDesktop.dev`) isolates `UserDefaults` and Launch Services identity, but
**not** the SwiftData local mirror: running the Debug build from Xcode still reads and writes the
store used by the installed Release build.

The local mirror is not the source of truth. Pi stores sessions as JSONL files under
`~/.pi/agent/sessions/...` (ADR-0005 / ADR-0009), and the app rebuilds its mirror from them when a
session is opened. Losing or orphaning the mirror is therefore recoverable; mixing test and production
writes into the same store is not.

## Options

1. **Keep the default store, rely on bundle id** — cheapest, but demonstrably wrong for a
   non-sandboxed app: the SwiftData file path is shared, so a Debug run can overwrite production data.
2. **Move both configurations into a bundle-id-named directory and migrate the old store** — clean
   layout, but requires a one-off migration, and the existing generic `default.store` may also be used
   by other SwiftData apps on the machine, so it is not safe to adopt blindly.
3. **Use two app-specific directories, one per configuration** (chosen) — Release writes
   `Application Support/PiDesktop/default.store`; Debug writes
   `Application Support/PiDesktop-Dev/default.store`. No migration: the local mirror is rebuilt from
   pi's JSONL files.
4. **Only give Debug a custom URL, keep Release on `default.store`** — preserves existing Release
   data, but leaves the generic filename collision and keeps production on a path other apps can use.

## Decision

Option 3. `PiDesktopApp.modelStoreURL()` resolves `URL.applicationSupportDirectory`, appends
`PiDesktop` for Release or `PiDesktop-Dev` under `#if DEBUG`, creates the directory, and returns
`default.store` inside it. That URL is passed to `ModelConfiguration(schema:url:)`.

The bundle identifiers remain different as well (`.dev` for Debug), so `UserDefaults`, Launch Services
identity, notifications, and future keychain items are isolated by the system.

## Consequences

- Debug and Release never share the SwiftData local mirror; an Xcode run cannot corrupt the installed
  app's store.
- pi's JSONL session files under `~/.pi/agent/sessions/` remain shared by workspace. This decision
  isolates the app-local mirror, preferences, and system identity — not pi's source data.
- The previous `~/Library/Application Support/default.store` is no longer opened. It can be deleted
  manually; pi's session files are untouched and the mirror is rebuilt on demand.
- If App Sandbox is ever enabled, `URL.applicationSupportDirectory` resolves inside the container, so
  the same code keeps working without another path change.
- Persistence-related tests still use in-memory containers; this decision only affects the app's
  production container.
