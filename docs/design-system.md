# Design System / Liquid Glass

[English](design-system.md) · [简体中文](design-system.zh-CN.md)

This page defines PiDesktop's visual and interaction spec. **Read it before writing or reviewing any UI.**

## 1. Core principles

1. **Native first** — if an Apple component can do it, don't build your own.
2. **System glass** — use the Liquid Glass APIs; never fake the material with custom blur/tints.
3. **Semantic appearance** — prefer `.tint`, `.controlSize`, `.background(.regularMaterial)`, etc.
4. **Respect the system** — adapt to light/dark, increased contrast, and reduced transparency.

## 2. Liquid Glass usage

macOS Liquid Glass provides system-level materials. Prefer these APIs (by availability):

| Use case | API |
| --- | --- |
| Glass background on a view | `.glassEffect(_:in:)` |
| Combine/morph multiple glass elements | `GlassEffectContainer` + `glassEffectID` |
| Glass buttons | `.buttonStyle(.glass)` / `.glassProminent` |
| AppKit bridging | `NSGlassEffectView` |

Example:

```swift
// Glass card
content
    .padding()
    .glassEffect(.regular, in: .rect(cornerRadius: 16))

// Coordinated elements inside a glass container
GlassEffectContainer(spacing: 16) {
    HStack {
        Button("New session") { }.buttonStyle(.glass)
        Button("Settings") { }.buttonStyle(.glass)
    }
}
```

Constraints:
- Use glass in system-intended places (toolbars, overlays, cards, control backgrounds); don't stack it everywhere.
- Never layer custom `Material`/blur/translucent gradients on top of glass.
- Keep system motion; before writing custom animation, confirm the native option is insufficient and ask per §4.
- API availability tracks the SDK: verify real signatures for the deployment target (macOS 27.0); don't invent them.

## 3. Component selection

| Need | First choice |
| --- | --- |
| List / table | `List`, `Table` |
| Sidebar navigation | `NavigationSplitView` |
| Toolbar | `.toolbar` + `ToolbarItem` |
| Settings | `Settings` scene / `Form` |
| Menus | `Menu`, `.contextMenu` |
| Dialogs | `.sheet`, `.popover`, `.alert`, `.confirmationDialog` |
| Icons | SF Symbols |
| Rich text / Markdown | Native `Text` / `AttributedString` first; block-level rendering via `MarkdownText` (Foundation intents + SwiftUI primitives) |

## 4. Third-party or custom components: ask first

Before adding the following, **explain and get approval** (see [AGENTS.md §2.3](../AGENTS.md)):

- Third-party dependencies (SPM, etc.)
- Hand-drawn controls / custom drawing / custom animation engines
- Non–SF Symbols icon sets, third-party fonts, design assets
- Invasive replacements of a native component that would otherwise work

Ask with:
1. **Why native is insufficient** — the specific missing capability.
2. **Options** — native approximation vs third-party/custom, pros and cons.
3. **Impact** — size, maintenance, license, consistency with glass/accessibility.

## 5. Visual tokens (conventions)

- **Color**: semantic colors first (`.primary`, `.secondary`, `Color.accentColor`, `.tint`). Brand color via the `AccentColor` asset.
- **Type**: system font + semantic styles (`.body`, `.headline`, `.caption`) via `.font(...)`; avoid hard-coded sizes.
- **Spacing**: multiples of 4/8; use shared constants instead of scattered magic numbers.
- **Corner radius**: match the system; give glass containers an explicit `.rect(cornerRadius:)`.
  App-internal radii come from `DesignTokens.Radius` (`chip` 4, `small` 6, `card` 8, `control` 10) —
  deliberately small to stay close to native controls.
- **Icons**: SF Symbols with `.symbolRenderingMode` / `.imageScale`.

> New tokens: extend this section first, then code. Significant design trade-offs → ADR.

### Sidebar

- The workspace header is a tinted folder badge plus the directory name/path and the workspace menu;
  the old hard divider is gone — the section header separates the list instead.
- Sessions live in a `.sidebar` `List` under a "Sessions" section header that also carries the count.
  Rows are one icon + title + a secondary line (relative time · message count) with a few points of
  vertical padding, so each row reads as its own target.
- A turn that finishes while its session is not the visible one shows a tinted unread dot at the row's
  trailing edge; opening the session clears it. The same event posts a system notification
  (`UserNotifications`) when the app is in the background — see `Core/Notifications/TurnNotifier.swift`.

### Chat surface

- Messages live in a plain `List` with hidden row separators; consecutive messages from the same role
  share one header (role avatar + name) to cut visual noise.
- The timeline is grouped into **turns** (a user message up to the next one). Only each turn's final
  assistant text — the conclusion — stays expanded; reasoning, tool calls, and intermediate assistant
  narration collapse behind `DisclosureGroup`s.
- Collapsed rows use a shared `DisclosureGroupStyle` (`RowDisclosureGroupStyle`): the whole header line
  is a button with `contentShape(Rectangle())`, so it is easy to hit, the chevron keeps the system look,
  and expanded content is indented instead of sitting flush against the edge.
- The message list, composer, status capsule, and usage footer share the same 16 pt horizontal margin,
  so the column edges line up.
- Assistant text renders as block-level Markdown (`MarkdownText`): headings, paragraphs,
  ordered/unordered lists, fenced code blocks, block quotes, thematic breaks, and tables (`Grid`).
  It is built on Foundation's `AttributedString(markdown:)` + `PresentationIntent` and SwiftUI
  primitives; no third-party dependency. Inline formatting (bold, inline code, links) is preserved.
- User messages render in a tinted bubble (`.tint.opacity(0.12)`); assistant messages are plain text so
  Markdown stays readable.
- The composer is a rounded field with a focus ring and a `.borderedProminent` circular send button
  (⌘↩). The streaming status line sits in a `.thinMaterial` `Capsule` — a system-intended overlay, not
  a hand-rolled blur.
- While the agent runs the composer stays enabled: Enter queues a **steering** message (the send
  control becomes a `Menu` whose primary action steers, offering "Send as Follow-up"). Queued messages
  appear under the status line with a "Clear Queued" link that restores their text to the composer.
- A toolbar magnifier opens a search popover over the conversation; results match message text and tool
  arguments/output, and selecting one scrolls the message list to that row.
- The toolbar has a Context menu (`arrow.down.right.and.arrow.up.left`): "Compact Now", "Compact with
  Instructions…" (a small sheet), an Auto-compaction `Toggle` bound to `get_state`, and an Auto-retry
  `Toggle`. While a retry is in progress the status line shows an "Abort Retry" link.
- The toolbar has a Branch menu (`arrow.triangle.branch`) offering "Clone Session" and "Fork from
  Message…"; the latter opens a sheet listing forkable user messages. Selecting one forks and puts the
  original text back in the composer, so the same flow doubles as edit-and-resend.
- A draft starting with `!` runs a direct shell command (nothing is sent to the model); a small
  "Running shell command…" row with an Abort link appears until it finishes.
- Typing `/` in the composer shows an inline suggestion list of pi commands (extension / prompt /
  skill) with description and source chips; selecting one fills `/name ` without sending. A toolbar
  command menu offers the same list for discoverability.
- Images attach from the pasteboard, a drag-and-drop onto the composer, or the paperclip's file
  importer. Pending images show as removable 56 pt thumbnails above the field; sent images render at
  up to 200 pt in the user bubble ([ADR-0010](decisions/0010-image-attachments.md)).
- Tool calls collapse to a single summary line (SF Symbol, tool name, argument chip, status) and expand
  to `Arguments` / `Output`; failures keep the red outline.
- Usage is a `Gauge` (`.accessoryLinearCapacity`) plus `.monospacedDigit()` labels, so the numbers do
  not jitter as they update.
- The message list follows the bottom while the agent streams. Once the user scrolls up, following
  pauses and a glass "scroll to latest" button (`.buttonStyle(.glass)`) appears; tapping it resumes
  following. Following is **intent-based** (`isFollowingBottom`, updated from `onScrollGeometryChange`
  + `onScrollPhaseChange`) rather than a raw distance check, so streaming growth does not stop the
  follow just because the content got taller.
- Opening a session shows a glass loading card (`ProgressView` + `.glassEffect`) until the mirrored
  history first renders; `SessionStore.isLoading(_:)` exposes the state for the duration of `activate`.
- The model and thinking-level toolbar menus use `Toggle` items bound to the current selection, which
  renders native menu checkmarks. Models are compared by `provider` + `id`, since the metadata returned
  by `get_state` and `get_available_models` can differ (`name`, `contextWindow`).

## 6. Accessibility

- Every interactive element needs a readable label (`.accessibilityLabel`).
- Support keyboard navigation and VoiceOver.
- Never rely on color alone to convey state; adapt to Dynamic Type and contrast settings.

## 7. UI checklist

- [ ] Native components used; no reinvention of built-ins
- [ ] Glass comes from system APIs; no hand-rolled blur
- [ ] Semantic colors/fonts; no hard-coded magic numbers
- [ ] Keyboard shortcuts are also reachable from a menu (`Commands` / `FocusedValue`)
- [ ] Light/dark and accessibility adapted
- [ ] Third-party/custom components approved (or covered by an ADR)
