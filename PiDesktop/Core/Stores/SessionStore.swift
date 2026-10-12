//
//  SessionStore.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// 会话状态的唯一可变来源：把 `Core/Agent` 的领域事件落成 SwiftData 消息。
///
/// 遵循单向数据流（`docs/architecture.md`）：View 发意图、读状态；状态变更只发生在这里。
@MainActor
@Observable
final class SessionStore {
    /// 为会话创建传输实例。测试/预览注入 mock，生产注入 `PiRPCClient`。
    /// 标注 `@MainActor`：工厂仅在主 actor 上调用，且 `PiRPCClient` 的初始化器受主 actor 隔离。
    typealias TransportFactory = @MainActor (_ workingDirectory: URL?) -> any AgentTransport

    /// 持有容器（而非仅 `ModelContext`）：`ModelContext` 不持有其容器，
    /// 容器被释放后再使用 context 会崩溃，因此这里必须强引用。
    private let container: ModelContainer
    private let makeTransport: TransportFactory

    private var modelContext: ModelContext { container.mainContext }
    private var transports: [UUID: any AgentTransport] = [:]
    private var subscriptions: [UUID: Task<Void, Never>] = [:]
    private var streaming: [UUID: Streaming] = [:]

    /// 当前正在执行的工具名（转瞬状态，仅供 UI 展示；工具调用暂不持久化）。
    private(set) var activeToolName: String?

    /// 流式助手消息的累积状态。
    private struct Streaming {
        var message: Message
        var text: String
        var thinking: String
    }

    init(container: ModelContainer, makeTransport: @escaping TransportFactory) {
        self.container = container
        self.makeTransport = makeTransport
    }

    /// 该会话是否正在流式接收。
    func isStreaming(_ session: Session) -> Bool {
        streaming[session.id] != nil
    }

    /// 发送一条用户消息并开始接收助手回复。
    func send(_ rawText: String, in session: Session) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming(session) else { return }

        let transport = await ensureTransport(for: session)

        session.append(Message(role: .user, content: text))
        // 先插入占位的助手消息，流式增量就地更新它。
        let assistant = Message(role: .assistant, content: "")
        session.append(assistant)
        streaming[session.id] = Streaming(message: assistant, text: "", thinking: "")

        do {
            try await transport.prompt(text)
        } catch {
            finish(sessionID: session.id, error: error.localizedDescription)
        }
    }

    /// 中断该会话当前运行。
    func interrupt(_ session: Session) async {
        await transports[session.id]?.abort()
    }

    /// 关闭所有传输与订阅（App 退出时调用）。
    func shutdown() {
        for task in subscriptions.values { task.cancel() }
        subscriptions.removeAll()
        for transport in transports.values {
            Task { await transport.shutdown() }
        }
        transports.removeAll()
        streaming.removeAll()
        activeToolName = nil
    }

    // MARK: - Transport wiring

    private func ensureTransport(for session: Session) async -> any AgentTransport {
        if let existing = transports[session.id] { return existing }

        let workingDirectory = session.workingDirectory.map { URL(fileURLWithPath: $0) }
        let transport = makeTransport(workingDirectory)
        transports[session.id] = transport

        // 先建立订阅、再返回，确保 prompt 之前事件流已就绪。
        let stream = await transport.events()
        let sessionID = session.id
        subscriptions[sessionID] = Task { [weak self] in
            for await event in stream {
                self?.handle(event, sessionID: sessionID)
            }
        }
        return transport
    }

    // MARK: - Event handling

    private func handle(_ event: AgentEvent, sessionID: UUID) {
        switch event {
        case .agentStarted:
            break

        case .textDelta(let delta):
            guard var state = streaming[sessionID] else { return }
            state.text += delta
            state.message.content = state.text
            streaming[sessionID] = state

        case .thinkingDelta(let delta):
            guard var state = streaming[sessionID] else { return }
            state.thinking += delta
            streaming[sessionID] = state

        case .toolCallStarted(_, let name):
            activeToolName = name

        case .toolCallFinished:
            activeToolName = nil

        case .assistantMessageCompleted(let text, _, let errorMessage):
            guard var state = streaming[sessionID] else { return }
            if !text.isEmpty { state.text = text }
            if state.text.isEmpty, let errorMessage {
                state.message.content = errorMessage
            } else {
                state.message.content = state.text
            }
            streaming[sessionID] = state

        case .settled:
            finish(sessionID: sessionID)

        case .failed(let message):
            finish(sessionID: sessionID, error: message)
        }
    }

    /// 结束流式状态；若助手消息仍为空则移除占位，避免空气泡。
    private func finish(sessionID: UUID, error: String? = nil) {
        activeToolName = nil
        guard let state = streaming.removeValue(forKey: sessionID) else { return }

        if let error {
            if state.message.content.isEmpty {
                state.message.content = error
            } else {
                state.message.content += "\n\n\(error)"
            }
        } else if state.message.content.isEmpty {
            modelContext.delete(state.message)
        }
    }
}
