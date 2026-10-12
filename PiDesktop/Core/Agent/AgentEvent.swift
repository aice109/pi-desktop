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
    /// 自动重试开始（如限流/过载）。
    case retryStarted(attempt: Int, maxAttempts: Int)
    /// 自动重试结束（成功或彻底失败）。
    case retryFinished(success: Bool)
    /// 上下文压缩开始。
    case compactionStarted
    /// 上下文压缩结束。
    case compactionFinished(aborted: Bool, errorMessage: String?)
    /// 自动工作全部结束（`agent_settled`）。
    case settled(aborted: Bool)
    /// 待处理队列变化（`queue_update`）：完整替换，不是增量。
    case queueUpdated(AgentQueue)
    /// 会话显示名变化（`session_info_changed`）；`nil` 表示被清除。
    case sessionInfoChanged(name: String?)
    /// 思考等级变化（`thinking_level_changed`，可能由扩展或 TUI 侧触发）。
    case thinkingLevelChanged(level: String)
    /// 压缩 / 分支摘要的重试开始。
    case summarizationRetryStarted
    /// 压缩 / 分支摘要的重试结束。
    case summarizationRetryFinished
    /// 会话树追加了新条目（扩展写入或分支变化），提示上层可重新同步历史。
    case entryAppended
    /// 传输层失败（进程退出、读取错误等）。
    case failed(String)
}

/// 待处理的 steering / follow-up 消息（`queue_update`）。
nonisolated struct AgentQueue: Sendable, Equatable {
    var steering: [String] = []
    var followUp: [String] = []

    var isEmpty: Bool { steering.isEmpty && followUp.isEmpty }
}

/// 进行中的非阻塞活动（用于状态栏提示）。
nonisolated enum AgentActivity: Sendable, Equatable {
    case retrying(attempt: Int, maxAttempts: Int)
    case compacting
    case summarizing

    /// 状态栏文案。
    var displayText: String {
        switch self {
        case .retrying(let attempt, let maxAttempts):
            return maxAttempts > 1 ? "Retrying (\(attempt)/\(maxAttempts))…" : "Retrying…"
        case .compacting:
            return "Compacting context…"
        case .summarizing:
            return "Summarizing…"
        }
    }
}

/// 与 agent 通信的抽象。
///
/// 用协议隔离真实子进程，便于测试与未来更换传输方式（`coding-conventions.md` §8）。
/// 约定：`events()` 只需调用一次，且必须在 `prompt(_:)` 之前调用，避免丢失早期事件。
/// `prompt` 被 pi 接受后的处置方式（对应响应的 `data.disposition`）。
nonisolated enum PromptDisposition: String, Sendable, Equatable {
    /// 已开始一次运行，之后会收到事件流。
    case started
    /// 运行中，已进入队列（需要 `streamingBehavior`）。
    case queued
    /// 被扩展命令 / 输入处理器立即消费，不会启动运行、也不会有 `agent_settled`。
    case handled

    /// 未知值按 `started` 处理，兼容 pi 未来新增的处置方式。
    init(raw: String?) {
        self = raw.flatMap(PromptDisposition.init(rawValue:)) ?? .started
    }
}

protocol AgentTransport: Sendable {
    /// 事件流。
    func events() async -> AsyncStream<AgentEvent>
    /// 发送一条用户 prompt；返回即表示已被接受（不代表运行完成）。
    ///
    /// 返回值区分「启动运行」「排队」「被立即处理」：`handled` 不会再有事件，调用方需据此收尾。
    @discardableResult
    func prompt(_ message: String) async throws -> PromptDisposition
    /// 在运行中排队一条 steering 消息；在当前回合的工具调用完成后投递。
    @discardableResult
    func steer(_ message: String) async throws -> PromptDisposition
    /// 在运行中排队一条 follow-up 消息；仅在 agent 完全停下后才投递。
    @discardableResult
    func followUp(_ message: String) async throws -> PromptDisposition
    /// 清空待处理的 steering / follow-up 队列，并返回被清空的文本（供客户端还原到输入框）。
    func clearQueue() async -> AgentQueue
    /// 中断当前运行。
    func abort() async
    /// 关闭底层进程/连接。
    func shutdown() async
    /// 查询当前会话状态（`get_state`）：模型、思考等级、会话文件等。
    func sessionState() async -> AgentSessionState?
    /// 可选模型列表（`get_available_models`）。
    func availableModels() async -> [AgentModel]
    /// 切换模型；返回是否成功。
    func setModel(_ model: AgentModel) async -> Bool
    /// 设置思考等级；返回是否成功。
    func setThinkingLevel(_ level: String) async -> Bool
    /// 设置会话显示名（`set_session_name`）；返回是否成功。
    func setSessionName(_ name: String) async -> Bool
    /// 会话用量与上下文占用（`get_session_stats`）。
    func sessionStats() async -> AgentUsage?
    /// 会话完整历史条目（`get_entries`）。
    ///
    /// 与只含当前上下文的 `get_messages` 不同，它包含压缩前历史与遗弃分支，
    /// 因此适合作为刷新本地镜像的权威来源；条目带稳定 id，将来可用 `since` 增量同步。
    func sessionEntries() async -> [SessionEntryDTO]
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
