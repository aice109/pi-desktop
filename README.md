# PiDesktop

[![Platform](https://img.shields.io/badge/platform-macOS%2027%2B-black)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange)](https://swift.org)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](#status)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

**English** · [简体中文](README.zh-CN.md)

A native macOS GUI for the [pi coding agent](https://github.com/earendil-works/pi): manage sessions, watch tool calls unfold, and keep project context — all in a first-class Mac app.

> ⚠️ **Status: early.** Session management and streaming chat with the pi agent work today;
> tool-call visualization, workspace context, and settings are in progress.

---

## Features

Planned / in progress:

- 🗂 **Session management** — create, list, resume, and organize agent sessions.
- 💬 **Streaming chat** — render assistant output and reasoning as it arrives.
- 🛠 **Tool-call visualization** — cards showing tool name, arguments, live output, status, and duration.
- 📁 **Workspace context** — attach projects and files to a session.
- ⚙️ **Settings** — model selection, preferences, and theme.
- 🪟 **Native look** — built with Apple frameworks and macOS **Liquid Glass**.

See [`docs/architecture.md`](docs/architecture.md) and [`docs/pi-agent.md`](docs/pi-agent.md) for the design.

---

## Requirements

- macOS **27.0** or later
- Xcode with a matching SDK (Swift 5, SwiftUI, SwiftData)

## Getting Started

```bash
git clone https://github.com/aice109/pi-desktop.git
cd PiDesktop

# Build from the command line
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build

# Or open in Xcode and press ⌘R
open PiDesktop.xcodeproj
```

> If `xcodebuild` reports `requires Xcode`, point the toolchain at Xcode:
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.

Full build/test/debug commands and troubleshooting: [`docs/workflows.md`](docs/workflows.md).

---

## Project Structure

```
PiDesktop/
├── AGENTS.md                  # Rules & doc index for AI agents / contributors
├── README.md                  # This file (English)
├── README.zh-CN.md            # 简体中文
├── CONTRIBUTING.md            # How to contribute
├── LICENSE                    # MIT
├── .github/                   # CI, issue & PR templates
├── scripts/                   # Developer tooling (icon generator)
├── PiDesktop.xcodeproj/       # Xcode project
├── PiDesktop/                 # App source
└── docs/                      # Documentation (English default + zh-CN)
    ├── README.md              # Doc index
    ├── architecture.md
    ├── design-system.md
    ├── coding-conventions.md
    ├── workflows.md
    ├── pi-agent.md
    └── decisions/             # Architecture Decision Records (ADRs)
```

---

## Design Principles

1. **Native first** — prefer Apple frameworks (SwiftUI, AppKit, SwiftData); don't reinvent built-ins.
2. **Liquid Glass** — follow the macOS design language with system glass APIs, never hand-rolled blur.
3. **Ask before adding** — third-party dependencies and custom components require explicit approval first (see [`AGENTS.md`](AGENTS.md)).
4. **Documentation-driven** — rules and details are layered; code changes ship with doc updates.

---

## Documentation

- **Agents / contributors: start with [`AGENTS.md`](AGENTS.md).**
- Doc index: [`docs/README.md`](docs/README.md)
- Architecture: [`docs/architecture.md`](docs/architecture.md)
- Design system: [`docs/design-system.md`](docs/design-system.md)
- Workflows: [`docs/workflows.md`](docs/workflows.md)
- 中文文档：[`README.zh-CN.md`](README.zh-CN.md) · [`AGENTS.zh-CN.md`](AGENTS.zh-CN.md)

---

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). In short: read `AGENTS.md`, follow [Conventional Commits](https://www.conventionalcommits.org/), keep the build green, and update docs with your code. Significant trade-offs need an ADR.

## Security

Please report vulnerabilities privately — see [`SECURITY.md`](SECURITY.md).

## License

Released under the [MIT License](LICENSE). © 2026 PiDesktop contributors.
