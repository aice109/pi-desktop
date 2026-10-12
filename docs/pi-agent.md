# pi agent Integration

[English](pi-agent.md) · [简体中文](pi-agent.zh-CN.md)

How PiDesktop talks to the pi coding agent. Read when working on agent logic.

> Integration follows pi's official RPC interface (see [ADR-0003](decisions/0003-pi-transport-and-sandbox.md)).
> The concrete wire format lives in pi's docs (`rpc.md`, `rpc-commands.md`, `json.md`,
> `message-types.md`); verify against the installed pi version when extending.

## 1. Roles

PiDesktop is the **GUI front end** for the pi agent:

- pi owns: model calls, tool execution, session orchestration.
- PiDesktop owns: the interface, event visualization, context management, persistence.

**The UI never calls models/tools directly**; it consumes domain events from pi and sends user intents.

## 2. Integration approach

Decided in [ADR-0003](decisions/0003-pi-transport-and-sandbox.md): **subprocess + RPC**
(`pi --mode rpc`), with the App Sandbox disabled.

- PiDesktop launches `pi --mode rpc --no-session` as a child process; one client per session, with the
  child's working directory set to the session's `workingDirectory`.
- Commands are newline-delimited JSON on stdin; responses and session events are NDJSON on stdout;
  stderr is diagnostics only.
- `Core/Agent/PiRPCClient` owns the process and maps records to domain events;
  `Core/Agent/RPCRecords` decodes the wire format.
- `pi` is located via `PI_EXECUTABLE`, `PATH`, and common install paths; the child `PATH` is augmented
  so the `#!/usr/bin/env node` launcher can find Node.
- **Sessions.** pi groups sessions by working directory on disk. The app lists
  `~/.pi/agent/sessions/--<workspace>--/` (read-only, `Core/Pi`) and resumes a chosen session with
  `--session <path>`; new sessions let pi persist them, and the resulting file path is read back from
  `get_state`. See [ADR-0005](decisions/0005-workspace-and-pi-sessions.md).

Wire references: pi's `docs/rpc.md`, `docs/rpc-commands.md`, `docs/json.md`, `docs/message-types.md`.

## 3. Event model

Implemented in `Core/Agent/AgentEvent.swift`; the wire→event mapping lives in `RPCProtocol` so nothing
above `Core/Agent` sees the transport format:

```swift
enum AgentEvent: Sendable, Equatable {
    case agentStarted
    case textDelta(String)               // streaming assistant text
    case thinkingDelta(String)           // reasoning, if exposed
    case toolCallStarted(id: String, name: String, arguments: String?)
    case toolCallUpdated(id: String, output: String)
    case toolCallFinished(id: String, name: String, isError: Bool, durationMs: Int?, output: String?)
    case assistantMessageCompleted(text: String, stopReason: String?, errorMessage: String?)
    case retryStarted(attempt: Int, maxAttempts: Int)
    case retryFinished(success: Bool)
    case compactionStarted
    case compactionFinished(aborted: Bool, errorMessage: String?)
    case settled(aborted: Bool)          // agent_settled: no automatic work remains
    case failed(String)                  // transport failure
}
```

Rules:
- Mapping wire records → domain events happens in `Core/Agent` only.
- Events are delivered upward as an `AsyncStream`.
- Events update UI state on a `@MainActor` store (`SessionStore`).

Not events: usage/cost is read on demand (`sessionStats`) and tool calls are persisted as `ToolCall`
([ADR-0006](decisions/0006-tool-calls.md)); assistant reasoning is persisted on `Message.thinking`
([ADR-0007](decisions/0007-reasoning.md)).

## 4. Session lifecycle

```
create/resume session → start or connect to agent → send user input
      → receive event stream (streaming render) → turn ends → continue or interrupt
      → persist to SwiftData → end/close
```

Must handle: startup failure, connection loss, user interruption, timeouts, concurrent turns, session resume.

## 5. UI mapping

| Domain event | UI |
| --- | --- |
| `textDelta` / `assistantMessageCompleted` | Streaming text append + Markdown render |
| `thinkingDelta` | Collapsible reasoning section (live) |
| `toolCallStarted` | Tool-call card (running) |
| `toolCallUpdated` | Live output inside the card |
| `toolCallFinished` | Card marked success/failure + duration |
| `retryStarted` / `compactionStarted` | Status line shows "Retrying (n/m)…" / "Compacting context…" |
| `failed` | Inline error |

Rendering follows [design-system.md](design-system.md) (native components + glass). Tool calls are
persisted and rendered as cards ([ADR-0006](decisions/0006-tool-calls.md)).

Currently live: streaming assistant text (Markdown), a reasoning section (live and persisted), and
tool-call cards. Error retry is still pending.

## 6. Security & privacy

- Never log or persist sensitive content (keys, full file contents).
- Workspace access respects user-authorized scope.
- Sandbox/network entitlement changes require user approval first.

## 7. TODO

- [x] Confirm pi's protocol → ADR-0003
- [x] `Core/Agent` abstraction (`AgentTransport`) + `PiRPCClient`
- [x] SwiftData models for sessions/messages (ADR-0004)
- [x] Streaming assistant text render
- [x] List a workspace's pi sessions + resume them (ADR-0005)
- [x] Persist tool calls and render them as cards (ADR-0006)
- [x] Model / thinking-level selection, usage & cost display
- [x] Parse assistant `toolCall` blocks so history shows tool arguments
- [x] Rename sessions (delete moves the file to the Trash)
- [x] Persist assistant reasoning (ADR-0007)
- [ ] `get_messages` sync, error retry
