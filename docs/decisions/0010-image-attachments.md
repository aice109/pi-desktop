# ADR-0010: Attach images to prompts

[English](0010-image-attachments.md) · [简体中文](0010-image-attachments.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

pi accepts images on `prompt`, `steer`, and `follow_up` through an `images` array of `ImageContent`
(`{type: "image", data: <base64>, mimeType}`; pi `docs/message-types.md`). User messages stored in the
session file carry the same `image` blocks. PiDesktop currently drops image blocks when decoding and
can only send text, so it cannot show or send screenshots at all.

Rendering images means persisting them locally: the mirror is rebuilt from pi on open, but between
syncs (and offline) the UI must still show what the user attached. This is a schema change, so per
[ADR-0004](0004-domain-model.md) it needs an ADR.

## Options

1. **A `MessageImage` SwiftData model** (chosen) — one row per image, bytes in `@Attribute(.externalStorage)`.
   Images belong to a message, are rendered in timeline order, and import naturally from history.
2. **Send-only, re-import from pi** — no schema change, but images disappear from the mirror until the
   next sync and cannot be previewed in the composer; offline history loses them.
3. **Files on disk referenced by path** — keeps the store small but adds lifecycle/cleanup burden and
   breaks the "one SwiftData mirror" model.

## Decision

Option 1.

- `AgentImage` is the transport-level value (raw `data` + `mimeType`); `PiRPCClient` base64-encodes it
  into the wire `images` field. `AgentTransport.prompt/steer/followUp` take `images: [AgentImage]`.
- `MessageImage` is the persisted model: `mimeType`, `data` (`.externalStorage`), and a cascade
  relationship from `Message`. `Message.images` is ordered by insertion.
- History parsing keeps `image` content blocks: `MessageContentDTO` splits text and images, and
  `PiHistory` yields `PiDisplayImage` values that the mirror inserts as `MessageImage` rows.
- The composer accepts images from the pasteboard, a file picker, and drag-and-drop, shows thumbnails
  with a remove affordance, and sends them with the next message. User messages render their images.

## Consequences

- Schema change: a new `MessageImage` model plus a `Message` relationship. The app is **unreleased**, so
  a lightweight migration / store reset is acceptable.
- Base64 crosses the RPC boundary by design (pi's wire format); the store keeps raw `Data` to avoid
  double-encoding. External storage keeps the SQLite file small for screenshots.
- Only raster images are supported (png/jpeg/gif/webp/heic); arbitrary file attachments are out of scope.
- Message editing (replacing an image) is not supported; the composer removes and re-adds instead.
- Very large images are not resized/throttled yet; a follow-up can add a size cap.

## Related

- [ADR-0004](0004-domain-model.md) — `Session` / `Message`
- [ADR-0007](0007-reasoning.md) — the analogous "persist a content block" decision
- [pi-agent.md](../pi-agent.md) — event model and prompt command
