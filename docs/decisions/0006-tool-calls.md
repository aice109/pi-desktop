# ADR-0006: Persist tool calls and render them as cards

[English](0006-tool-calls.md) · [简体中文](0006-tool-calls.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

Watching tool calls unfold is the app's headline feature, but the first iteration only showed a
transient "Running <tool>…" indicator and discarded the call afterwards. pi's live events now carry
enough to render them: `tool_execution_start` has `args`, `tool_execution_update` has
`partialResult`, and `tool_execution_end` has `result`, `isError`, and `durationMs` (pi
`docs/json.md`). Historical sessions also contain `toolResult` entries
(pi `docs/session-format.md`).

[ADR-0004](0004-domain-model.md) deliberately deferred `ToolCall` until the event model existed. It
now does, so this ADR decides how tool calls are represented and rendered.

## Options

1. **Keep tool calls on `Message`** — reuse `Message(role: .tool)` and add `toolName` / `arguments` /
   `isError` / `durationMs` fields. Keeps a single timeline, but overloads `Message` with a union of
   fields only meaningful for one role, and mixes two concepts.
2. **A dedicated `ToolCall` model** (chosen) — matches the plan in `architecture.md`; keeps `Message`
   clean; the view merges two arrays by time into one timeline.
3. **Do not persist tool calls** (live-only indicator) — least work, but nothing remains after the
   turn and reopening a session loses all of it.

## Decision

Option 2. Add a `ToolCall` SwiftData model and carry its data through the agent layer.

- **Model** — `ToolCall`: `id` (UUID, unique), `toolCallID` (pi's id, for correlating events), `name`,
  `arguments` (compact text), `output`, `isError`, `durationMs`, `createdAt`, and `session` (cascade
  delete, inverse `Session.toolCalls`).
- **Events** — `AgentEvent.toolCallStarted(id:name:arguments:)`,
  `.toolCallUpdated(id:output:)`, `.toolCallFinished(id:name:isError:durationMs:output:)`. `args` is
  decoded into a generic `JSONValue` and flattened to a display string, because each tool has its own
  parameter shape.
- **Store** — `SessionStore` creates a `ToolCall` on start, updates `output` on partial results, and
  finalizes on end. A `toolCallID → ToolCall` index supports parallel tool calls; a live
  `activeToolName` remains for the status line.
- **History** — `PiSessionFiles.toolCalls(in:)` maps each `toolResult` entry to a `ToolCall`, so
  reopened sessions render the same cards.
- **UI** — `ChatView` merges messages and tool calls by `createdAt` into one timeline; `ToolCallCard`
  shows name, arguments, status, duration, and a collapsible output.

## Consequences

- A schema change: a new entity and a relationship. Adding them is a lightweight migration; the app is
  **unreleased**, so a one-time store reset is also acceptable. Structural changes still require
  `VersionedSchema` / `SchemaMigrationPlan`.
- History imports get tool **name** and **output** but not **arguments**: `toolResult` entries do not
  carry them, and parsing the assistant's `toolCall` blocks is not done yet. Live calls do show
  arguments. A follow-up should parse those blocks.
- `MessageRole.tool` is kept so previously imported data still decodes, but new imports no longer
  create tool messages.
- Output can be large; it is stored whole and shown collapsed. Truncation/limits are a follow-up.

## Related

- [ADR-0003](0003-pi-transport-and-sandbox.md) — transport and sandbox
- [ADR-0004](0004-domain-model.md) — `Session` / `Message`
- [ADR-0005](0005-workspace-and-pi-sessions.md) — workspace-scoped sessions
- [pi-agent.md](../pi-agent.md) — event model
