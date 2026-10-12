//
//  ChatView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import SwiftData

/// 会话详情：消息流 + 输入框，经 `SessionStore` 与 pi 通信（ADR-0003）。
struct ChatView: View {
    let session: Session
    @Environment(SessionStore.self) private var store
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if store.isStreaming(session) { statusBar }
            Divider()
            composer
        }
        .navigationTitle(session.title.isEmpty ? "Untitled Session" : session.title)
        .toolbar {
            if store.isStreaming(session) {
                ToolbarItem {
                    Button {
                        Task { await store.interrupt(session) }
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(sortedMessages) { message in
                    MessageRow(message: message, isStreaming: isStreaming(message))
                        .id(message.id)
                }
            }
            .listStyle(.inset)
            .onChange(of: sortedMessages.count) { _, _ in
                guard let last = sortedMessages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(store.activeToolName.map { "Running \($0)…" } ?? "Thinking…")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .disabled(trimmedDraft.isEmpty || store.isStreaming(session))
        }
        .padding()
    }

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

/// 单条消息：角色标签 + 内容。
private struct MessageRow: View {
    let message: Message
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role.tint)
            Text(message.content.isEmpty && isStreaming ? "…" : message.content)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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
            for: Session.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    let session = Session(title: "Preview")
    container.mainContext.insert(session)
    session.append(Message(role: .user, content: "What does this project do?"))
    session.append(Message(role: .assistant, content: "PiDesktop is a native macOS GUI for the pi coding agent."))

    let store = SessionStore(container: container, makeTransport: { _, _ in MockAgentTransport() })
    return NavigationStack { ChatView(session: session) }
        .environment(store)
        .modelContainer(container)
}
