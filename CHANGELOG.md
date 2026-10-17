# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `scripts/release.sh` is the one-command production release entry point: it runs the CI gate,
  delegates the Release build and DMG assembly to `scripts/make-dmg.sh`, and refuses to package a
  build whose bundle id or display name is not the production identity.
- The icon generator now writes two asset sets: `AppIcon.appiconset` (production) and
  `AppIconDev.imageset` (the production icon with a large semi-transparent 「测」 capsule in the
  bottom-right corner).

### Changed
- The DEBUG build is now the clearly isolated test build: bundle id
  `io.github.aice109.PiDesktop.dev`, display name `Pi Desktop 测试版`, and a 「测」-badged Dock icon
  applied at launch under `#if DEBUG`. Release keeps `io.github.aice109.PiDesktop` and displays
  `Pi Desktop`. The `.app` / executable / module names stay `PiDesktop`, so the shared scheme and
  test host keep working.
- SwiftData now uses per-configuration stores (`Application Support/PiDesktop[-Dev]/default.store`)
  instead of the shared non-sandboxed `default.store`, so a Debug run can no longer overwrite the
  installed Release build's local mirror (ADR-0012). The mirror is rebuilt from pi's session files;
  the old `default.store` can be deleted manually.

## [0.2.0] - 2026-10-13

### Added
- A `scripts/make-dmg.sh` release packager builds an ad-hoc signed DMG with Apple's own tools
  (`xcodebuild` → `codesign` → `diskutil image create`), with `--sign` / `--notarize` options for the
  Developer ID distribution path. No third-party dependency is involved.
- UI strings are localizable through a String Catalog (`Localizable.xcstrings`), with an initial
  Simplified Chinese (`zh-Hans`) translation; untranslated keys fall back to English.
- A Chat menu "Retry Last Message" (⇧⌘R) re-sends the last user message after a process exit or error.
- Fenced code blocks are syntax-colored by a small native tokenizer (comments, strings, numbers,
  keywords), with a per-code cache and no third-party dependency.
- The Branch menu's "Show Tree…" renders the whole session tree (`get_tree`), including abandoned
  branches, with the active leaf highlighted, pi labels shown as bookmark chips, and a fork action on
  user nodes. The tree is flattened into a single row array instead of recursive `OutlineGroup`s, and
  the sheet loads it in the background so opening it is instant and never hangs.
- A toolbar button toggles a right-side **Conversation Anchors** inspector (off by default, remembered in
  Settings): one row per turn (number, prompt, and the conclusion's first line). Selecting a row scrolls
  the conversation to that turn, reusing the search scroll target; anchors come from the local mirror,
  so the list is available immediately.
- Turns that finish while the app is in the background post a system notification, and any session that
  finished off-screen gets an unread dot in the sidebar (cleared when opened, kept across launches).
- The agent event model now covers pi's queue and session-state events: `queue_update`,
  `session_info_changed`, `thinking_level_changed`, `summarization_retry_*`, and `entry_appended`.
  External renames and thinking-level changes now propagate to the UI, summarization retries show in
  the status line, and an appended entry reconciles the local mirror when idle.
- A toolbar find popover searches the open conversation (message text plus tool arguments/output) and
  scrolls to the selected result.
- Forking from a message now returns the original text and puts it back in the composer, so the flow
  doubles as edit-and-resend.
- A Chat menu cycles the model (⌃⌘M) and thinking level (⌃⌘T) via `cycle_model` /
  `cycle_thinking_level`, and copies the last assistant response (⇧⌘C) via `get_last_assistant_text`.
- A `!`-prefixed composer input runs pi's direct `bash`; output lands in the timeline/model context as
  a tool message, and a running command can be aborted. Historical `bashExecution` entries render the
  same way.
- The File menu exports the open session to a standalone HTML file via pi's `export_html`, using a
  save panel to choose the destination (⇧⌘E).
- Auto-retry can be toggled per session and an in-progress retry aborted from the status line
  (`set_auto_retry` / `abort_retry`). pi does not report the flag in `get_state`, so it is tracked
  locally, defaulting to on.
- The toolbar's Context menu can compact the conversation on demand (optionally with custom summary
  instructions) and toggle auto-compaction, backed by `compact` and `set_auto_compaction`.
- History follows the **active branch**: `get_entries` is a tree, so the mirror walks `parentId` back
  from `leafId` instead of flattening abandoned branches into one line. A Branch toolbar menu adds
  `clone` and `fork from a message`; both re-read `get_state` and fully reconcile afterwards.
- pi's discoverable commands are listed with `get_commands` and surfaced in a slash-command
  suggestion list (plus a toolbar menu) so extension commands, prompt templates, and skills can be
  inserted without memorizing names.
- History sync is incremental after the first load: `get_entries` is called with the last seen entry
  id as `since`, and only new entries are appended without touching existing rows. A missing or stale
  cursor, or a moved `leafId`, falls back to a full reconcile.
- Images can be attached to a message from the pasteboard, drag-and-drop, or a file picker. Sent
  images render in the user bubble and are persisted as `MessageImage` rows (ADR-0010); history
  imports pi's `image` blocks. The new `MessageImage` model joins the SwiftData schema.
- Messages can be queued while the agent is running: Enter sends a steering message (delivered after
  the current tool calls) and the send control's menu offers "Send as Follow-up". The status area lists
  the pending queue, and "Clear Queued" restores the text to the composer. Backed by pi's `steer`,
  `follow_up`, and `clear_queue` commands.
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
- The sidebar's minimum width now matches its default open width (`DesignTokens.Layout.sidebarWidth`,
  280pt) and is enforced with `.frame(minWidth:)` plus an AppKit bridge that pins the native sidebar split
  item's `minimumThickness`, so the workspace card and session titles are never shown truncated (and the
  divider no longer slips a few points before collapsing): dragging the divider inwards collapses the
  sidebar to detail-only (native `NavigationSplitView`), while dragging outwards still widens it.
- File paths in the sidebar and window subtitle are home-abbreviated (`~/Developer/PiDesktop`), and the
  chat subtitle now hides when the session's working directory matches the current project, so the same
  path is no longer shown in two places. The sidebar header is a large glass project-switcher card
  (badge, project name, a circled chevron, and the abbreviated path) that opens a popover with recent
  projects (the current one check-marked), "Choose Folder…", and "Close Workspace".
- The message list ends with a small "end of conversation" marker (a hairline rule around an
  `arrow.down.to.line` glyph) that doubles as bottom padding, and scroll indicators are inset from the
  list edges so their caps are not clipped.
- Each chat turn now renders one collapsible **process** section that gathers all of its intermediate
  reasoning, tool calls, and mid-turn narration (collapsed by default, summarised with a step count
  and the tools involved), leaving only the user message and the final conclusion visible.
- `scripts/ci.sh` also runs `scripts/format.sh` (swift-format lint) before building, so style is
  enforced alongside the build and tests.
- The main scene is a single `Window` instead of a `WindowGroup`, so the app-level stores (one
transport per session, a single visible-session id for unread/notifications) are always consistent
  (ADR-0011).
- `scripts/ci.sh` builds and tests with a working Xcode toolchain (selecting `DEVELOPER_DIR` when
  `xcodebuild` cannot find Xcode). The disabled CI workflow now calls the same script, so re-enabling
  it is a rename.
- Session summaries are cached by file path + modification time, so refreshing a workspace no longer
  re-scans every line of every unchanged session file. Modification time is read through
  `FileManager` (not `URL.resourceValues`, which caches per URL) so the cache invalidates correctly.
- Block-level Markdown is parsed through a process-wide `NSCache`, so scrolling, focus changes, and
  other unrelated re-renders no longer re-parse every message. Cached blocks keep stable ids, avoiding
  `ForEach` identity churn.
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
- Opening the session tree could freeze the app on long conversations: the recursive tree was rendered
  with `OutlineGroup`, which nests one view per entry, and real sessions are linear chains hundreds of
  entries deep. The tree is now flattened to a single-level `List` (`SessionTreeOutline.swift`), with
  indentation only at real branch points, and the sheet loads its data asynchronously instead of
  blocking the toolbar action.
- The final answer could appear above the tool calls that produced it: a single assistant message was
  created at send time and every streamed segment — including text emitted after tool calls — was
  appended to it, so it sorted before those calls. Assistant output is now split per pi message
  segment (the message is created lazily on the first delta and finalized at each `message_end`), so
  the conclusion lands after the tools.
- Manual compaction (and export / clone / fork) produced no on-screen feedback: the chat status area
  was rendered only while streaming, so an in-flight `compact` — or any of these one-shot operations —
  showed nothing at all. The status area now appears whenever a session has any in-flight work
  (`SessionStore.isBusy`), with an indeterminate progress indicator and localized text; the compact
  entries disable themselves while one runs, and a successful compaction reconciles the mirror.
- One-shot operations returned success / failure that the UI ignored, and workspace errors were stored
  but never shown. Results now surface through a glass notice banner at the top of the window (success
  auto-dismisses, failure stays until dismissed), and workspace failures (folder pick, move to Trash)
  show a native alert instead of being swallowed.
- Status-line activity strings ("Compacting context…", "Retrying…", …) bypassed the String Catalog;
  they are now localized through `String(localized:)`.
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

[Unreleased]: https://github.com/aice109/pi-desktop/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/aice109/pi-desktop/releases/tag/v0.2.0
