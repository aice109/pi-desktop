# ADR-0011: A single main window

[English](0011-single-window.md) · [简体中文](0011-single-window.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

The main scene is a `WindowGroup` holding three app-level stores (`SessionStore`, `WorkspaceStore`,
`AppSettingsStore`) created once in `PiDesktopApp.init`. `WindowGroup` lets the user open several main
windows (File ▸ New Window), and every window shares those stores.

`SessionStore` is written as a **single-owner** store:

- `transports` / `subscriptions` / `states` are keyed by `Session.id`, so two windows opening the same
  session would share one pi subprocess and fight over its event stream.
- `visibleSessionID` is a single value, used to decide unread/notifications (ADR-0011 depends on it).
  With two windows viewing different sessions it cannot be correct.
- Only one window's `ContentView` sets `focusedSceneValue(\.sessionCommands)`; menu commands act on
  whichever window is focused, but the stores they mutate are shared.

The result is subtle corruption rather than a crash: wrong unread dots, a session's stream driven from
two places, and commands whose effect is hard to predict. Proper multi-window support would require
scoping the stores (and their pi subprocesses) per window and rethinking the SwiftData context sharing.

## Options

1. **Keep `WindowGroup`, document the limitation** — cheapest, but leaves a footgun that looks like it
   works.
2. **Scope stores per window** — correct multi-window, but a large refactor: per-window stores, per-window
   pi processes, `@FocusedValue` wiring for every command, and re-validating the model container across
   contexts. The app does not need simultaneous sessions today.
3. **Make the main UI a single `Window`** (chosen) — one main window, so the single-owner stores are
   always correct. "New Session" stays the in-app way to start new work.

## Decision

Option 3. `PiDesktopApp` uses `Window("PiDesktop", id: "main")` instead of `WindowGroup`. The
`Settings` scene is unchanged, so ⌘, still opens preferences.

## Consequences

- Shared-store invariants (`visibleSessionID`, one transport per session) always hold.
- File ▸ New Window disappears; users switch work with "New Session" (⌘N) inside the one window.
- If multi-window ever becomes a requirement, it is option 2 — an ADR that supersedes this one plus the
  per-window-store refactor.
