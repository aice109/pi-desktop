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
    /// 分支结构总览（`get_tree`）。
    @State private var sessionTree: AgentSessionTree?
    @State private var isShowingTree = false
    /// 手动压缩（可带自定义指令）的弹窗。
    @State private var isCompactionPromptPresented = false
    @State private var compactionInstructions = ""
    /// 会话内搜索。
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var scrollTarget: UUID?
    /// 当前是否贴近底部（决定“回到底部”按钮是否出现）。
    @State private var isAtBottom = true
    /// 是否跟随底部：内容增长时自动滚动；用户主动上滑后暂停。
    @State private var isFollowingBottom = true
    /// 最近一次滚动阶段，用于区分用户滚动与程序滚动。
    @State private var scrollPhase: ScrollPhase = .idle
    @FocusState private var isComposerFocused: Bool

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
        .navigationSubtitle(session.workingDirectory ?? "")
        .task(id: session.id) {
            // 打开会话即激活 pi（懒启动），并加载模型列表。
            await store.activate(session)
            models = await store.availableModels(for: session)
            commands = await store.availableCommands(for: session)
        }
        .onAppear { isComposerFocused = true }
        .sheet(isPresented: $isShowingTree) {
            SessionTreeSheet(tree: sessionTree) { entryId in
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
        .toolbar {
            ToolbarItem { findButton }
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
                Task {
                    sessionTree = await store.sessionTree(for: session)
                    isShowingTree = true
                }
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
        let rows = chatRows(from: items)
        let lastMessage = sortedMessages.last
        let isStreamingSession = store.isStreaming(session)

        return ScrollViewReader { proxy in
            List {
                ForEach(rows) { row in
                    timelineRow(row, isStreaming: isStreamingSession && row.id == lastMessage?.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .id(row.id)
                }
            }
            .listStyle(.plain)
            .contentMargins(.vertical, 8, for: .scrollContent)
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
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
                scrollTarget = nil
            }
            .onChange(of: items.count) { _, _ in autoScroll(proxy, items: items) }
            // 流式追加不会改变条数，需额外监听末条内容变化。
            .onChange(of: lastMessage?.content) { _, _ in autoScroll(proxy, items: items) }
            .onChange(of: session.toolCalls.last?.output) { _, _ in autoScroll(proxy, items: items) }
            .onAppear {
                isAtBottom = true
                isFollowingBottom = true
                scrollToBottom(proxy, items: items, animated: false)
            }
            .overlay(alignment: .bottomTrailing) {
                // 用户翻到上面时给出“回到底部”的入口。
                if !isAtBottom, !items.isEmpty {
                    scrollToBottomButton(proxy, items: items)
                        .padding(.trailing, 20)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottomTrailing)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isAtBottom)
        }
    }

    /// 消息与工具调用按时间合并成正序时间线。
    private var timeline: [TimelineItem] {
        let messages = session.messages.map(TimelineItem.message)
        let toolCalls = session.toolCalls.map(TimelineItem.toolCall)
        return (messages + toolCalls).sorted { $0.date < $1.date }
    }

    /// 把时间线切成「回合」并标注每行的展示方式。
    ///
    /// 回合 = 一条用户消息到下一个用户消息之前。每个回合只保留最后一条有正文的助手消息
    /// 作为「结论」常显；其余（思考、工具调用、中间旁白）默认折叠。
    private func chatRows(from items: [TimelineItem]) -> [ChatRow] {
        guard !items.isEmpty else { return [] }
        let flags = headerFlags(for: items)

        // 回合起点：首条 + 每条（非首位的）用户消息。
        var starts = [0]
        for index in items.indices.dropFirst() {
            if case .message(let message) = items[index], message.role == .user {
                starts.append(index)
            }
        }
        starts.append(items.count)

        var rows: [ChatRow] = []
        for turn in 0..<(starts.count - 1) {
            let range = starts[turn]..<starts[turn + 1]
            // 结论 = 本回合最后一条有正文的助手消息（流式占位为空时不算）。
            var conclusionID: UUID?
            for index in range {
                if case .message(let message) = items[index],
                    message.role == .assistant, !message.content.isEmpty
                {
                    conclusionID = message.id
                }
            }
            for index in range {
                rows.append(
                    ChatRow(
                        item: items[index],
                        showsHeader: flags[index],
                        isConclusion: items[index].id == conclusionID,
                        startsTurn: index == range.lowerBound
                    ))
            }
        }
        return rows
    }

    /// 每行是否显示角色头部：首条，或与上一条角色不同（连续同一角色消息合并展示）。
    ///
    /// 一次算完整列标记，避免每行都去重排整条时间线（长会话的 O(n²) 源头）。
    private func headerFlags(for items: [TimelineItem]) -> [Bool] {
        var flags = [Bool](repeating: true, count: items.count)
        for index in items.indices.dropFirst() {
            guard case .message(let previous) = items[index - 1],
                case .message(let current) = items[index]
            else { continue }
            flags[index] = previous.role != current.role
        }
        return flags
    }

    @ViewBuilder
    private func timelineRow(_ row: ChatRow, isStreaming: Bool) -> some View {
        switch row.item {
        case .message(let message):
            MessageRow(
                message: message,
                isStreaming: isStreaming,
                showsHeader: row.showsHeader,
                isCollapsed: message.role == .assistant && !row.isConclusion
            )
            .padding(.top, row.startsTurn ? 8 : 0)
        case .toolCall(let toolCall):
            ToolCallCard(toolCall: toolCall, isRunning: store.isRunningTool(toolCall.toolCallID))
                .padding(.top, row.startsTurn ? 8 : 0)
        }
    }

    private func scrollToBottomButton(_ proxy: ScrollViewProxy, items: [TimelineItem]) -> some View {
        Button {
            isFollowingBottom = true
            scrollToBottom(proxy, items: items, animated: true)
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
    private func autoScroll(_ proxy: ScrollViewProxy, items: [TimelineItem]) {
        guard isFollowingBottom else { return }
        scrollToBottom(proxy, items: items, animated: true)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, items: [TimelineItem], animated: Bool) {
        guard let last = items.last else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(last.id, anchor: .bottom) }
        } else {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
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

/// 时间线的一行：原始项 + 展示标记。
private struct ChatRow: Identifiable {
    let item: TimelineItem
    let showsHeader: Bool
    /// 是否为该回合的「结论」（最后一条有正文的助手消息）。
    let isConclusion: Bool
    /// 是否为回合首行，用于增加段间距。
    let startsTurn: Bool

    var id: UUID { item.id }
}

// MARK: - Message row

/// 单条消息：角色头像 + （可选）头部 + 内容。
///
/// 连续的同一角色消息只在其首条显示头部，减少视觉噪音。
private struct MessageRow: View {
    let message: Message
    let isStreaming: Bool
    let showsHeader: Bool
    /// 非结论的助手正文默认折叠为「过程」。
    let isCollapsed: Bool
    @State private var isProcessExpanded = false

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
        } else if isCollapsed {
            processDisclosure
        } else {
            MarkdownText(text: message.content)
                .textSelection(.enabled)
        }
    }

    /// 回合中间旁白：折叠为一行预览，展开后同样按 Markdown 渲染。
    private var processDisclosure: some View {
        DisclosureGroup(isExpanded: $isProcessExpanded) {
            MarkdownText(text: message.content)
                .textSelection(.enabled)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.caption)
                Text(processPreview)
                    .font(.callout)
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .disclosureGroupStyle(RowDisclosureGroupStyle())
    }

    /// 折叠标签用首行文本，方便扫读。
    private var processPreview: String {
        let firstLine =
            message.content
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return firstLine.isEmpty ? "Process" : firstLine
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
private struct SessionTreeSheet: View {
    let tree: AgentSessionTree?
    let onFork: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Session Tree")
                .font(.headline)
                .padding([.horizontal, .top], 16)
                .padding(.bottom, 8)
            if let roots = tree?.roots, !roots.isEmpty {
                List {
                    OutlineGroup(roots, children: \.optionalChildren) { node in
                        SessionTreeRow(node: node, isActive: node.id == tree?.leafId, onFork: onFork)
                    }
                }
            } else {
                Text("This session has no entries yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: 420)
    }
}

/// 树中的一行：图标 + 预览 + 类型 + fork / 活动叶子标记。
private struct SessionTreeRow: View {
    let node: AgentTreeNode
    let isActive: Bool
    let onFork: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(node.preview.isEmpty ? node.kind : node.preview)
                    .lineLimit(1)
                Text(node.kind)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if node.isUserMessage {
                Button("Fork") { onFork(node.id) }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            if isActive {
                Image(systemName: "smallcircle.filled.circle")
                    .foregroundStyle(.tint)
                    .help("Active branch tip")
            }
        }
    }

    private var icon: String {
        switch node.role {
        case "user": return "person.fill"
        case "assistant": return "sparkle"
        default: return node.kind == "bashExecution" ? "terminal" : "doc.text"
        }
    }
}

extension AgentTreeNode {
    /// `OutlineGroup` 用：叶子返回 nil 即不显示展开箭头。
    fileprivate var optionalChildren: [AgentTreeNode]? { children.isEmpty ? nil : children }
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
    return NavigationStack { ChatView(session: session) }
        .environment(store)
        .environment(AppSettingsStore(defaults: UserDefaults(suiteName: "ChatViewPreview") ?? .standard))
        .modelContainer(container)
}
