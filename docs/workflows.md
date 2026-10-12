# Workflows (Build / Test / Debug / Commit)

[English](workflows.md) · [简体中文](workflows.zh-CN.md)

## 1. Environment

- macOS 27.0+, Xcode with a matching SDK.
- No third-party dependencies yet.
- Scheme: `PiDesktop` — committed as a shared scheme at
  `PiDesktop.xcodeproj/xcshareddata/xcschemes/PiDesktop.xcscheme`, so `-scheme` works from a fresh
  clone and CI without relying on Xcode autocreation. It includes the `PiDesktopTests` test target.

> **About shared schemes**: `xcuserdata/` is user-local state and is gitignored. The shared scheme is
> committed so run/test/archive behavior is explicit and reproducible. If you add targets or test
> bundles, update the scheme (Scheme ▸ Manage Schemes in Xcode, or edit the XML directly).
>
> **About `requires Xcode`**: if `xcodebuild` reports it, `xcode-select` points at CommandLineTools.
> Fix with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, or set
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for a single command.

## 2. Build

```bash
# Debug
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build

# Release
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Release build

# Isolated DerivedData (easy to clean)
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop \
  -derivedDataPath .build/DerivedData build
```

## 3. Run & debug

```bash
open PiDesktop.xcodeproj   # then ⌘R in Xcode
```

- Breakpoints / LLDB: inside Xcode.
- View debugging: Xcode "Debug View Hierarchy".
- Previews: `#Preview` in source.
- Console: the Xcode console pane.

## 4. Tests

```bash
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop test
```

- Add unit tests for new logic; add UI tests for critical flows.
- Test naming: `test_<behavior>_<condition>_<expectation>`.
- The `PiDesktopTests` target hosts unit tests (e.g. `SessionModelTests`) backed by an in-memory
  SwiftData container. Hold the `ModelContainer` for the test's lifetime: a `ModelContext` does not
  retain its container, and using a context after its container is deallocated crashes (SIGTRAP).
- `PiRPCClientIntegrationTests` launches a real `pi` subprocess and is **skipped by default** (it calls
  a model and costs money). Enable it with `PI_INTEGRATION_TESTS=1` or by creating
  `/tmp/pi_integration_enabled`.

## 5. Clean & troubleshoot

```bash
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop clean
xcodebuild -list -project PiDesktop.xcodeproj
xcodebuild -showBuildSettings -project PiDesktop.xcodeproj -scheme PiDesktop | grep -i -E "SDK|DEPLOYMENT"
```

| Symptom | Check |
| --- | --- |
| `requires Xcode` | `xcode-select` points at CommandLineTools, see §1 |
| scheme not found | target/scheme names match; this project autocreates its scheme |
| signing fails | Xcode account / `DEVELOPMENT_TEAM` |
| glass / new API unavailable | deployment target and SDK actually support it |
| SwiftData container crash | model schema and migration |

### CI

CI is **temporarily disabled**: `.github/workflows/ci.yml.disabled` (GitHub only runs `*.yml`, so it is
inert). It is kept as the build recipe; the deployment target is macOS 27.0 and GitHub-hosted runners
may not yet ship a matching Xcode/SDK. Re-enable by renaming it to `ci.yml` once a suitable runner
(hosted or self-hosted) exists.

The workflow (and local runs) share [`scripts/ci.sh`](../scripts/ci.sh), which builds and tests and
selects `DEVELOPER_DIR` when `xcodebuild` cannot find Xcode. Run it directly:

```bash
./scripts/ci.sh
```

### Formatting & lint

[`scripts/format.sh`](../scripts/format.sh) uses the `swift-format` bundled with Xcode (no third-party
dependency) with the repo's [`.swift-format`](../.swift-format) config:

```bash
./scripts/format.sh          # check (non-zero on any finding)
./scripts/format.sh --fix    # format in place
```

## 6. Commit conventions

[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>
```

- **type**: `feat` `fix` `refactor` `perf` `docs` `style` `test` `build` `chore` `ci`
- **scope**: `chat` `session` `settings` `workspace` `agent` `glass` `docs`, etc.
- **subject**: imperative, no period, ≤ 50 chars
- **body**: explain "why"
- **footer**: `BREAKING CHANGE:` / `Closes #123`

Pre-commit checklist:
- [ ] `xcodebuild ... build` passes
- [ ] no new warnings
- [ ] `./scripts/format.sh` is clean; keep formatting-only changes in their own commit
- [ ] no secrets / personal paths / `xcuserdata`
- [ ] affected docs updated ([README.md](README.md) rules)
- [ ] significant trade-offs have an ADR

Example:
```
fix(session): stop message list flicker when switching sessions

The list used array indices as identity, mis-reusing rows after a switch.
Use stable ids instead.

Closes #42
```

## 7. Branching (recommended)

- `main` stays buildable.
- Branches: `feat/<scope>`, `fix/<scope>`.
- Merge only when build + tests pass and docs are synced.

## 8. Do not

- Commit `xcuserdata`, `.DS_Store`, or build output.
- Commit secrets / tokens / absolute personal paths.
- Use meaningless messages (`update`, `wip`, `fix bug`).
- Skip the §6 checklist.
