# Architecture

[English](architecture.md) · [简体中文](architecture.zh-CN.md)

## Goals

PiDesktop is a native macOS GUI for the pi coding agent. Its core responsibilities:

1. Establish a session with the pi agent (start/connect/interrupt).
2. Present the agent's messages, reasoning, tool calls, and results in real time.
3. Manage project/file context and the working directory.
4. Provide settings, preferences, and history.

## Technology stack

| Concern | Choice | Notes |
| --- | --- | --- |
| UI | SwiftUI | Primary UI framework; AppKit bridging when needed |
| Persistence | SwiftData | Sessions, messages, settings |
| State | Observation / `@Observable` | Preferred over `ObservableObject` |
| Concurrency | Swift Concurrency | `async/await`, `actor`, `AsyncStream` |
| Design | Liquid Glass | See [design-system.md](design-system.md) |

## Current layout

```
PiDesktop/
├── PiDesktopApp.swift          # @main, Scene, SwiftData container, store assembly
├── ContentView.swift           # Root view (workspace gate + session list + detail)
├── Features/
│   ├── Chat/                   # ChatView: message stream + composer
│   ├── Settings/               # SettingsView: preferences window
│   └── Workspace/              # WorkspaceGateView: choose a folder
├── Core/
│   ├── Agent/                  # AgentEvent, AgentTransport, PiRPCClient, RPCProtocol
│   ├── Commands/               # SessionCommands: menu ↔ focused window bridge
│   ├── Pi/                     # PiSessionFiles, PiHistory (read pi's history)
│   ├── Models/                 # Session, Message, ToolCall (ADR-0004 / ADR-0006)
│   └── Stores/                 # SessionStore, WorkspaceStore, AppSettingsStore
├── DesignSystem/               # DesignTokens: shared radius tokens (design-system.md §5)
└── Assets.xcassets/            # Asset catalog
```

## Planned module layout

As features land, source is organized **feature-first**, not by type:

```
PiDesktop/
├── App/            # Entry, scenes, dependency assembly
├── Features/
│   ├── Chat/       # Conversation & message stream UI
│   ├── Session/    # Session list & lifecycle
│   ├── Settings/   # Preferences
│   └── Workspace/  # Project / file context
├── Core/
│   ├── Agent/      # Communication with pi (process/protocol/events)
│   ├── Pi/         # Read pi's on-disk session files
│   ├── Models/     # SwiftData models
│   └── Services/   # Storage, logging, configuration
└── DesignSystem/   # Colors, type, glass wrappers, shared views
```

Rules:
- A feature folder is self-contained (views / view models / local components).
- Cross-feature capabilities sink into `Core/` or `DesignSystem/`.
- The agent layer exposes domain events only; it never leaks transport details.

## Data flow

Implemented (see [ADR-0003](decisions/0003-pi-transport-and-sandbox.md)):

```
pi agent process (pi --mode rpc)
      │  NDJSON on stdout
      ▼
 Core/Agent  ──►  AgentEvent stream (AsyncStream)
      │                     │
      │                     ▼
      │        SessionStore (@Observable, @MainActor)  ──►  SwiftData (Message)
      │                     │
      └── stdin JSONL ◄──── SwiftUI Views (ChatView)
```

Principles:
- **Unidirectional data flow**: views read state and send intents; state changes live in stores.
- **Main-actor isolation**: UI state is marked `@MainActor`.
- **Transport/UI decoupling**: the agent layer never imports SwiftUI; it exposes only `AgentEvent`.

Session **listing** is read-only and separate from the live transport: `WorkspaceStore` scans
`~/.pi/agent/sessions/--<workspace>--/` through `Core/Pi`, and opening a session mirrors its history
into a local `Session` (`piSessionPath`) before continuing it with `pi --session <path>` (ADR-0005).

On open the mirror is **reconciled** with pi instead of being filled once: `SessionStore.syncHistory`
reads the session file first (fast, offline) and then `get_entries` over RPC, skipping the rebuild when
the content is unchanged ([ADR-0009](decisions/0009-history-sync.md)).

The rebuild inserts `Message` / `ToolCall` rows in bulk: new objects are registered with the
`ModelContext` first and then assigned to the relationship in one shot. Building the relationship
with unregistered objects (or appending one by one) is O(n²) in SwiftData and blocks the main actor
for tens of seconds on a long history.

## Data model

**Implemented** ([ADR-0004](decisions/0004-domain-model.md), [ADR-0006](decisions/0006-tool-calls.md)):

- `Session` — a conversation: id, title, created/updated timestamps, working directory, status, and
  the `piSessionPath` of its file on disk ([ADR-0005](decisions/0005-workspace-and-pi-sessions.md)).
- `Message` — role (user/assistant/tool), content, optional assistant reasoning, timestamp, owning session.
- `ToolCall` — tool name, arguments, output, status, duration, owning session.
- `MessageImage` — raw image bytes (`.externalStorage`) + mimeType for an image attached to a user
  message ([ADR-0010](decisions/0010-image-attachments.md)).

> Model changes are significant → require an ADR (see [decisions/](decisions/README.md)).

**Not in SwiftData:** preferences (theme, startup/UI toggles, last opened session) live in
`UserDefaults` through `AppSettingsStore` ([ADR-0008](decisions/0008-app-settings.md)) — they are a
single flat record needed before the container exists.

## Related
- UI spec: [design-system.md](design-system.md)
- pi integration: [pi-agent.md](pi-agent.md)
- Code style: [coding-conventions.md](coding-conventions.md)
