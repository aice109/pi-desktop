//
//  AgentEvent.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 从 pi 事件流映射出的**领域事件**。
///
/// 这是 `Core/Agent` 的对外边界：上层（`SessionStore` / UI）只消费这些领域事件，
/// 不感知 JSONL、子进程等传输细节（见 `docs/pi-agent.md`、ADR-0003）。
nonisolated enum AgentEvent: Sendable, Equatable {
    /// 一次底层 agent 运行开始。
    case agentStarted
    /// 助手文本增量（用于流式渲染）。
    case textDelta(String)
    /// 助手思考增量（用于折叠的 reasoning 区）。
    case thinkingDelta(String)
    /// 工具调用开始。`arguments` 为参数的紧凑文本（如 `command: ls`）。
    case toolCallStarted(id: String, name: String, arguments: String?)
    /// 工具调用输出更新（`tool_execution_update` 的最新部分结果）。
    case toolCallUpdated(id: String, output: String)
    /// 工具调用结束。`output` 为最终输出（可能为空）。
    case toolCallFinished(id: String, name: String, isError: Bool, durationMs: Int?, output: String?)
    /// 一条助手消息完成（`message_end` 的权威内容）。
    case assistantMessageCompleted(text: String, stopReason: String?, errorMessage: String?)
    /// 自动工作全部结束（`agent_settled`）。
    case settled(aborted: Bool)
    /// 传输层失败（进程退出、读取错误等）。
    case failed(String)
}

/// 与 agent 通信的抽象。
///
/// 用协议隔离真实子进程，便于测试与未来更换传输方式（`coding-conventions.md` §8）。
/// 约定：`events()` 只需调用一次，且必须在 `prompt(_:)` 之前调用，避免丢失早期事件。
protocol AgentTransport: Sendable {
    /// 事件流。
    func events() async -> AsyncStream<AgentEvent>
    /// 发送一条用户 prompt；返回即表示已被接受（不代表运行完成）。
    func prompt(_ message: String) async throws
    /// 中断当前运行。
    func abort() async
    /// 关闭底层进程/连接。
    func shutdown() async
    /// 查询当前会话信息（`get_state`）；新会话由 pi 落盘后才有 `sessionFile`。
    func sessionInfo() async -> AgentSessionInfo?
}

/// pi 会话的运行时信息。
nonisolated struct AgentSessionInfo: Sendable, Equatable {
    /// 会话文件路径（pi 持久化时存在）。
    var sessionFile: String?
    var sessionId: String?
    var sessionName: String?
}

/// 传输层错误。
nonisolated enum AgentTransportError: Error, Equatable, LocalizedError {
    case executableNotFound
    case launchFailed(String)
    case notConnected
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "找不到可执行的 pi CLI，请确认已安装 pi 或设置 PI_EXECUTABLE 环境变量。"
        case .launchFailed(let message):
            return "启动 pi 进程失败：\(message)"
        case .notConnected:
            return "尚未连接到 pi 进程。"
        case .commandFailed(let message):
            return "pi 拒绝了命令：\(message)"
        }
    }
}
