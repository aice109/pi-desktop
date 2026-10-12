# pi agent Integration

[English](pi-agent.md) · [简体中文](pi-agent.zh-CN.md)

How PiDesktop talks to the pi coding agent. Read when working on agent logic.

> ⚠️ Integration details depend on pi's actual interface. This page records **design constraints and the
> target shape**; the concrete protocol follows pi's official docs and source. Verify against the latest
> pi docs before implementing.

## 1. Roles

PiDesktop is the **GUI front end** for the pi agent:

- pi owns: model calls, tool execution, session orchestration.
- PiDesktop owns: the interface, event visualization, context management, persistence.

**The UI never calls models/tools directly**; it consumes domain events from pi and sends user intents.

## 2. Integration approach (TBD, needs an ADR)

Candidates:

| Approach | Description | Trade-offs |
| --- | --- | --- |
| Subprocess + stdio protocol | App launches the pi CLI and communicates line/JSON | Simple, reuses the CLI; must manage process lifecycle |
| Local service / RPC | pi runs as a service; app connects via socket/HTTP | Loosely coupled; extra service management |
| Direct SDK linking | If pi offers a Swift/embeddable SDK | Tightest coupling; depends on availability |

> Once decided, **write an ADR**, then backfill this section.

## 3. Event model (target)

The agent layer exposes domain events upward (no transport details):

```swift
enum AgentEvent {
    case sessionStarted(id: SessionID)
    case messageDelta(id, text)          // streaming text delta
    case messageCompleted(id, Message)
    case reasoningDelta(id, text)        // reasoning, if exposed
    case toolCallStarted(ToolCall)
    case toolCallOutput(ToolCallID, chunk)
    case toolCallFinished(ToolCallID, result, status)
    case turnFinished(usage)
    case error(AgentError)
}
```

Rules:
- Mapping transport format → domain events happens in `Core/Agent` only.
- Events are pushed upward as an `AsyncStream` (or equivalent sequence).
- Events update UI state on a `@MainActor` store.

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
| `messageDelta` | Streaming bubble/text append |
| `reasoningDelta` | Collapsible reasoning section |
| `toolCallStarted` | Tool-call card (in progress) |
| `toolCallOutput` | Live output inside the card |
| `toolCallFinished` | Card marked success/failure + duration |
| `error` | Inline error with retry |

Rendering follows [design-system.md](design-system.md) (native components + glass).

## 6. Security & privacy

- Never log or persist sensitive content (keys, full file contents).
- Workspace access respects user-authorized scope.
- Sandbox/network entitlement changes require user approval first.

## 7. TODO

- [ ] Confirm pi's protocol → write an ADR
- [ ] Define the full domain event set
- [ ] Implement the `Core/Agent` abstraction + one concrete implementation
- [ ] SwiftData models for sessions/messages
- [ ] Streaming render + tool-call card UI
