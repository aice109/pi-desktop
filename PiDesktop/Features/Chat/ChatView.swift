//
//  ChatView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// 会话详情：消息流 + 输入框，经 `SessionStore` 与 pi 通信（ADR-0003）。
struct ChatView: View {
    let session: Session
    @Environment(SessionStore.self) private var store
    @Environment(AppSettingsStore.self) private var appSettings
    @Environment(WorkspaceStore.self) private var workspaceStore
    @State private var draft = ""
    /// 待发送的图片附件（ADR-0010）。
    @State private var attachments: [AgentImage] = []
    @State private var isPickingImages = false
    @State private var models: [AgentModel] = []
    /// 可发现的 pi 命令（`get_commands`），用于斜杠建议。
    @State private var commands: [AgentCommand] = []
    /// fork 选择弹窗的数据与开关。
    @State private var forkMessages: [AgentForkMessage] = []
    @State private var isChoosingFork = false
    /// 分支结构总览（`get_tree`）开关；树内容由弹窗自行加载，点击后即时弹出、不阻塞。
    @State private var isShowingTree = false
    /// 手动压缩（可带自定义指令）的弹窗。
    @State private var isCompactionPromptPresented = false
    @State private var compactionInstructions = ""
    /// 会话内搜索。
    @State private var isSearching = false
    @State private var searchQuery = ""
    /// 对话锚点面板：当前选中的锚点（点选后跳转到对应回合）。
    @State private var selectedAnchorID: UUID?
    @State private var scrollTarget: UUID?
    /// 已展开「过程」区的回合 id；默认全部收起，只显示提问与最终结论。
    @State private var expandedTurns: Set<UUID> = []
    /// 当前是否贴近底部（决定“回到底部”按钮是否出现）。
    @State private var isAtBottom = true
    /// 是否跟随底部：内容增长时自动滚动；用户主动上滑后暂停。
    @State private var isFollowingBottom = true
    /// 最近一次滚动阶段，用于区分用户滚动与程序滚动。
    @State private var scrollPhase: ScrollPhase = .idle
    @FocusState private var isComposerFocused: Bool
    /// 会话末尾标记的稳定锚点：滚动到底时以它为目标，保证底部留白完整露出。
    private static let bottomAnchorID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if store.isBusy(session) { statusArea }
            Divider()
            composer
            usageFooter
        }
        .overlay {
            // 仅在会话尚无内容时遮罩：再次校准时（已有消息）不遮挡阅读。
            if store.isLoading(session), session.messages.isEmpty {
                SessionLoadingView()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isLoading(session))
        .navigationTitle(session.title.isEmpty ? "Untitled Session" : session.title)
        .navigationSubtitle(detailSubtitle)
        .task(id: session.id) {
            // 打开会话即激活 pi（懒启动），并加载模型列表。
            await store.activate(session)
            models = await store.availableModels(for: session)
            commands = await store.availableCommands(for: session)
        }
        .onAppear { isComposerFocused = true }
        .sheet(isPresented: $isShowingTree) {
            SessionTreeSheet(load: { await store.sessionTree(for: session) }) { entryId in
                Task {
                    // 从树节点 fork，并把原文本回填输入框（编辑并重发）。
                    if let text = await store.fork(session, from: entryId), !text.isEmpty {
                        draft = text
                        isComposerFocused = true
                    }
                    isShowingTree = false
                }
            }
        }
        .sheet(isPresented: $isChoosingFork) {
            ForkMessageSheet(messages: forkMessages) { entryId in
                Task {
                    // fork 后把原消息回填输入框，用户可直接编辑并重发（「编辑并重发」）。
                    if let text = await store.fork(session, from: entryId), !text.isEmpty {
                        draft = text
                        isComposerFocused = true
                    }
                }
            }
        }
        .sheet(isPresented: $isCompactionPromptPresented) {
            CompactionSheet(instructions: $compactionInstructions) { text in
                Task { await store.compact(session, instructions: text) }
            }
        }
        // 右侧对话锚点面板：点选锚点即可快速定位到某个回合（可选，默认关闭）。
        .inspector(isPresented: anchorPanelBinding) {
            anchorInspector
                .inspectorColumnWidth(min: 220, ideal: 260, max: 360)
        }
        .toolbar {
            ToolbarItem { findButton }
            ToolbarItem { anchorToggle }
            ToolbarItem { contextMenu }
            ToolbarItem { branchMenu }
            if !commands.isEmpty { ToolbarItem { commandMenu } }
            ToolbarItem { modelMenu }
            if let levels = currentState?.availableThinkingLevels, levels.count > 1 {
                ToolbarItem { thinkingMenu(levels) }
            }
            if store.isStreaming(session) {
                ToolbarItem {
                    Button {
                        Task { await store.interrupt(session) }
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .help("Stop (⌘.)")
                }
            }
        }
    }

    private var currentState: AgentSessionState? { store.state(for: session) }

    /// 顶部副标题：仅在会话工作目录与当前项目不同时显示。
    ///
    /// 相同时侧栏项目栏已经展示了该路径，重复显示只会挤占标题空间；
    /// 不同时（例如恢复的历史会话）才用缩写后的路径提示实际目录。
    private var detailSubtitle: String {
        guard let directory = session.workingDirectory,
            !directory.isEmpty,
            directory != workspaceStore.workspace?.path
        else { return "" }
        return PathDisplay.abbreviated(directory)
    }

    /// 上下文菜单：手动压缩 + 自动压缩开关（pi 的 `compact` / `set_auto_compaction`）。
    private var contextMenu: some View {
        // 压缩进行中时禁用入口，避免重复触发。
        let isCompacting = store.activity(for: session) == .compacting
        return Menu {
            Button("Compact Now") {
                Task { await store.compact(session) }
            }
            .disabled(isCompacting)
            Button("Compact with Instructions…") {
                compactionInstructions = ""
                isCompactionPromptPresented = true
            }
            .disabled(isCompacting)
            Divider()
            Toggle("Auto-compaction", isOn: autoCompactionBinding)
            Toggle("Auto-retry", isOn: autoRetryBinding)
        } label: {
            Label("Context", systemImage: "arrow.down.right.and.arrow.up.left")
        }
        .help("Context")
    }

    private var autoCompactionBinding: Binding<Bool> {
        Binding(
            get: { currentState?.autoCompactionEnabled ?? true },
            set: { newValue in
                Task { await store.setAutoCompaction(newValue, in: session) }
            }
        )
    }

    private var autoRetryBinding: Binding<Bool> {
        Binding(
            get: { store.isAutoRetryEnabled(in: session) },
            set: { newValue in
                Task { await store.setAutoRetry(newValue, in: session) }
            }
        )
    }

    /// 会话内搜索入口（工具栏放大镜）。
    private var findButton: some View {
        Button {
            isSearching = true
        } label: {
            Label("Find", systemImage: "magnifyingglass")
        }
        .help("Find in Conversation")
        .popover(isPresented: $isSearching, arrowEdge: .bottom) { conversationSearch }
    }

    private var conversationSearch: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Find in conversation", text: $searchQuery)
                .textFieldStyle(.roundedBorder)
                .padding(12)
            Divider()
            let results = searchResults
            if results.isEmpty {
                Text(searchQuery.isEmpty ? "Type to search." : "No matches.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List(results) { result in
                    Button {
                        scrollTarget = result.id
                        isSearching = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.title)
                                .font(.caption.weight(.semibold))
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 360, height: 320)
    }

    /// 对话锚点面板开关：绑定到持久化偏好，可跨启动保留。
    private var anchorPanelBinding: Binding<Bool> {
        Binding(
            get: { appSettings.showAnchorPanel },
            set: { appSettings.showAnchorPanel = $0 }
        )
    }

    /// 锚点入口（工具栏）：切换窗口右侧的回合导航面板。
    private var anchorToggle: some View {
        Button {
            appSettings.showAnchorPanel.toggle()
        } label: {
            Label("Anchors", systemImage: "sidebar.right")
        }
        .help("Conversation Anchors")
    }

    /// 右侧锚点面板：按回合列出提问，选中即滚动到该回合。
    private var anchorInspector: some View {
        // 只算一次：面板重建时避免重复排序整条时间线。
        let anchors = conversationAnchors
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark")
                    .foregroundStyle(.secondary)
                Text("Anchors")
                    .font(.headline)
                Spacer()
                Text("\(anchors.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if anchors.isEmpty {
                Text("No anchors yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
            } else {
                List(selection: $selectedAnchorID) {
                    ForEach(anchors) { anchor in
                        anchorRow(anchor)
                            .tag(anchor.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
        // 选中即定位：复用消息列表的滚动目标（与搜索同一路径）。
        .onChange(of: selectedAnchorID) { _, id in
            guard let id else { return }
            scrollTarget = id
        }
    }

    /// 单条锚点：序号徽标 + 提问摘要 + 结论摘要；选中态由 `List` 原生高亮。
    private func anchorRow(_ anchor: ConversationAnchor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(anchor.index)")
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(.quaternary.opacity(0.5), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(anchor.title)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if let detail = anchor.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .help(anchor.title)
    }

    /// 对话锚点：每个回合一条，用提问作为标题、结论首行作为副标题。
    private var conversationAnchors: [ConversationAnchor] {
        chatTurns(from: timeline).enumerated().compactMap { offset, turn in
            guard let userMessage = turn.userMessage else { return nil }
            return ConversationAnchor(
                id: userMessage.id,
                title: anchorTitle(for: userMessage),
                detail: turn.conclusion.map { Self.firstLine(of: $0.content) },
                index: offset + 1
            )
        }
    }

    /// 锚点标题：折叠空白、截断；仅有图片时给出说明。
    private func anchorTitle(for message: Message) -> String {
        let collapsed = message.content
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        if collapsed.isEmpty {
            return message.images.isEmpty ? "…" : String(localized: "Image message")
        }
        return collapsed.count > 140 ? String(collapsed.prefix(140)) + "…" : collapsed
    }

    /// 取正文首行并折叠空白，用于副标题。
    private static func firstLine(of text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let collapsed = line.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.count > 120 ? String(collapsed.prefix(120)) + "…" : collapsed
    }

    /// 匹配的消息与工具调用；片段截在关键词周围。
    private var searchResults: [ConversationSearchResult] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        var results: [ConversationSearchResult] = []
        for message in sortedMessages where message.content.localizedCaseInsensitiveContains(query) {
            results.append(
                ConversationSearchResult(
                    id: message.id,
                    title: message.role.displayName,
                    snippet: snippet(message.content, matching: query)
                ))
        }
        for call in session.toolCalls {
            let combined = [call.arguments, call.output].compactMap { $0 }.joined(separator: "\n")
            guard combined.localizedCaseInsensitiveContains(query) else { continue }
            results.append(
                ConversationSearchResult(
                    id: call.id,
                    title: call.name,
                    snippet: snippet(combined, matching: query)
                ))
        }
        return Array(results.prefix(50))
    }

    private func snippet(_ text: String, matching query: String) -> String {
        guard let range = text.range(of: query, options: .caseInsensitive) else {
            return String(text.prefix(120)).replacingOccurrences(of: "\n", with: " ")
        }
        let start = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        return String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
    }

    /// 分支菜单：clone 当前分支，或从某条用户消息 fork。
    private var branchMenu: some View {
        Menu {
            Button("Clone Session") {
                Task { await store.clone(session) }
            }
            Button("Fork from Message…") {
                Task {
                    forkMessages = await store.forkMessages(for: session)
                    isChoosingFork = true
                }
            }
            Button("Show Tree…") {
                isShowingTree = true
            }
        } label: {
            Label("Branch", systemImage: "arrow.triangle.branch")
        }
        .help("Branch")
    }

    /// 工具栏命令菜单：不输入 `/` 也能发现并插入命令。
    private var commandMenu: some View {
        Menu {
            ForEach(commands) { command in
                Button {
                    applyCommand(command)
                } label: {
                    if let description = command.description, !description.isEmpty {
                        Text("/\(command.name) — \(description)")
                    } else {
                        Text("/\(command.name)")
                    }
                }
            }
        } label: {
            Label("Commands", systemImage: "command")
        }
        .help("Commands")
    }

    /// 状态栏文案：重试/压缩优先，其次工具，最后默认“思考中”。
    private var statusText: String {
        if let activity = store.activity(for: session) { return activity.displayText }
        if let tool = store.activeToolName { return String(localized: "Running \(tool)…") }
        return String(localized: "Thinking…")
    }

    /// 模型选择菜单：
    ///
    /// 用 `Toggle` 而非 `Label(_, systemImage: "checkmark")`：菜单会渲染成系统原生的勾选行，
    /// 选中态稳定可见；比较只认 `provider` + `id`，避免元数据差异导致误判“未选中”。
    private var modelMenu: some View {
        Menu {
            if models.isEmpty {
                Text(currentState == nil ? "Loading…" : "No models available")
            } else {
                ForEach(displayedModels) { model in
                    Toggle(isOn: modelSelectionBinding(for: model)) {
                        Text(model.displayName)
                    }
                }
            }
        } label: {
            Label(currentState?.model?.displayName ?? "Model", systemImage: "cpu")
        }
        .help("Model")
    }

    /// 下拉里的模型：保证当前模型在列，避免因列表缺失而看不到选中态。
    private var displayedModels: [AgentModel] {
        guard let current = currentState?.model else { return models }
        guard !models.contains(where: { $0.matches(current) }) else { return models }
        // 去掉同 id 的旧条目，避免 `ForEach` 出现重复标识。
        return [current] + models.filter { $0.id != current.id }
    }

    private func modelSelectionBinding(for model: AgentModel) -> Binding<Bool> {
        Binding(
            get: { currentState?.model?.matches(model) ?? false },
            set: { isSelected in
                guard isSelected else { return }
                Task { await store.selectModel(model, in: session) }
            }
        )
    }

    /// 思考等级菜单（仅当当前模型支持多个等级时显示）。
    private func thinkingMenu(_ levels: [String]) -> some View {
        Menu {
            ForEach(displayedThinkingLevels(levels), id: \.self) { level in
                Toggle(isOn: thinkingSelectionBinding(for: level)) {
                    Text(level.capitalized)
                }
            }
        } label: {
            Label(currentState?.thinkingLevel?.capitalized ?? "Thinking", systemImage: "brain")
        }
        .help("Thinking Level")
    }

    private func thinkingSelectionBinding(for level: String) -> Binding<Bool> {
        Binding(
            get: { currentState?.thinkingLevel?.caseInsensitiveCompare(level) == .orderedSame },
            set: { isSelected in
                guard isSelected else { return }
                Task { await store.selectThinkingLevel(level, in: session) }
            }
        )
    }

    /// 保证当前等级在列（例如模型切换后返回的等级不在可选列表里）。
    private func displayedThinkingLevels(_ levels: [String]) -> [String] {
        guard let current = currentState?.thinkingLevel,
            !levels.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame })
        else { return levels }
        return levels + [current]
    }

    /// 底栏：上下文占用 / 累计 token / 费用（可在偏好设置中关闭）。
    @ViewBuilder
    private var usageFooter: some View {
        if appSettings.showUsageFooter, let usage = store.usage(for: session) {
            HStack(spacing: 14) {
                if let percent = usage.contextPercent {
                    HStack(spacing: 6) {
                        Gauge(value: min(max(percent / 100, 0), 1), in: 0...1) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .frame(width: 80)
                            .tint(percent >= 80 ? .orange : .accentColor)
                        Text("\(Int(percent.rounded()))%")
                            .monospacedDigit()
                    }
                    .help("Context usage")
                }
                Label("\(usage.totalTokens.formatted()) tokens", systemImage: "number")
                Label(usage.costUSD.formatted(.currency(code: "USD")), systemImage: "dollarsign.circle")
                Spacer()
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        // 预先算好时间线与行标记。若在每一行里重新访问 `timeline` / `sortedMessages`，
        // 每次渲染都会重排整条时间线，长会话下退化成 O(n²) 导致卡顿。
        let items = timeline
        let turns = chatTurns(from: items)
        let isStreamingSession = store.isStreaming(session)
        // 只给最后一条助手消息显示流式指示（惰性创建后它就是当前正在累积的那条）。
        let streamingMessageID =
            isStreamingSession ? sortedMessages.last { $0.role == .assistant }?.id : nil

        return ScrollViewReader { proxy in
            List {
                ForEach(turns) { turn in
                    turnRow(turn, streamingMessageID: streamingMessageID)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .id(turn.id)
                }
                if !turns.isEmpty {
                    conversationEndMarker
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .id(Self.bottomAnchorID)
                }
            }
            .listStyle(.plain)
            // 滚动条与列表边缘留出间距，避免末端被列表边界截断。
            .contentMargins(.vertical, 8, for: .scrollIndicators)
            // 跟随判断：贴近底部时恢复跟随；离开底部且由用户手势驱动时暂停跟随。
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(geometry)
            } action: { oldMetrics, newMetrics in
                // 滚动事件频率很高，仅在真正变化时写 @State，避免每个滚动 tick 都触发重绘。
                let nearBottom = newMetrics.isNearBottom
                if isAtBottom != nearBottom { isAtBottom = nearBottom }
                if nearBottom {
                    if !isFollowingBottom { isFollowingBottom = true }
                } else if scrollPhase.isUserScroll {
                    if isFollowingBottom { isFollowingBottom = false }
                } else if scrollPhase == .idle, newMetrics.contentHeight <= oldMetrics.contentHeight + 1 {
                    // 阶段事件缺失时的兜底：内容未增长却离开底部，视为用户上滑。
                    if isFollowingBottom { isFollowingBottom = false }
                }
            }
            .onScrollPhaseChange { _, phase in
                if scrollPhase != phase { scrollPhase = phase }
                // 手势结束后以最终位置为准；程序滚动（animating）不改变跟随意图。
                if phase == .idle, isAtBottom, !isFollowingBottom { isFollowingBottom = true }
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                // 命中的条目可能在折叠的过程区里：先展开所在回合，等它渲染后再滚动。
                if let turnID = turns.first(where: { turn in
                    turn.process.contains { $0.id == target }
                })?.id {
                    expandedTurns.insert(turnID)
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(60))
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
                }
                scrollTarget = nil
            }
            .onChange(of: items.count) { _, _ in autoScroll(proxy, turns: turns) }
            // 流式追加既不改条数、也不改回合数，需额外监听末条内容与工具输出。
            .onChange(of: sortedMessages.last?.content) { _, _ in autoScroll(proxy, turns: turns) }
            .onChange(of: session.toolCalls.last?.output) { _, _ in autoScroll(proxy, turns: turns) }
            .onAppear {
                isAtBottom = true
                isFollowingBottom = true
                scrollToBottom(proxy, turns: turns, animated: false)
            }
            .overlay(alignment: .bottomTrailing) {
                // 用户翻到上面时给出“回到底部”的入口。
                if !isAtBottom, !turns.isEmpty {
                    scrollToBottomButton(proxy, turns: turns)
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomTrailing)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isAtBottom)
        }
    }

    /// 消息与工具调用按时间合并成正序时间线。
    ///
    /// 时间戳相同时按原始顺序（消息先于工具）稳定排序；Swift 的 `sorted(by:)` 不保证稳定，
    /// 因此显式用下标兜底，避免同一时刻的条目在重排后跳来跳去。
    private var timeline: [TimelineItem] {
        let messages = session.messages.map(TimelineItem.message)
        let toolCalls = session.toolCalls.map(TimelineItem.toolCall)
        return (messages + toolCalls).enumerated()
            .sorted { lhs, rhs in
                if lhs.element.date != rhs.element.date { return lhs.element.date < rhs.element.date }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// 把时间线切成「回合」。
    ///
    /// 回合 = 一条用户消息到下一个用户消息之前。每个回合只保留最后一条有正文的助手消息
    /// 作为「结论」常显；其余（思考、工具调用、中间旁白）收进一个默认折叠的「过程」区，
    /// 保证最终总结始终排在工具调用之后。
    private func chatTurns(from items: [TimelineItem]) -> [ChatTurn] {
        guard !items.isEmpty else { return [] }

        // 回合起点：首条 + 每条（非首位的）用户消息。
        var starts = [0]
        for index in items.indices.dropFirst() {
            if case .message(let message) = items[index], message.role == .user {
                starts.append(index)
            }
        }
        starts.append(items.count)

        var turns: [ChatTurn] = []
        for turn in 0..<(starts.count - 1) {
            let range = starts[turn]..<starts[turn + 1]
            // 结论 = 本回合最后一条有正文的助手消息（流式占位为空时不算）。
            var conclusionIndex: Int?
            for index in range {
                if case .message(let message) = items[index],
                    message.role == .assistant, !message.content.isEmpty
                {
                    conclusionIndex = index
                }
            }

            var userMessage: Message?
            var conclusion: Message?
            var process: [TimelineItem] = []
            for index in range {
                if index == conclusionIndex, case .message(let message) = items[index] {
                    conclusion = message
                } else if index == range.lowerBound, case .message(let message) = items[index],
                    message.role == .user
                {
                    userMessage = message
                } else {
                    process.append(items[index])
                }
            }
            turns.append(
                ChatTurn(
                    id: userMessage?.id ?? items[range.lowerBound].id,
                    userMessage: userMessage,
                    process: process,
                    conclusion: conclusion
                ))
        }
        return turns
    }

    /// 一个回合的完整渲染：常显提问 + 可折叠过程 + 常显结论。
    @ViewBuilder
    private func turnRow(_ turn: ChatTurn, streamingMessageID: UUID?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let userMessage = turn.userMessage {
                MessageRow(message: userMessage, isStreaming: false, showsHeader: true)
                    .id(userMessage.id)
            }
            if !turn.process.isEmpty {
                processDisclosure(turn)
            }
            if let conclusion = turn.conclusion {
                MessageRow(
                    message: conclusion,
                    isStreaming: streamingMessageID == conclusion.id,
                    showsHeader: true
                )
                .id(conclusion.id)
            }
        }
        .padding(.top, 8)
    }

    /// 中间过程（思考 / 工具调用 / 旁白）的大折叠。
    ///
    /// 折叠时只留一行摘要，展开后按时间顺序列出全部中间项；默认收起，让提问与最终结论一目了然。
    private func processDisclosure(_ turn: ChatTurn) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: turn.id)) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(turn.process) { item in
                    processItem(item)
                        .id(item.id)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            processLabel(turn)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .disclosureGroupStyle(RowDisclosureGroupStyle())
    }

    /// 折叠头：图标 + 步数 + 涉及的工具名；有工具在跑时给出迷你进度指示。
    private func processLabel(_ turn: ChatTurn) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "ellipsis.circle")
                .font(.caption)
            Text("Process")
                .font(.caption.weight(.semibold))
            Text(processSummary(turn))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
            if turn.process.contains(where: isRunningProcessItem) {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
    }

    /// 折叠头文案：步数 + 去重后的工具名（最多 3 个）。
    private func processSummary(_ turn: ChatTurn) -> String {
        var toolNames: [String] = []
        for item in turn.process {
            guard case .toolCall(let call) = item, !toolNames.contains(call.name) else { continue }
            toolNames.append(call.name)
        }
        let steps = turn.process.count == 1 ? "1 step" : "\(turn.process.count) steps"
        guard !toolNames.isEmpty else { return steps }
        let shown = toolNames.prefix(3).joined(separator: ", ")
        return "\(steps) · \(shown)\(toolNames.count > 3 ? "…" : "")"
    }

    /// 过程项是否为仍在执行的工具调用。
    private func isRunningProcessItem(_ item: TimelineItem) -> Bool {
        guard case .toolCall(let call) = item else { return false }
        return store.isRunningTool(call.toolCallID)
    }

    /// 折叠区内的一项：消息按原样渲染，工具调用渲染为卡片。
    @ViewBuilder
    private func processItem(_ item: TimelineItem) -> some View {
        switch item {
        case .message(let message):
            MessageRow(message: message, isStreaming: false, showsHeader: false)
        case .toolCall(let toolCall):
            ToolCallCard(toolCall: toolCall, isRunning: store.isRunningTool(toolCall.toolCallID))
        }
    }

    /// 大折叠的展开状态：按回合 id 记录。
    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedTurns.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    expandedTurns.insert(id)
                } else {
                    expandedTurns.remove(id)
                }
            }
        )
    }

    private func scrollToBottomButton(_ proxy: ScrollViewProxy, turns: [ChatTurn]) -> some View {
        Button {
            isFollowingBottom = true
            scrollToBottom(proxy, turns: turns, animated: true)
        } label: {
            Label("Latest", systemImage: "arrow.down")
                .labelStyle(.iconOnly)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .help("Scroll to latest")
        .accessibilityLabel("Scroll to latest")
    }

    /// 仅在用户停留在底部时自动跟随新内容。
    private func autoScroll(_ proxy: ScrollViewProxy, turns: [ChatTurn]) {
        guard isFollowingBottom else { return }
        scrollToBottom(proxy, turns: turns, animated: true)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, turns: [ChatTurn], animated: Bool) {
        guard !turns.isEmpty else { return }
        // 滚到末尾标记而非最后一条消息：标记下方为底部留白，保证“到底”时它完整可见。
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
    }

    /// 会话末尾标记：细线 + “到底”图标，兼作聊天区底部的呼吸留白。
    ///
    /// 放在列表最后一行（滚到底才露出），用 SF Symbol 而非纯文字暗示“已到最后”，
    /// 并提供 28pt 底部间距，避免最后一条消息紧贴输入框。
    private var conversationEndMarker: some View {
        HStack(spacing: 10) {
            endRule
            Image(systemName: "arrow.down.to.line")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
            endRule
        }
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
        .padding(.bottom, 28)
        .accessibilityElement()
        .accessibilityLabel("End of conversation")
    }

    /// 末尾标记两侧的细线。
    private var endRule: some View {
        Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
    }

    // MARK: - Status

    /// 运行状态：实时思考（可折叠）+ 已排队消息 + 工具/思考指示。
    @ViewBuilder
    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reasoning = store.reasoning(in: session) {
                ReasoningDisclosure(text: reasoning)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
            }
            let queued = store.queued(for: session)
            if !queued.isEmpty { queuedMessages(queued) }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if case .retrying = store.activity(for: session) {
                    Button("Abort Retry") {
                        Task { await store.abortRetry(in: session) }
                    }
                    .buttonStyle(.link)
                    .font(.caption)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    /// 已排队的 steering / follow-up 消息：可一键清空并还原到输入框。
    private func queuedMessages(_ queued: AgentQueue) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(queued.steering.enumerated()), id: \.offset) { _, text in
                queuedRow(symbol: "arrow.turn.down.right", text: text)
            }
            ForEach(Array(queued.followUp.enumerated()), id: \.offset) { _, text in
                queuedRow(symbol: "text.append", text: text)
            }
            HStack {
                Spacer()
                Button("Clear Queued", action: clearQueue)
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func queuedRow(symbol: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachments.isEmpty { attachmentStrip }
            if store.isRunningBash(session) { runningBashRow }
            if !commandSuggestions.isEmpty { commandSuggestionList }
            composerField
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // 三种附件入口都走同一套加载：剪贴板、Finder 拖拽、文件选择器。
        .onPasteCommand(of: [.image]) { providers in loadImages(from: providers) }
        .dropDestination(for: URL.self) { urls, _ in
            loadImages(fromURLs: urls)
            return true
        }
        .fileImporter(
            isPresented: $isPickingImages,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true,
            onCompletion: handleImagePick
        )
    }

    /// 输入行：附件按钮 + 文本框 + 发送控件。
    private var composerField: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Button {
                isPickingImages = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Attach images")
            .accessibilityLabel("Attach images")

            TextField("Message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
                .focused($isComposerFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    .quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control)
                        .strokeBorder(
                            isComposerFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: 1
                        )
                }
                .onSubmit { submit() }
            sendControl
        }
    }

    /// 直接 shell 正在执行时的提示与中止入口。
    private var runningBashRow: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Running shell command…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Abort") {
                Task { await store.abortBash(in: session) }
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }

    /// 输入以 `/` 开头时的命令建议（最多 8 条）。
    private var commandSuggestions: [AgentCommand] {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("/"), !trimmed.contains(" "), !commands.isEmpty else { return [] }
        let query = trimmed.dropFirst().lowercased()
        let matches =
            query.isEmpty
            ? commands
            : commands.filter { $0.name.lowercased().hasPrefix(query) }
        return Array(matches.prefix(8))
    }

    private var commandSuggestionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(commandSuggestions) { command in
                Button {
                    applyCommand(command)
                } label: {
                    HStack(spacing: 8) {
                        Text("/\(command.name)")
                            .font(.system(.callout, design: .monospaced))
                        Spacer(minLength: 8)
                        if let description = command.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let source = command.source {
                            Text(source)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(.quaternary.opacity(0.7), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if command.id != commandSuggestions.last?.id { Divider() }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(.separator, lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 选中命令：填入 `/name `（不直接发送，允许补充参数）。
    private func applyCommand(_ command: AgentCommand) {
        draft = "/\(command.name) "
        isComposerFocused = true
    }

    /// 待发送图片的缩略图行，每张可单独移除。
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments) { image in
                    attachmentThumbnail(image)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func attachmentThumbnail(_ image: AgentImage) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let nsImage = NSImage(data: image.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))

            Button {
                attachments.removeAll { $0.id == image.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.5))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .accessibilityLabel("Remove image")
        }
    }

    /// 发送控件：空闲时普通发送；运行中可排队（点击 = steer，菜单可选 follow-up）。
    @ViewBuilder
    private var sendControl: some View {
        if store.isStreaming(session) {
            Menu {
                Button("Steer", action: { submit(as: .steer) })
                Button("Send as Follow-up", action: { submit(as: .followUp) })
            } label: {
                sendLabel
            } primaryAction: {
                submit(as: .steer)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(canSubmit)
            .keyboardShortcut(.return, modifiers: .command)
            .help("Queue for this run (⌘↩ steers)")
        } else {
            Button(action: { submit(as: .prompt) }) { sendLabel }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .disabled(!canSubmit)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send (⌘↩)")
        }
    }

    private var sendLabel: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 24, height: 24)
    }

    // MARK: - Helpers

    /// 消息按时间正序展示（最早的在上）。
    private var sortedMessages: [Message] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 一次提交的投递方式。
    private enum Submission { case prompt, steer, followUp }

    /// 提交输入框内容：空闲时普通发送，运行中按指定方式排队（默认 steer）。
    private func submit(as kind: Submission = .prompt) {
        let text = trimmedDraft
        let images = attachments
        guard !text.isEmpty || !images.isEmpty else { return }
        // `!命令` 直接执行 shell（pi 的 `bash`），不当作普通 prompt。
        if kind == .prompt, text.hasPrefix("!") {
            let command = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !command.isEmpty else { return }
            draft = ""
            Task { await store.runBash(command, in: session) }
            return
        }
        draft = ""
        attachments = []
        Task {
            switch kind {
            case .prompt:
                // 若提交瞬间回合已结束，`steer` 会落空——此时退回普通发送。
                if store.isStreaming(session) {
                    await store.steer(text, images: images, in: session)
                } else {
                    await store.send(text, images: images, in: session)
                }
            case .steer:
                await store.steer(text, images: images, in: session)
            case .followUp:
                await store.followUp(text, images: images, in: session)
            }
        }
    }

    /// 文本或图片任一存在即可提交。
    private var canSubmit: Bool {
        !trimmedDraft.isEmpty || !attachments.isEmpty
    }

    private func handleImagePick(_ result: Result<[URL], Error>) {
        if case .success(let urls) = result { loadImages(fromURLs: urls) }
    }

    /// 从 Finder 拖拽 / 文件选择器加载图片文件。
    private func loadImages(fromURLs urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/png"
            attachments.append(AgentImage(mimeType: mimeType, data: data))
        }
    }

    /// 从剪贴板 / 拖拽的 `NSItemProvider` 加载图片。
    private func loadImages(from providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadDataRepresentation(for: .image) { data, _ in
                guard let data else { return }
                let mimeType =
                    provider.registeredTypeIdentifiers
                    .compactMap { UTType($0)?.preferredMIMEType }
                    .first ?? "image/png"
                Task { @MainActor in
                    attachments.append(AgentImage(mimeType: mimeType, data: data))
                }
            }
        }
    }

    /// 清空队列并把文本还原到输入框（pi 的 Esc 语义）。
    private func clearQueue() {
        Task {
            let cleared = await store.clearQueue(in: session)
            let restored = (cleared.steering + cleared.followUp).joined(separator: "\n")
            if !restored.isEmpty { draft = restored }
        }
    }
}

// MARK: - Timeline

/// 会话时间线的一项：消息或工具调用。
private enum TimelineItem: Identifiable {
    case message(Message)
    case toolCall(ToolCall)

    var id: UUID {
        switch self {
        case .message(let message): return message.id
        case .toolCall(let toolCall): return toolCall.id
        }
    }

    var date: Date {
        switch self {
        case .message(let message): return message.createdAt
        case .toolCall(let toolCall): return toolCall.createdAt
        }
    }
}

/// 一个「回合」：一条用户消息及其后续的助手输出，直到下一条用户消息之前。
///
/// 渲染时把中间过程收进一个大折叠，只常显提问与最终结论。
private struct ChatTurn: Identifiable {
    /// 回合标识：优先用提问消息的 id，保证流式追加时行身份稳定。
    let id: UUID
    /// 回合开头的用户消息（导入历史的首个回合可能没有）。
    let userMessage: Message?
    /// 中间过程：思考 / 工具调用 / 旁白——默认折叠。
    let process: [TimelineItem]
    /// 结论：本回合最后一条有正文的助手消息——常显。
    let conclusion: Message?
}

// MARK: - Message row

/// 单条消息：角色头像 + （可选）头部 + 内容。
///
/// 连续的同一角色消息只在其首条显示头部，减少视觉噪音。
private struct MessageRow: View {
    let message: Message
    let isStreaming: Bool
    let showsHeader: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 5) {
                if showsHeader { header }
                if let thinking = message.thinking, !thinking.isEmpty {
                    ReasoningDisclosure(text: thinking)
                }
                if !message.images.isEmpty { imageAttachments }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 1)
        .contextMenu {
            Button("Copy") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message.content, forType: .string)
            }
        }
    }

    /// 角色圆形徽标。
    private var avatar: some View {
        Image(systemName: message.role.symbolName)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(message.role.tint)
            .frame(width: 22, height: 22)
            .background(message.role.tint.opacity(0.14), in: Circle())
    }

    /// 用户消息附带的图片缩略图（ADR-0010）。
    @ViewBuilder
    private var imageAttachments: some View {
        HStack(spacing: 6) {
            ForEach(message.images) { image in
                if let nsImage = NSImage(data: image.data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
                        .accessibilityLabel("Attached image")
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(message.role.displayName)
                .font(.subheadline.weight(.semibold))
            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if message.content.isEmpty {
            // 流式占位：等待首个增量时显示加载指示，否则该消息只有思考，正文留空。
            if isStreaming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("…").foregroundStyle(.secondary)
                }
                .font(.callout)
            }
        } else if message.role == .tool {
            Text(message.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.small))
        } else if message.role == .user {
            MarkdownText(text: message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        } else {
            MarkdownText(text: message.content)
                .textSelection(.enabled)
        }
    }
}

/// 让整行标签都可点击的折叠样式。
///
/// 系统 `DisclosureGroup` 默认只把命中区放在小箭头上，很难点中。这里把标签整体包成无边框
/// `Button`，再用 `contentShape` 撑满整行、补上垂直留白；展开状态仍由 `DisclosureGroup`
/// 管理，只是换了呈现。展开内容左侧缩进，避免贴边。
private struct RowDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 14)
            }
        }
    }
}

/// 可折叠的思考内容（实时与历史共用）。
private struct ReasoningDisclosure: View {
    let text: String

    var body: some View {
        DisclosureGroup {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            Label("Reasoning", systemImage: "brain")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disclosureGroupStyle(RowDisclosureGroupStyle())
    }
}

/// 工具调用卡片：名称 + 参数 + 状态 + 可折叠输出。
private struct ToolCallCard: View {
    let toolCall: ToolCall
    /// 是否正在执行，由 `SessionStore` 判定（见 `isRunningTool(_:)`）。
    let isRunning: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let arguments = toolCall.arguments, !arguments.isEmpty {
                    detail("Arguments", text: arguments)
                }
                if let output = toolCall.output, !output.isEmpty {
                    detail("Output", text: output)
                }
                if (toolCall.arguments?.isEmpty ?? true) && (toolCall.output?.isEmpty ?? true) {
                    Text("No details")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            summary
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .strokeBorder(Color.red.opacity(toolCall.isError ? 0.5 : 0), lineWidth: 1)
        }
        .disclosureGroupStyle(RowDisclosureGroupStyle())
        .contextMenu {
            if let output = toolCall.output, !output.isEmpty {
                Button("Copy Output") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(output, forType: .string)
                }
            }
        }
    }

    /// 折叠时的一行摘要：图标 + 工具名 + 参数 + 状态。
    private var summary: some View {
        HStack(spacing: 6) {
            Image(systemName: symbolName)
                .font(.caption)
                .foregroundStyle(toolCall.isError ? .red : .orange)
            Text(toolCall.name)
                .font(.caption.weight(.semibold))
                .monospaced()
            if let arguments = toolCall.arguments, !arguments.isEmpty {
                Text(arguments)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        .quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.chip)
                    )
            }
            Spacer()
            status
        }
    }

    /// 展开后的参数 / 输出段落。
    private func detail(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 常见工具映射到 SF Symbols，让卡片一眼可辨。
    private var symbolName: String {
        switch toolCall.name {
        case "bash", "shell": return "terminal"
        case "read": return "doc.text"
        case "write": return "square.and.pencil"
        case "edit", "multi_edit": return "pencil"
        case "grep", "search": return "magnifyingglass"
        case "glob", "list", "ls": return "folder"
        case "web_search", "fetch": return "globe"
        default: return "wrench.and.screwdriver.fill"
        }
    }

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 4) {
            if toolCall.isError {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            } else if let durationMs = toolCall.durationMs {
                Text("\(durationMs) ms")
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else if isRunning {
                ProgressView().controlSize(.mini)
            } else {
                // 已结束但耗时未知（多为历史导入）：不能靠 durationMs 判断是否在跑，
                // 否则长会话里的历史工具会永远转圈。
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

extension MessageRole {
    fileprivate var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .tool: return "Tool"
        }
    }

    fileprivate var symbolName: String {
        switch self {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .tool: return "wrench.and.screwdriver.fill"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .user: return .accentColor
        case .assistant: return .primary
        case .tool: return .orange
        }
    }
}

// MARK: - Scroll helpers

extension ScrollPhase {
    /// 是否由用户手势驱动（拖动 / 交互 / 惯性减速）。程序滚动为 `animating`，不算。
    fileprivate var isUserScroll: Bool {
        switch self {
        case .tracking, .interacting, .decelerating: return true
        default: return false
        }
    }
}

/// 滚动位置快照：只取跟随判断需要的字段，并在内容增长与用户滚动之间做区分。
private struct ScrollMetrics: Equatable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var containerHeight: CGFloat
    var insetBottom: CGFloat

    init(_ geometry: ScrollGeometry) {
        offsetY = geometry.contentOffset.y
        contentHeight = geometry.contentSize.height
        containerHeight = geometry.containerSize.height
        insetBottom = geometry.contentInsets.bottom
    }

    /// 距底部小于阈值即视为“在底部”；内容不足一屏时也成立。
    var isNearBottom: Bool {
        let visibleBottom = offsetY + containerHeight
        let contentBottom = contentHeight + insetBottom
        return contentBottom - visibleBottom <= 80
    }
}

/// 会话首次加载时的等待遮罩：玻璃卡片 + 进度指示。
private struct SessionLoadingView: View {
    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.large)
            Text("Loading session…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.card))
    }
}

/// 手动压缩弹窗：可填写自定义摘要指令（pi 的 `compact.customInstructions`）。
private struct CompactionSheet: View {
    @Binding var instructions: String
    let onCompact: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Compact Context", systemImage: "arrow.down.right.and.arrow.up.left")
                .font(.headline)
            Text("Optionally describe what the summary should focus on.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Instructions (optional)", text: $instructions, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
                .frame(width: 360)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Compact") {
                    let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    onCompact(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}

/// 会话内搜索的一条结果。
private struct ConversationSearchResult: Identifiable {
    let id: UUID
    let title: String
    let snippet: String
}

/// 对话锚点：一个回合的跳转目标（用提问定位，并附带结论摘要）。
private struct ConversationAnchor: Identifiable {
    /// 目标消息 id，用于滚动到该回合。
    let id: UUID
    /// 提问摘要。
    let title: String
    /// 结论首行摘要；无结论时为 nil。
    let detail: String?
    /// 回合序号，从 1 开始。
    let index: Int
}

/// fork 选择弹窗：列出可 fork 的用户消息，选中即从该处创建分支。
private struct ForkMessageSheet: View {
    let messages: [AgentForkMessage]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Fork from a Message")
                .font(.headline)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)
            if messages.isEmpty {
                Text("No user messages available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                List(messages) { message in
                    Button {
                        onSelect(message.entryId)
                        dismiss()
                    } label: {
                        Text(message.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
        }
        .frame(width: 460, height: 360)
    }
}

/// 会话树总览：展示所有分支（含遗弃分支）与当前活动叶子，可从用户消息处 fork。
///
/// 树在弹窗出现后异步加载（`load`），因此点击入口即时反馈，不会卡在 RPC 往返上；
/// 渲染使用压平后的行数组（`outlineRows`）而非递归的 `OutlineGroup`，避免线性会话
/// （一条长链）递归出上百层嵌套视图而卡死。
private struct SessionTreeSheet: View {
    let load: @MainActor () async -> AgentSessionTree?
    let onFork: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var tree: AgentSessionTree?
    @State private var isLoading = true
    /// 已折叠节点的 id；默认全部展开，长会话也能一眼看到分支。
    @State private var collapsed: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session Tree")
                .font(.headline)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)
            content
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
        .task {
            tree = await load()
            isLoading = false
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let rows = tree?.outlineRows(collapsed: collapsed) ?? []
            if rows.isEmpty {
                Text("This session has no entries yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                List(rows) { row in
                    SessionTreeRow(
                        row: row,
                        isCollapsed: collapsed.contains(row.id),
                        onToggle: { toggleCollapsed(row.id) },
                        onFork: onFork
                    )
                }
                .listStyle(.plain)
            }
        }
    }

    /// 折叠 / 展开：切换子树可见性。
    private func toggleCollapsed(_ id: String) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if collapsed.contains(id) {
                collapsed.remove(id)
            } else {
                collapsed.insert(id)
            }
        }
    }
}

/// 树中的一行：缩进 + 展开箭头 + 图标 + 预览 + 类型/标签 + fork / 活动叶子标记。
private struct SessionTreeRow: View {
    let row: SessionTreeOutlineRow
    let isCollapsed: Bool
    let onToggle: () -> Void
    let onFork: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            disclosure
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(iconStyle)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.preview.isEmpty ? row.kind : row.preview)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(row.kind)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let label = row.label, !label.isEmpty {
                        anchorLabel(label)
                    }
                }
            }
            Spacer(minLength: 0)
            if row.isUserMessage {
                Button("Fork") { onFork(row.id) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if row.isActiveLeaf {
                Image(systemName: "smallcircle.filled.circle")
                    .foregroundStyle(.tint)
                    .help("Active branch tip")
            }
        }
        .padding(.leading, CGFloat(row.indent) * 14)
        // 活动分支整行轻微着色，方便在分叉里找到当前路径。
        .listRowBackground(row.isOnActivePath ? Color.accentColor.opacity(0.06) : Color.clear)
    }

    /// 展开箭头；叶子用等宽占位保持缩进对齐。
    @ViewBuilder
    private var disclosure: some View {
        if row.isExpandable {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCollapsed ? "Expand" : "Collapse")
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }

    /// pi 标签 / 书签的胶囊。
    private func anchorLabel(_ label: String) -> some View {
        Label(label, systemImage: "bookmark.fill")
            .font(.caption2)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.tint.opacity(0.14), in: Capsule())
            .foregroundStyle(.tint)
    }

    private var iconStyle: AnyShapeStyle {
        row.isActiveLeaf || row.isOnActivePath ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    private var icon: String {
        switch row.role {
        case "user": return "person.fill"
        case "assistant": return "sparkle"
        default: return row.kind == "bashExecution" ? "terminal" : "doc.text"
        }
    }
}

#Preview {
    // 预览专用内存容器；创建失败即视为开发环境异常。
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Session.self, Message.self, ToolCall.self, MessageImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    let session = Session(title: "Preview")
    container.mainContext.insert(session)
    session.append(Message(role: .user, content: "What does this project do?"))
    session.record(
        ToolCall(
            toolCallID: "call_1",
            name: "bash",
            arguments: "command: ls",
            output: "AGENTS.md  README.md  PiDesktop",
            durationMs: 12
        ))
    session.append(
        Message(
            role: .assistant,
            content:
                "PiDesktop is a **native macOS GUI** for the `pi` coding agent.\n\n- Sessions\n- Streaming chat",
            thinking: "The user asks what the project does, so summarize the README."
        ))

    let store = SessionStore(container: container, makeTransport: { _, _ in MockAgentTransport() })
    let workspaceStore = WorkspaceStore(
        defaults: UserDefaults(suiteName: "ChatViewPreview") ?? .standard,
        root: URL(fileURLWithPath: "/tmp/pi-sessions-preview")
    )
    return NavigationStack { ChatView(session: session) }
        .environment(store)
        .environment(workspaceStore)
        .environment(AppSettingsStore(defaults: UserDefaults(suiteName: "ChatViewPreview") ?? .standard))
        .modelContainer(container)
}
