# ADR-0005: Workspace-scoped pi sessions

[English](0005-workspace-and-pi-sessions.md) · [简体中文](0005-workspace-and-pi-sessions.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

The app listed only the sessions it created itself and never surfaced the sessions pi already stores.
pi groups sessions by working directory on disk
(`~/.pi/agent/sessions/--<path>--/<timestamp>_<id>.jsonl`, see pi `docs/session-format.md`). Users
expect to **pick a project folder and see that folder's pi sessions**, then continue one.

Two questions must be answered:

1. What is the source of truth for the session list?
2. How does the app open and continue a pi session?

ADR-0003 chose subprocess transport and ADR-0004 defined `Session` / `Message`. This ADR does not
revisit those; it defines how pi's on-disk sessions relate to the local model.

## Options

1. **Keep app-owned sessions only** — add pi's sessions as a separate read-only view. Simple, but two
   competing session lists confuse users and neither is authoritative.
2. **pi's on-disk sessions are the list source; mirror the opened one locally** (chosen). Read the
   session files for the selected folder; when a session is opened, import its history into a local
   `Session` keyed by the pi session file, and continue it via `pi --session <path>`.
3. **Make pi the sole source of truth and drop SwiftData** — cleanest conceptually, but a large
   refactor that discards ADR-0004 and removes any local cache/history for offline display.

## Decision

Option 2.

- **Listing** is read-only. `Core/Pi/PiSessionFiles` locates
  `~/.pi/agent/sessions/--<path>--/` (mangling per pi's rules: drop the leading separator, replace
  `/`, `\`, `:` with `-`, wrap in `--`) and parses each `.jsonl` into a `PiSessionSummary`
  (id, name, preview, message count, timestamps).
- **Workspace** selection is owned by `Core/Stores/WorkspaceStore` and persisted in `UserDefaults`.
  When no folder is selected, the UI shows `WorkspaceGateView`, which prompts the user to choose one.
- **Opening** a session mirrors it into a local `Session` (`piSessionPath` = the file path), importing
  displayable messages (user / assistant / toolResult) from the file.
- **Continuing** launches pi with `--session <path>`. New sessions launch **without** `--no-session`, so
  pi persists them; `AgentTransport.sessionInfo()` (`get_state`) returns the `sessionFile`, which is
  written back to `Session.piSessionPath` after the first turn and refreshes the list.

## Consequences

- `Session` gains `piSessionPath: String?`. This is a schema change; adding an optional property is a
  lightweight migration. The app is **unreleased**, so a one-time store reset is also acceptable.
  Future structural changes still require `VersionedSchema` + `SchemaMigrationPlan`.
- The app no longer passes `--no-session` by default; pi now owns session persistence. Local `Message`
  rows are a display cache/mirror, not the only copy.
- Deleting sessions (which would delete pi's `.jsonl` files) is deliberately **deferred** — it is
  destructive and needs its own design.
- Parsing reads whole session files; large histories are scanned off the main actor. If this becomes
  slow, add a bounded scan (header/tail) later.
- No new third-party dependency and no custom component: the UI uses `ContentUnavailableView` and
  SwiftUI's `.fileImporter`.

## Related

- [ADR-0003](0003-pi-transport-and-sandbox.md) — transport and sandbox
- [ADR-0004](0004-domain-model.md) — `Session` / `Message`
- [pi-agent.md](../pi-agent.md) — integration overview
- [architecture.md](../architecture.md) — module layout and data flow
