//
//  MockAgentTransport.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import Synchronization

/// 测试与预览用的传输实现：不启动进程，事件由调用方手动注入。
///
/// 放在 App target 以便 `#Preview` 与单元测试共用（避免各自维护一份）。
final class MockAgentTransport: AgentTransport, @unchecked Sendable {
    private let stream: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    /// 用 `Mutex` 而非 `NSLock`：`NSLock` 在 async 上下文中不可用（Swift 6 起为错误）。
    private let sent = Mutex<[String]>([])
    /// `sessionState()` 的返回值，测试/预览可注入。
    private let state = Mutex<AgentSessionState?>(nil)
    /// `availableModels()` 的返回值。
    private let models = Mutex<[AgentModel]>([])
    /// `sessionStats()` 的返回值。
    private let usage = Mutex<AgentUsage?>(nil)
    /// `sessionEntries()` 的返回值。
    private let entries = Mutex<[SessionEntryDTO]>([])
    /// `prompt(_:)` 的返回值。
    private let disposition = Mutex<PromptDisposition>(.started)

    nonisolated init() {
        (stream, continuation) = AsyncStream<AgentEvent>.makeStream(bufferingPolicy: .unbounded)
    }

    /// 已发送的 prompt 文本，供断言。
    var sentPrompts: [String] { sent.withLock { $0 } }

    /// 注入 `sessionState()` 的返回值。
    var sessionStateValue: AgentSessionState? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// 注入 `availableModels()` 的返回值。
    var availableModelsValue: [AgentModel] {
        get { models.withLock { $0 } }
        set { models.withLock { $0 = newValue } }
    }

    /// 注入 `sessionStats()` 的返回值。
    var sessionStatsValue: AgentUsage? {
        get { usage.withLock { $0 } }
        set { usage.withLock { $0 = newValue } }
    }

    /// 注入 `sessionEntries()` 的返回值。
    var sessionEntriesValue: [SessionEntryDTO] {
        get { entries.withLock { $0 } }
        set { entries.withLock { $0 = newValue } }
    }

    /// 注入 `prompt(_:)` 的返回值。
    var promptDispositionValue: PromptDisposition {
        get { disposition.withLock { $0 } }
        set { disposition.withLock { $0 = newValue } }
    }

    func events() async -> AsyncStream<AgentEvent> {
        stream
    }

    @discardableResult
    func prompt(_ message: String) async throws -> PromptDisposition {
        sent.withLock { $0.append(message) }
        return promptDispositionValue
    }

    func abort() async {}

    func sessionState() async -> AgentSessionState? {
        state.withLock { $0 }
    }

    func availableModels() async -> [AgentModel] {
        models.withLock { $0 }
    }

    func setModel(_ model: AgentModel) async -> Bool {
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.model = model
            current = updated
        }
        return true
    }

    func setThinkingLevel(_ level: String) async -> Bool {
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.thinkingLevel = level
            current = updated
        }
        return true
    }

    func setSessionName(_ name: String) async -> Bool {
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.sessionName = name
            current = updated
        }
        return true
    }

    func sessionStats() async -> AgentUsage? {
        usage.withLock { $0 }
    }

    func sessionEntries() async -> [SessionEntryDTO] {
        entries.withLock { $0 }
    }

    func shutdown() async {
        continuation.finish()
    }

    /// 注入一个事件（测试/预览用）。
    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }
}
