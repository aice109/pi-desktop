# ADR-0009: Reconcile the local mirror with pi history

[English](0009-history-sync.md) · [简体中文](0009-history-sync.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

ADR-0005 makes pi's on-disk sessions the source of the session list and mirrors the opened session
into the local `Session`. The mirror was filled **once**, on first open, from the session file. After
that it was never refreshed, so anything that changed the session outside the app — continuing it in
the terminal, a compaction, another client — never showed up. Reopening a session could therefore
display stale history forever.

## Options

1. **Keep the one-shot import** — simplest, but silently wrong after any external change.
2. **Re-read the session file on every open** — correct for the file-based case, but ignores works in
   flight in pi (unflushed entries) and re-parses a potentially large file while pi already has the
   answer in memory.
3. **Reconcile from pi over RPC on open** (chosen) — ask pi for its entries and rebuild the mirror.

For option 3, pi offers two commands:

- `get_messages` returns the **current LLM context**: after a compaction the pre-compaction turns are
  gone, so it cannot represent what the user saw.
- `get_entries` returns the whole append-only tree (pre-compaction history and abandoned branches
  included), with stable ids and timestamps, and supports a `since` cursor.

## Decision

Option 3, with option 2 as an offline fallback.

- `AgentTransport.sessionEntries()` wraps `get_entries` (no cursor yet); the transport stays DTO-only
  (`SessionEntryDTO`), and `Core/Pi` maps it into `PiHistory` through the same `PiHistory.make(from:)`
  used by the session-file parser. One mapping, two sources.
- `SessionStore.syncHistory(for:)` is called from `activate`: **first** from the session file (fast,
  no need to wait for the pi process), **then** from `get_entries` to pick up anything the file has
  not seen. A `PiHistoryFingerprint` (counts + last message text + last tool-call id) skips the
  rebuild when nothing changed, so switching sessions does not churn `Message` objects.
- Rebuilding replaces the mirror's messages and tool calls. That is safe because every local message
  and tool call originates from pi; nothing user-only is stored in `Message`/`ToolCall`. The rebuild
  is skipped while a turn is streaming so it cannot erase in-flight content.

## Consequences

- Reopening a session now converges to pi's truth, including turns made outside the app.
- `SessionStore` depends on `Core/Pi` (glue layer); `Core/Pi` continues to depend only on
  `Core/Agent` DTOs, so the dependency direction stays acyclic.
- Rebuilding changes `Message.id` values. SwiftUI list identity churns once per real change; the
  fingerprint keeps the common path (no change) identical.
- Decoding tolerance matters: `get_entries` messages may have `content` missing or `null`
  (`system`, `bashExecution`). A required field there fails the **whole** response and silently
  yields empty history, so `MessageDTO.content` and `MessageContentDTO` accept both.
- Incremental sync via `get_entries`'s `since` cursor is a natural follow-up; the ids are already
  available but not yet persisted.

## Related

- [ADR-0005](0005-workspace-and-pi-sessions.md) — workspace scoping and pi sessions as the list source
- [ADR-0004](0004-domain-model.md) — `Session` / `Message`
- [ADR-0006](0006-tool-calls.md) — `ToolCall`
