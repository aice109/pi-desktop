# ADR-0007: Persist assistant reasoning

[English](0007-reasoning.md) · [简体中文](0007-reasoning.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

Reasoning models stream their thinking through `thinking_delta` events, and `ChatView` already shows
a live, collapsible "Reasoning" section while a turn runs. But the text was only held in memory for
the duration of the turn and then discarded: after `agent_settled` (or after reopening the session)
the reasoning was gone. pi also persists thinking in the session file as `thinking` content blocks
(pi `docs/message-types.md`), so the data is available for history imports.

This is a small schema change, which per [ADR-0004](0004-domain-model.md) needs an ADR.

## Options

1. **Add `Message.thinking` (optional)** (chosen) — reasoning belongs to a specific assistant message;
   one optional field on the existing model is the smallest change and imports naturally.
2. **A separate `Reasoning` model** — mirrors `ToolCall`, but reasoning is one-per-assistant-message
   and never needs its own timeline; overkill.
3. **Keep reasoning live-only** — no schema change, but the content is lost, which is the problem.

## Decision

Option 1. Add `Message.thinking: String?`.

- `SessionStore` already accumulates `thinkingDelta` while streaming; on `assistantMessageCompleted`
  it writes the accumulated text into the message. An assistant message is now kept if it has **either**
  content or thinking (previously a thinking-only reply was deleted as an empty placeholder).
- History import parses assistant `thinking` blocks (`MessageContentDTO.joinedThinking`) into
  `Message.thinking`.
- `ChatView` renders a collapsible "Reasoning" disclosure on any assistant message that has thinking,
  using the same component as the live indicator.

## Consequences

- Schema change: one optional field on `Message`. Adding an optional attribute is a lightweight
  migration; the app is **unreleased**, so a one-time store reset is also acceptable.
- `Message` is no longer strictly "content only"; `thinking` is reasoning metadata that is never sent
  back to the model (pi owns the conversation state, so this is display-only).
- The `thinkingSignature` (provider replay data) is deliberately **not** stored: it is opaque and not
  needed for display.
- Very long reasoning is stored whole and shown collapsed; truncation is a follow-up.

## Related

- [ADR-0004](0004-domain-model.md) — `Session` / `Message`
- [ADR-0006](0006-tool-calls.md) — tool calls (the other half of rich rendering)
- [pi-agent.md](../pi-agent.md) — event model
