# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial macOS SwiftUI + SwiftData project scaffold.
- Documentation system: `AGENTS.md` (rules + progressive disclosure) and `docs/`
  (architecture, design system, coding conventions, workflows, pi-agent integration, ADRs).
- English-default documentation with Chinese (`*.zh-CN.md`) mirrors.
- Community health files: contributing guide, code of conduct, security policy.
- CI workflow, issue and pull request templates.
- `.gitignore` covering Xcode user state, build output, and secrets.
- Real SwiftData domain models `Session` / `Message` replacing the template `Item`
  (ADR-0004), with unit tests for append/persist and cascade delete.
- `PiDesktopTests` unit-test target and a committed shared scheme
  (`PiDesktop.xcscheme`) that includes it.
- ADR-0003 (Accepted): pi transport and app sandbox / entitlements.
- ADR-0004 (Accepted): SwiftData domain model (Session / Message).
- pi integration over RPC (`pi --mode rpc`): `Core/Agent` (`AgentEvent`, `AgentTransport`,
  `PiRPCClient`, `RPCProtocol`), a `SessionStore`, and a streaming `ChatView`. Verified end-to-end
  against a real pi subprocess (opt-in integration test).
- Workspace-scoped session browsing (ADR-0005): pick a project folder, list that folder's pi sessions
  (`Core/Pi`), and resume one via `pi --session`. New sessions are persisted by pi, and a
  `WorkspaceStore` remembers the chosen folder. Opening a session mirrors its history locally.
- Tool-call visualization (ADR-0006): tool calls are captured from live events and persisted as
  `ToolCall` rows, then rendered as cards with name, arguments, status, duration, and collapsible
  output. Historical `toolResult` entries are imported too.
- Per-session model and thinking-level selection, plus a usage footer (context %, total tokens, cost)
  backed by `get_available_models`, `set_model`, `set_thinking_level`, and `get_session_stats`.

### Changed
- App Sandbox disabled and the `files.user-selected` entitlement removed to allow
  the subprocess transport (ADR-0003); the app runs unsandboxed with hardened runtime.
- Session list sorted by most-recent activity instead of relying on undefined
  insertion order.
- Assistant and user messages render with native Markdown (bold, inline code, links) instead of raw
  text; each message shows a role icon and timestamp.
- The session sidebar gained search, a refresh action (⌘R), a new-session shortcut (⌘N), and a
  "move to Trash" action that also cleans up the local mirror.
- App version aligned to `0.1.0` (`MARKETING_VERSION`) to match the README badge;
  nothing has been released yet, so the changelog stays under `[Unreleased]`.

### Removed
- Template `Item` model.

### Fixed
- A response whose shape did not deserialize (for example `contextUsage.percent` arriving as a
  decimal) silently hung the pending request forever. Undecodable `response` lines now release their
  request, and the stats DTOs match pi's actual field types.

### Notes
- Released under the MIT License.
- Personal signing and identity values were removed from the Xcode project;
git history was rewritten so no prior revision contains them.

[Unreleased]: https://github.com/aice109/pi-desktop/commits/main
