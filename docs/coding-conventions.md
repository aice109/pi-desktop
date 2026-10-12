# Coding Conventions

[English](coding-conventions.md) · [简体中文](coding-conventions.zh-CN.md)

For Swift / SwiftUI code. Read before writing code.

## 1. General

- Follow the Swift API Design Guidelines and existing code style.
- Commit in small steps; every change should be small and compilable.
- Don't refactor unrelated code unless it directly serves the task.
- Prefer clear > terse > clever.

## 2. Naming

- Types `UpperCamelCase`; methods/properties/variables `lowerCamelCase`.
- Booleans use `is/has/should/can` (`isLoading`).
- Avoid abbreviations (`vc`, `mgr`) except domain terms.
- Views are always `XxxView`; models use domain names.

## 3. File organization

- **One primary type per file**, file name matches the type.
- Organize by feature domain (see [architecture.md](architecture.md)).
- Small related types (private subviews) may share a file, kept readable.

## 4. SwiftUI

- Keep views **declarative and side-effect free**; put side effects in view models/stores.
- Split large views; avoid giant `body`s; provide `#Preview`s.
- State priority: `@State` → `@Observable` model → `@Environment`; use `@StateObject`/`@ObservedObject` sparingly (prefer Observation).
- Mark UI-state types `@MainActor`.
- Keep modifier order readable; extract complex styling into `ViewModifier`/`View` extensions in `DesignSystem/`.

## 5. Concurrency

- Use Swift Concurrency (`async/await`, `Task`, `actor`, `AsyncStream`).
- Update UI on the main actor; cross-actor values must be `Sendable`.
- Long-lived tasks must be cancelable; avoid task leaks.
- Don't start uncontrolled `Task`s from `body`.

## 6. Data & persistence

- SwiftData: `@Model` types stay pure data + light logic.
- Query with `@Query` / `FetchDescriptor`; avoid heavy computation in views.
- Model changes may need migration and require an ADR.

## 7. Error handling

- Express recoverable errors with `throws` / `Result`; avoid silent failures.
- Show users understandable errors; don't leak stack traces.
- `fatalError` is acceptable for unrecoverable startup failures; everything else uses error paths.

## 8. Dependencies & encapsulation

- Abstract external capabilities (transport, storage) behind protocols for replaceability/testing.
- **Ask before adding any third-party dependency** (see [AGENTS.md §2.3](../AGENTS.md)).

## 9. Comment rules

**General rule: comment generously, but not everything.** When unsure, ask "will this save the next
reader five minutes?" If yes, write it; if no, drop it.

### 9.1 When you must comment

- **Public API / types**: `///` doc comments covering purpose, parameters, returns, side effects.
- **Non-obvious "why"**: redundant-looking checks, special branches, compatibility paths — explain the reason.
- **Constraints & pitfalls**: concurrency/threading requirements, lifetime, call order, hidden system-API behavior.
- **Magic numbers / strings**: explain their origin or meaning.
- **Workarounds**: state the reason and removal condition, e.g. `// TODO(#123): remove once X is fixed.`
- **Complex algorithms / non-intuitive logic**: outline the idea/invariant before the implementation.
- **File/type responsibility**: one line at the top of each type saying what it owns (especially stores/services/view models).

### 9.2 When not to comment

- **Self-explanatory code**: `title = "Settings"` needs no `// set the title`.
- **Restating signatures**: `/// Fetch user` on `func fetchUser()` is noise.
- **Commented-out dead code**: delete it; use git history when needed.
- **Over-segmenting**: a heading comment on every line drowns the important parts.
- **Comments out of sync with code**: worse than none; update them when you change code.

### 9.3 Style

- Keep the Xcode header; don't pile on extra boilerplate.
- Use `//` above the code it explains (not trailing alignment), unless it's very short.
- English by default; bilingual is fine for public/open-source APIs.

## 10. Quality gate

- Build is green, no new warnings.
- No force-unwrap `!` (unless guaranteed and commented).
- No leftover `print` (use logging).
- No hard-coded secrets or absolute paths.
