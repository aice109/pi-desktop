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
├── PiDesktopApp.swift      # @main, Scene, SwiftData container
├── ContentView.swift       # Root view
├── Item.swift              # Template sample model (SwiftData)
└── Assets.xcassets/        # Asset catalog
```

> The template `Item` is a placeholder; replace it with real domain models (below).

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
│   ├── Models/     # SwiftData models
│   └── Services/   # Storage, logging, configuration
└── DesignSystem/   # Colors, type, glass wrappers, shared views
```

Rules:
- A feature folder is self-contained (views / view models / local components).
- Cross-feature capabilities sink into `Core/` or `DesignSystem/`.
- The agent layer exposes domain events only; it never leaks transport details.

## Data flow (target)

```
pi agent process/protocol
      │  event stream (AsyncStream)
      ▼
 Core/Agent  ──►  domain events  ──►  SessionStore (@Observable, @MainActor)
                                            │
                                            ▼
                                         SwiftUI Views
```

Principles:
- **Unidirectional data flow**: views read state and send intents; state changes live in stores.
- **Main-actor isolation**: UI state is marked `@MainActor`.
- **Transport/UI decoupling**: the agent layer never imports SwiftUI.

## Data model (planned)

- `Session` — a conversation: title, timestamps, working directory, status.
- `Message` — role (user/assistant/tool), content, timestamp, related tool call.
- `ToolCall` — tool name, arguments, status, result, duration.
- `AppSettings` — model, theme, preferences.

> Model changes are significant → require an ADR (see [decisions/](decisions/README.md)).

## Related
- UI spec: [design-system.md](design-system.md)
- pi integration: [pi-agent.md](pi-agent.md)
- Code style: [coding-conventions.md](coding-conventions.md)
