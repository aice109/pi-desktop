# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- The agent event model now covers pi's queue and session-state events: `queue_update`,
  `session_info_changed`, `thinking_level_changed`, `summarization_retry_*`, and `entry_appended`.
  External renames and thinking-level changes now propagate to the UI, summarization retries show in
  the status line, and an appended entry reconciles the local mirror when idle.
- The chat now follows new output only while the user is at the bottom. Scrolling up pauses the
  follow and shows a glass "scroll to latest" button; tapping it resumes. The follow is intent-based,
  so streaming growth no longer stops it prematurely.
- Opening a session shows a glass loading card until its mirrored history first renders, and switching
  sessions cross-fades instead of flashing an empty detail pane.
- Block-level Markdown rendering in the chat (`MarkdownText`, native): headings, paragraphs,
  ordered/unordered lists, fenced code blocks with a language label, block quotes, thematic breaks,
  and tables (`Grid`), built on Foundation's `AttributedString(markdown:)` + `PresentationIntent` with
  no third-party dependency.
- The chat timeline is grouped into turns; only each turn's final assistant text stays expanded, while
  reasoning, tool calls, and intermediate narration collapse behind `DisclosureGroup`s. Tool cards now
  collapse to a one-line summary and expand to Arguments / Output.
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
- Session rename through pi's `set_session_name` (sidebar context menu). Historical tool calls now
  import their arguments from the assistant's `toolCall` blocks.
- Assistant reasoning is persisted (`Message.thinking`, ADR-0007) and shown as a collapsible section;
  history imports it from the session file's `thinking` blocks.
- Retry and compaction activity is surfaced in the chat status line (`auto_retry_*` / `compaction_*`).
- A preferences window (⌘,) backed by `AppSettingsStore` in `UserDefaults` (ADR-0008): theme,
  reopen the last session, usage footer, and delete confirmation.
- File and Session menus (New Session ⌘N, Open Workspace ⌘O, Refresh ⌘R, Stop ⌘., Close Workspace)
  that act on the focused window through `FocusedValue`.
- The last opened session is reopened on launch (toggleable in Settings).
- History is reconciled with pi on open (ADR-0009): the session file is read first, then `get_entries`
  over RPC, so turns made outside the app appear. Rebuilds are skipped when nothing changed.

### Changed
- The model and thinking-level toolbar menus now render native checkmarks via `Toggle` items and keep
  the current selection in the list; models are compared by `provider` + `id` because the metadata from
  `get_state` and `get_available_models` can differ.
- History normalization from `get_entries` runs off the main actor, and the mirror rebuild yields once
  before its synchronous batch insert, so the loading animation can render before the work starts.
- UI polish: the sidebar gains a folder-badge workspace header and a counted "Sessions" section;
  app-internal corner radii are smaller and centralized in `DesignTokens.Radius`; chat collapses are
  now full-row tap targets with indented content, and the message list, composer, status capsule, and
  usage footer share one 16 pt horizontal margin.
- App Sandbox disabled and the `files.user-selected` entitlement removed to allow
  the subprocess transport (ADR-0003); the app runs unsandboxed with hardened runtime.
- Session list sorted by most-recent activity instead of relying on undefined
  insertion order.
- Assistant and user messages render with native Markdown (bold, inline code, links) instead of raw
  text; each message shows a role icon and timestamp.
- The session sidebar gained search, a refresh action (⌘R), a new-session shortcut (⌘N), and a
  "move to Trash" action that also cleans up the local mirror.
- The workspace bar is now a menu with recent folders and "Close Workspace"; Stop also has a ⌘.
  shortcut.
- App version aligned to `0.1.0` (`MARKETING_VERSION`) to match the README badge;
  nothing has been released yet, so the changelog stays under `[Unreleased]`.
- Chat and sidebar polish: role avatars, merged headers for consecutive messages, a tinted user
  bubble, per-tool icons and argument chips on tool cards, a focus-ringed composer with a circular
  send button (⌘↩), a context-usage gauge, and a session count in the workspace bar.

### Removed
- Template `Item` model.

### Fixed
- A prompt that pi handled immediately (an extension command or input handler) never emitted
  `agent_settled`, so the assistant placeholder spun forever. `prompt` now returns the response's
  `disposition`, and a `handled` prompt is finalized right away.
- After the pi process exited, the transport kept a stale handle: later prompts were silently dropped
  because the client believed a process was still running. Exit and stdout-close now release the
  process and its pipes, so the next command relaunches pi and the existing event stream keeps working.
- The current model and thinking level could appear unselected in the toolbar menus: selection was
  compared by the whole `AgentModel` value (including `name` / `contextWindow`), which can differ
  between pi commands. Selection now matches on `provider` + `id` and always includes the active value.
- Opening a session with a long history froze the app: the mirror rebuild appended each `Message` /
  `ToolCall` to the SwiftData relationship one by one, which is O(n²) (~32 s for 6,000 rows) and blocked
  the main actor, leaving the sidebar stuck on "Loading…". Rows are now registered in bulk and the
  relationship assigned once (~0.15 s for 6,000 rows). The chat timeline and header flags are also
  computed once per render instead of being re-sorted inside every row.
- Tool-call cards from a loaded history spun forever: the card treated a missing `durationMs` as
  "still running", but historical imports never carry a duration. Running state now comes from the
  store's live tool registry, so finished/imported calls show a checkmark. This also removes the
  animation load of many permanent spinners in long sessions.
- A response whose shape did not deserialize (for example `contextUsage.percent` arriving as a
  decimal) silently hung the pending request forever. Undecodable `response` lines now release their
  request, and the stats DTOs match pi's actual field types.

### Notes
- Released under the MIT License.
- Personal signing and identity values were removed from the Xcode project;
git history was rewritten so no prior revision contains them.

[Unreleased]: https://github.com/aice109/pi-desktop/commits/main
