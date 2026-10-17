# AGENTS.md

[English](AGENTS.md) · [简体中文](AGENTS.zh-CN.md)

> The single entry point for AI agents and contributors working in this repo.
> Read this file first (the most important rules live here), then open only the docs listed under
> **Progressive disclosure** that match your task. **Do not load every doc at once.**

---

## 1. What this project is

PiDesktop is a **native macOS GUI** for the [pi coding agent](https://github.com/earendil-works/pi)
(sessions, tool-call visualization, workspace context, settings).

- Platform: macOS (`MACOSX_DEPLOYMENT_TARGET = 27.0`)
- Language / UI: Swift 5 + SwiftUI (AppKit when needed)
- Persistence: SwiftData
- Project: `PiDesktop.xcodeproj`
- Goal: a native, lightweight, Mac-native pi agent client

---

## 2. Non-negotiable rules (MUST / MUST NOT)

Hard constraints. Violating them is a bug, and they must **never** be bypassed on your own.

### 2.1 Native components first (MUST)
- Prefer **Apple frameworks and components**: SwiftUI, AppKit, Foundation, SwiftData, Observation.
- If a built-in view/modifier can do it, **do not** build your own.
- Use `NSViewRepresentable` / `NSViewControllerRepresentable` for AppKit bridging, and keep bridging code centralized.

### 2.2 Liquid Glass (MUST)
- Follow the macOS **Liquid Glass** design language: `.glassEffect()`, `GlassEffectContainer`,
  `glassEffectID`, `.buttonStyle(.glass)`, and `NSGlassEffectView` (AppKit bridging).
- Use glass only in system-intended places; **never** fake it with custom blur or translucent fills.
- For custom looks, prefer semantic APIs: `.tint`, `.controlSize`, `.background(.regularMaterial)`.

### 2.3 Ask before adding third-party or custom components (MUST ASK)
Before any of the following, **explain the reason, present options, and get explicit approval**:
- Adding any **third-party dependency** (SPM / CocoaPods / binary / vendored source).
- Writing a **custom component** that replaces an existing system capability.
- Adding non–SF Symbols icons, third-party fonts, or design assets.
- Changing build configuration, the dependency graph, code signing, or entitlements.

When asking, cover: **why native isn't enough → option comparison → impact** on size, maintenance, licensing.
Until approved, ship the smallest viable native implementation.

### 2.4 Other hard constraints
- Never commit secrets, tokens, personal paths (`/Users/xxx`), or `xcuserdata`.
- Don't delete or rewrite files/history unrelated to your task.
- Read the relevant docs and existing code before changing behavior; follow existing patterns.
- **Comment generously, but not everything**: comment what isn't obvious; don't add noise to self-explanatory code. See [`docs/coding-conventions.md`](docs/coding-conventions.md) §9.

---

## 3. Progressive disclosure

**The root file holds rules; details live in `docs/`.** Load only what your task needs:

| If you are going to… | Load |
| --- | --- |
| Understand modules, data flow, layout | [`docs/architecture.md`](docs/architecture.md) |
| Write or review UI, glass, color, motion | [`docs/design-system.md`](docs/design-system.md) |
| Write Swift: naming, concurrency, errors | [`docs/coding-conventions.md`](docs/coding-conventions.md) |
| Build / run / test / debug / commit | [`docs/workflows.md`](docs/workflows.md) |
| Work on pi agent integration, protocol, sessions | [`docs/pi-agent.md`](docs/pi-agent.md) |
| Make a significant trade-off | [`docs/decisions/`](docs/decisions/README.md) |
| Find the doc entry point | [`docs/README.md`](docs/README.md) |
| Read docs in Chinese | `docs/*.zh-CN.md` |

Rules:
- **Read only what the task needs** to keep context small.
- For cross-cutting tasks, load docs from the table in order — don't grep the whole repo.
- When adding knowledge, update the **existing** doc it belongs to instead of scattering new files.

---

## 4. Common commands

```bash
# Build
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build

# Run
open PiDesktop.xcodeproj   # then ⌘R in Xcode

# Production release (CI gate + Release DMG + identity check)
./scripts/release.sh
```

> If `xcodebuild` says `requires Xcode`: `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
> Full commands and troubleshooting: [`docs/workflows.md`](docs/workflows.md).

---

## 5. Commit rules

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body: WHY this change, not what>

<footer: BREAKING CHANGE / Closes #issue>
```

- **type**: `feat` `fix` `refactor` `perf` `docs` `style` `test` `build` `chore` `ci`
- **scope**: module, e.g. `chat` `session` `settings` `glass` `docs` (optional but recommended)
- **subject**: imperative, no trailing period, ≤ 50 chars
- **one commit = one thing**; keep formatting-only changes separate from logic changes
- Before committing: build is green, no new warnings, docs synced (§6)
- **Forbidden**: `update`, `fix bug`, `wip`; committing commented-out dead code

Example:
```
feat(chat): stream pi tool-call cards as events arrive

Tool cards previously appeared only after completion, hiding the
in-progress state. Subscribe to incremental events and render by type.

Refs: docs/pi-agent.md#event-model
```

---

## 6. Documentation rules

- **Single source of truth**: describe knowledge once; link from elsewhere.
- **Docs ship with code**: changing architecture/APIs/UI specs/commands requires updating the matching doc.
- **Layers**:
  - Root `README.md`: overview and quick start for users/contributors.
  - `AGENTS.md` (this file): rules and index for agents; keep it lean.
  - `docs/*.md`: topic details, loaded on demand.
  - `docs/decisions/*.md`: append-only Architecture Decision Records (ADRs).
- **Two languages**: English is the default; Chinese mirrors use the `.zh-CN.md` suffix.
  Keep both in sync when you edit either; link them at the top of each doc.
- **ADR triggers**: new third-party dependency, core framework change, data-model/persistence change,
  or any wide-reaching trade-off → write an ADR first (template in [`docs/decisions/README.md`](docs/decisions/README.md)).
- Docs are Markdown, English by default; code fences declare a language; relative links must resolve.

---

## 7. Standard workflow

1. **Clarify** — ask when the request is ambiguous; don't guess.
2. **Load context** — read only the relevant docs (§3) and source.
3. **Plan** — items under §2.3 or architectural changes → ask first / write an ADR first.
4. **Implement** — native first, small commits, always compilable.
5. **Self-check** — builds clean, no warnings, UI matches the design system.
6. **Sync docs** — update affected docs; add an ADR when needed.
7. **Commit** — follow §5.

---

## 8. Key paths

| Path | Purpose |
| --- | --- |
| `PiDesktop/PiDesktopApp.swift` | App entry (Scene, SwiftData container) |
| `PiDesktop/ContentView.swift` | Root view |
| `PiDesktop.xcodeproj` | Xcode project |
| `docs/` | Documentation (load on demand) |
| `AGENTS.md` / `README.md` | Rules entry / usage overview |
