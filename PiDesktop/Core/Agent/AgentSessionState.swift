//
//  AgentSessionState.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 一个可选的模型（来自 `get_available_models` / `get_state`）。
nonisolated struct AgentModel: Sendable, Equatable, Identifiable, Hashable {
    /// 模型的 `modelId`。
    var id: String
    var name: String
    var provider: String
    /// 是否支持思考等级。
    var reasoning: Bool
    var contextWindow: Int?

    /// 展示名：优先 `name`，否则回退 `id`。
    var displayName: String { name.isEmpty ? id : name }
}

/// 会话的运行时状态（来自 `get_state`）。
nonisolated struct AgentSessionState: Sendable, Equatable {
    var model: AgentModel?
    var thinkingLevel: String?
    /// 当前模型支持的思考等级；不支持时通常为 `["off"]`。
    var availableThinkingLevels: [String] = []
    /// 会话文件路径；pi 持久化时存在。
    var sessionFile: String?
    var sessionId: String?
    var sessionName: String?
    var isStreaming: Bool = false
}

/// 会话的 token / 费用 / 上下文占用（来自 `get_session_stats`）。
nonisolated struct AgentUsage: Sendable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int
    var totalTokens: Int
    /// 累计费用（美元）。
    var costUSD: Double
    /// 当前上下文窗口占用（令牌数）；未知时为 nil。
    var contextTokens: Int?
    var contextWindow: Int?
    /// 上下文占用百分比；未知时为 nil。
    var contextPercent: Double?
}
