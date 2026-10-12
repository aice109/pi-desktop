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
| Rich text / Markdown | Native `Text` / `AttributedString` first; complex rendering requires approval |

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
- **Icons**: SF Symbols with `.symbolRenderingMode` / `.imageScale`.

> New tokens: extend this section first, then code. Significant design trade-offs → ADR.

### Chat surface

- Messages live in a plain `List` with hidden row separators; consecutive messages from the same role
  share one header (role avatar + name) to cut visual noise.
- User messages render in a tinted bubble (`.tint.opacity(0.12)`); assistant messages are plain text so
  Markdown stays readable.
- The composer is a rounded field with a focus ring and a `.borderedProminent` circular send button
  (⌘↩). The streaming status line sits in a `.thinMaterial` `Capsule` — a system-intended overlay, not
  a hand-rolled blur.
- Tool calls use an SF Symbol mapped from the tool name, a monospaced argument chip, and a red outline
  on failure.
- Usage is a `Gauge` (`.accessoryLinearCapacity`) plus `.monospacedDigit()` labels, so the numbers do
  not jitter as they update.

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
