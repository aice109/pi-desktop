//
//  ChatView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import SwiftData
import AppKit

/// 会话详情：消息流 + 输入框，经 `SessionStore` 与 pi 通信（ADR-0003）。
struct ChatView: View {
    let session: Session
    @Environment(SessionStore.self) private var store
    @Environment(AppSettingsStore.self) private var appSettings
    @State private var draft = ""
    @State private var models: [AgentModel] = []
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if store.isStreaming(session) { statusArea }
            Divider()
            composer
            usageFooter
        }
        .navigationTitle(session.title.isEmpty ? "Untitled Session" : session.title)
        .navigationSubtitle(session.workingDirectory ?? "")
        .task(id: session.id) {
            // 打开会话即激活 pi（懒启动），并加载模型列表。
            await store.activate(session)
            models = await store.availableModels(for: session)
        }
        .onAppear { isComposerFocused = true }
        .toolbar {
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

    /// 状态栏文案：重试/压缩优先，其次工具，最后默认“思考中”。
    private var statusText: String {
        if let activity = store.activity(for: session) { return activity.displayText }
        if let tool = store.activeToolName { return "Running \(tool)…" }
        return "Thinking…"
    }

    /// 模型选择菜单。
    private var modelMenu: some View {
        Menu {
            if models.isEmpty {
                Text("No models available")
            } else {
                ForEach(models) { model in
                    Button {
                        Task { await store.selectModel(model, in: session) }
                    } label: {
                        if model == currentState?.model {
                            Label(model.displayName, systemImage: "checkmark")
                        } else {
                            Text(model.displayName)
                        }
                    }
                }
            }
        } label: {
            Label(currentState?.model?.displayName ?? "Model", systemImage: "cpu")
        }
        .help("Model")
    }

    /// 思考等级菜单（仅当当前模型支持多个等级时显示）。
    private func thinkingMenu(_ levels: [String]) -> some View {
        Menu {
            ForEach(levels, id: \.self) { level in
                Button {
                    Task { await store.selectThinkingLevel(level, in: session) }
                } label: {
                    if level == currentState?.thinkingLevel {
                        Label(level.capitalized, systemImage: "checkmark")
                    } else {
                        Text(level.capitalized)
                    }
                }
            }
        } label: {
            Label(currentState?.thinkingLevel?.capitalized ?? "Thinking", systemImage: "brain")
        }
        .help("Thinking Level")
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
            .padding(.horizontal, 14)
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
                        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                        .id(row.id)
                }
            }
            .listStyle(.plain)
            .contentMargins(.vertical, 8, for: .scrollContent)
            .onChange(of: items.count) { _, _ in scrollToBottom(proxy, items: items) }
            // 流式追加不会改变条数，需额外监听末条内容变化。
            .onChange(of: lastMessage?.content) { _, _ in scrollToBottom(proxy, items: items) }
            .onChange(of: session.toolCalls.last?.output) { _, _ in scrollToBottom(proxy, items: items) }
            .onAppear { scrollToBottom(proxy, items: items) }
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
                   message.role == .assistant, !message.content.isEmpty {
                    conclusionID = message.id
                }
            }
            for index in range {
                rows.append(ChatRow(
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

    private func scrollToBottom(_ proxy: ScrollViewProxy, items: [TimelineItem]) {
        guard let last = items.last else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    // MARK: - Status

    /// 运行状态：实时思考（可折叠）+ 工具/思考指示。
    @ViewBuilder
    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reasoning = store.reasoning(in: session) {
                ReasoningDisclosure(text: reasoning)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.thinMaterial, in: Capsule())
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...10)
                .focused($isComposerFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(isComposerFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: 1)
                }
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .disabled(trimmedDraft.isEmpty || store.isStreaming(session))
            .keyboardShortcut(.return, modifiers: .command)
            .help("Send (⌘↩)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    /// 消息按时间正序展示（最早的在上）。
    private var sortedMessages: [Message] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        draft = ""
        Task { await store.send(text, in: session) }
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
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if message.role == .user {
            MarkdownText(text: message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
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
    }

    /// 折叠标签用首行文本，方便扫读。
    private var processPreview: String {
        let firstLine = message.content
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return firstLine.isEmpty ? "Process" : firstLine
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
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.red.opacity(toolCall.isError ? 0.5 : 0), lineWidth: 1)
        }
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
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 5))
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

private extension MessageRole {
    var displayName: String {
        switch self {
        case .user: return "You"
        case .assistant: return "Assistant"
        case .tool: return "Tool"
        }
    }

    var symbolName: String {
        switch self {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .tool: return "wrench.and.screwdriver.fill"
        }
    }

    var tint: Color {
        switch self {
        case .user: return .accentColor
        case .assistant: return .primary
        case .tool: return .orange
        }
    }
}

#Preview {
    // 预览专用内存容器；创建失败即视为开发环境异常。
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Session.self, Message.self, ToolCall.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    let session = Session(title: "Preview")
    container.mainContext.insert(session)
    session.append(Message(role: .user, content: "What does this project do?"))
    session.record(ToolCall(
        toolCallID: "call_1",
        name: "bash",
        arguments: "command: ls",
        output: "AGENTS.md  README.md  PiDesktop",
        durationMs: 12
    ))
    session.append(Message(
        role: .assistant,
        content: "PiDesktop is a **native macOS GUI** for the `pi` coding agent.\n\n- Sessions\n- Streaming chat",
        thinking: "The user asks what the project does, so summarize the README."
    ))

    let store = SessionStore(container: container, makeTransport: { _, _ in MockAgentTransport() })
    return NavigationStack { ChatView(session: session) }
        .environment(store)
        .environment(AppSettingsStore(defaults: UserDefaults(suiteName: "ChatViewPreview") ?? .standard))
        .modelContainer(container)
}
