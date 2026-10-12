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

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if store.isStreaming(session) { statusArea }
            Divider()
            composer
            usageFooter
        }
        .navigationTitle(session.title.isEmpty ? "Untitled Session" : session.title)
        .task(id: session.id) {
            // 打开会话即激活 pi（懒启动），并加载模型列表。
            await store.activate(session)
            models = await store.availableModels(for: session)
        }
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
                    .keyboardShortcut(".", modifiers: .command)
                    .help("Stop")
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
            HStack(spacing: 12) {
                if let percent = usage.contextPercent {
                    Label("\(percent.formatted(.number.precision(.fractionLength(0))))% context", systemImage: "gauge.with.dots.needle.33percent")
                }
                Label("\(usage.totalTokens.formatted()) tokens", systemImage: "number")
                Label(usage.costUSD.formatted(.currency(code: "USD")), systemImage: "dollarsign.circle")
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(timeline) { item in
                    timelineRow(item).id(item.id)
                }
            }
            .listStyle(.inset)
            .onChange(of: timeline.count) { _, _ in scrollToBottom(proxy) }
            // 流式追加不会改变条数，需额外监听末条内容变化。
            .onChange(of: sortedMessages.last?.content) { _, _ in scrollToBottom(proxy) }
            .onChange(of: session.toolCalls.last?.output) { _, _ in scrollToBottom(proxy) }
            .onAppear { scrollToBottom(proxy) }
        }
    }

    /// 消息与工具调用按时间合并成正序时间线。
    private var timeline: [TimelineItem] {
        let messages = session.messages.map(TimelineItem.message)
        let toolCalls = session.toolCalls.map(TimelineItem.toolCall)
        return (messages + toolCalls).sorted { $0.date < $1.date }
    }

    @ViewBuilder
    private func timelineRow(_ item: TimelineItem) -> some View {
        switch item {
        case .message(let message):
            MessageRow(message: message, isStreaming: isStreaming(message))
        case .toolCall(let toolCall):
            ToolCallCard(toolCall: toolCall)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard let last = timeline.last else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    // MARK: - Status

    /// 运行状态：实时思考（可折叠）+ 工具/思考指示。
    @ViewBuilder
    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let reasoning = store.reasoning(in: session) {
                ReasoningDisclosure(text: reasoning)
                    .padding(.horizontal)
                    .padding(.top, 6)
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(8)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .onSubmit(send)
            Button(action: send) {
                Label("Send", systemImage: "arrow.up.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(trimmedDraft.isEmpty || store.isStreaming(session))
            .help("Send")
        }
        .padding()
    }

    // MARK: - Helpers

    /// 消息按时间正序展示（最早的在上）。
    private var sortedMessages: [Message] {
        session.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isStreaming(_ message: Message) -> Bool {
        message.role == .assistant
            && store.isStreaming(session)
            && message.id == sortedMessages.last?.id
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

// MARK: - Message row

/// 单条消息：角色 + 时间 + 内容（助手/用户按 Markdown，工具结果用等宽卡片）。
private struct MessageRow: View {
    let message: Message
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            if let thinking = message.thinking, !thinking.isEmpty {
                ReasoningDisclosure(text: thinking)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(message.content, forType: .string)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: message.role.symbolName)
                .font(.caption)
            Text(message.role.displayName)
                .font(.caption.weight(.semibold))
            Spacer()
            Text(message.createdAt, format: .dateTime.hour().minute())
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(message.role.tint)
    }

    @ViewBuilder
    private var content: some View {
        if message.content.isEmpty && isStreaming {
            Text("…").foregroundStyle(.secondary)
        } else if message.role == .tool {
            Text(message.content)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        } else {
            MarkdownText(text: message.content)
                .textSelection(.enabled)
        }
    }
}

/// 可折叠的思考内容（实时与历史共用）。
private struct ReasoningDisclosure: View {
    let text: String

    var body: some View {
        DisclosureGroup("Reasoning") {
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// 工具调用卡片：名称 + 参数 + 状态 + 可折叠输出。
private struct ToolCallCard: View {
    let toolCall: ToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(toolCall.name)
                    .font(.caption.weight(.semibold))
                if let arguments = toolCall.arguments, !arguments.isEmpty {
                    Text(arguments)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                status
            }
            if let output = toolCall.output, !output.isEmpty {
                DisclosureGroup("Output") {
                    Text(output)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

    @ViewBuilder
    private var status: some View {
        HStack(spacing: 4) {
            if toolCall.isError {
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            } else if let durationMs = toolCall.durationMs {
                Text("\(durationMs) ms")
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
}

/// 用原生 Markdown 解析渲染文本；解析失败则回退为纯文本。
///
/// 采用 inline-only：保留换行与粗体/行内代码等行内格式，但不解释块级结构
/// （SwiftUI `Text` 不渲染列表/标题的块级 presentation intent）。
private struct MarkdownText: View {
    let text: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
        } else {
            Text(text)
        }
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
