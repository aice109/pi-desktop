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

    nonisolated init() {
        (stream, continuation) = AsyncStream<AgentEvent>.makeStream(bufferingPolicy: .unbounded)
    }

    /// 已发送的 prompt 文本，供断言。
    var sentPrompts: [String] { sent.withLock { $0 } }

    func events() async -> AsyncStream<AgentEvent> {
        stream
    }

    func prompt(_ message: String) async throws {
        sent.withLock { $0.append(message) }
    }

    func abort() async {}

    func shutdown() async {
        continuation.finish()
    }

    /// 注入一个事件（测试/预览用）。
    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }
}
