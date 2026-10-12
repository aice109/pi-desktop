# Contributing to PiDesktop

[English](CONTRIBUTING.md) · [简体中文](CONTRIBUTING.zh-CN.md)

Thanks for your interest in PiDesktop! This guide covers how to get set up and how to get a change merged.

## Before you start

Read [`AGENTS.md`](AGENTS.md) — it holds the project's hard rules and the doc index. The essentials:

1. **Native first** — prefer Apple frameworks (SwiftUI / AppKit / SwiftData) over custom code.
2. **Liquid Glass** — use the system glass APIs; never fake the material.
3. **Ask before adding** — open an issue to discuss **before** introducing a third-party dependency, a custom component, a new asset set, or a build-config change.
4. **Docs ship with code** — update the matching doc; significant trade-offs need an ADR.

## Development setup

- macOS 27.0+ with Xcode (matching SDK)
- No third-party dependencies yet

```bash
git clone https://github.com/aice109/pi-desktop.git
cd PiDesktop
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build
open PiDesktop.xcodeproj   # ⌘R to run
```

See [`docs/workflows.md`](docs/workflows.md) for test/debug/troubleshooting.

## Ways to contribute

- 🐛 **Bug reports** — use the issue template; include macOS version, Xcode version, steps, expected vs actual.
- 💡 **Feature requests** — open an issue describing the problem and the desired outcome.
- 📝 **Docs** — fixes and translations welcome. English is the default; Chinese lives in `*.zh-CN.md`.
- 💻 **Code** — see the workflow below.

## Pull request workflow

1. **Open an issue first** for anything non-trivial, so we can agree on the approach.
2. **Fork & branch**: `feat/<scope>`, `fix/<scope>`, `docs/<topic>`.
3. **Keep it small** — one logical change per PR.
4. **Follow style**: see [`docs/coding-conventions.md`](docs/coding-conventions.md) and the design system.
5. **Comment meaningfully** — explain the "why"; don't restate the code.
6. **Build & test** locally; keep the build green with no new warnings.
7. **Update docs** (and add an ADR for significant decisions).
8. **Commit** with [Conventional Commits](https://www.conventionalcommits.org/): `feat(chat): ...`.
9. **Open the PR** and fill in the template; link the issue.

## Commit message format

```
<type>(<scope>): <subject>

<body: why, not what>

<footer: BREAKING CHANGE / Closes #123>
```

`type` ∈ `feat` `fix` `refactor` `perf` `docs` `style` `test` `build` `chore` `ci`.

## Review

- CI must pass and the branch must be up to date.
- A maintainer reviews for correctness, native-first adherence, and doc sync.
- Squash-merge keeps `main` linear and buildable.

## Code of Conduct

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing, you agree that your contributions are licensed under the project's [LICENSE](LICENSE).
