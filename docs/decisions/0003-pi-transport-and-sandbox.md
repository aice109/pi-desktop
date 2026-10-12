# ADR-0003: pi transport and app sandbox / entitlements

[English](0003-pi-transport-and-sandbox.md) · [简体中文](0003-pi-transport-and-sandbox.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: project collaborators

## Context

PiDesktop must connect to the pi coding agent and let it operate on a user's project directory
(see [pi-agent.md](../pi-agent.md)). Two decisions are coupled and still open:

1. **Transport** — how the app talks to pi.
2. **Sandbox / entitlements** — what the app is allowed to do under the macOS App Sandbox.

The current scaffold ships `com.apple.security.app-sandbox = true` and
`com.apple.security.files.user-selected.read-only`, auto-generated from
`ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readonly`. A sandboxed app **cannot spawn
arbitrary child processes and cannot read/write arbitrary project paths**, so the transport and the
entitlement decision must be made together. Changing entitlements is gated by
[AGENTS.md §2.3](../../AGENTS.md) (explain → options → impact → explicit approval).

## Options

### Transport

1. **Subprocess + stdio** — launch the `pi` CLI and exchange line/JSON over pipes.
   - Pros: reuses the existing CLI; simple; one process tree; lifecycle is local.
   - Cons: must spawn a child; hardened runtime / library validation may block loading a
     non-notarized helper; needs careful cancellation and process management.
2. **Local service / RPC** — pi runs as a service (socket/HTTP); the app is a client.
   - Pros: sandbox-friendly (no child process from the UI); the service owns file access; loose coupling.
   - Cons: an extra daemon to install/supervise; socket discovery and auth; packaging.
3. **Direct SDK linking** — embed a pi SDK if one exists.
   - Pros: tightest integration.
   - Cons: depends on a Swift/embeddable SDK that may not exist; tightest coupling.

### Sandbox

- **A. Keep sandbox ON** — grant workspace access via `NSOpenPanel` + security-scoped bookmarks;
  run pi through a bundled helper / XPC service with `com.apple.security.inherit`.
  - Pros: Mac App Store–eligible; strongest isolation.
  - Cons: most engineering; one bookmark per workspace; helper packaging and trust boundary.
- **B. Disable App Sandbox** (`ENABLE_APP_SANDBOX = NO`).
  - Pros: spawn `pi` directly and read/write project dirs with normal filesystem permissions;
    simplest path; matches how most terminal / developer-tool GUIs ship (outside the Mac App Store).
  - Cons: not Mac App Store–eligible; weaker isolation; still needs notarization + hardened runtime
    for distribution.
- **C. Hybrid** — sandboxed UI + unsandboxed helper launched via `SMAppService` / login item.
  - Pros: a sandboxed UI is still possible.
  - Cons: most complex; two-process trust boundary.

## Decision

Choose **transport 1 (subprocess + stdio)** with **sandbox B (App Sandbox disabled)**.

PiDesktop is a developer tool distributed by direct download (notarized), not through the Mac App
Store. Disabling the App Sandbox lets the app spawn the `pi` CLI directly and read/write the user's
project directories with normal filesystem permissions — the shortest path to a working agent loop.
The sandboxed alternatives (A/C) add a helper/XPC process and per-workspace security-scoped bookmarks;
we revisit them only if Mac App Store distribution becomes a goal.

Implementation: set `ENABLE_APP_SANDBOX = NO` and drop `ENABLE_USER_SELECTED_FILES`. Per
[AGENTS.md §2.3](../../AGENTS.md) this entitlement change was explicitly approved by the project owner.

## Consequences

- The `com.apple.security.app-sandbox` and `com.apple.security.files.user-selected.read-only`
  entitlements are gone; the app runs unsandboxed with hardened runtime + notarization for distribution.
- Not Mac App Store–eligible. If that becomes a requirement, supersede this ADR with the helper/XPC
  approach (A/C).
- The app spawns and supervises `pi` as a child process: implement lifecycle/cancellation and a
  transport→domain-event mapping in `Core/Agent`.
- Follow-up: ADR-0004 records the SwiftData data model (`Session` / `Message`) and its migration story.

## Related

- [pi-agent.md](../pi-agent.md) — event model, session lifecycle, integration constraints
- [architecture.md](../architecture.md) — planned modules and data model
- [AGENTS.md §2.3](../../AGENTS.md) — approval gate for build config / entitlements
