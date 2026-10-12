//
//  RPCRecords.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

// RPC/JSON 线上报文的解码 DTO 与领域事件映射。
//
// 全部标记 `nonisolated`：解码发生在后台读取循环，不能依赖主 actor。
// 字段只覆盖当前需要的部分，未知字段一律忽略（向前兼容）。

/// 一条 RPC/JSON 记录。`response` 与 session event 复用同一结构，按 `type` 区分。
nonisolated struct RPCRecord: Decodable {
    var type: String
    var id: String?
    var command: String?
    var success: Bool?
    var error: String?
    var aborted: Bool?
    var assistantMessageEvent: AssistantMessageEventDTO?
    var message: MessageDTO?
    var toolCallId: String?
    var toolName: String?
    var isError: Bool?
    var durationMs: Int?
    var args: JSONValue?
    var result: ToolResultDTO?
    var partialResult: ToolResultDTO?
    // 重试 / 压缩事件
    var attempt: Int?
    var maxAttempts: Int?
    var delayMs: Int?
    var errorMessage: String?
    var reason: String?
    var data: RPCDataDTO?
}

/// 工具执行结果（`result` / `partialResult`）；只取其中的文本内容。
nonisolated struct ToolResultDTO: Decodable {
    var content: MessageContentDTO?
}

/// 命令响应的 `data` 字段（`get_state` / `get_session_stats` / 模型命令）。
nonisolated struct RPCDataDTO: Decodable {
    var sessionFile: String?
    var sessionId: String?
    var sessionName: String?
    var messageCount: Int?
    var model: ModelDTO?
    var thinkingLevel: String?
    var levels: [String]?
    var models: [ModelDTO]?
    var isStreaming: Bool?
    // get_session_stats
    var tokens: TokensDTO?
    var cost: Double?
    var contextUsage: ContextUsageDTO?
}

/// 模型定义（完整字段只取需要的部分）。
nonisolated struct ModelDTO: Decodable {
    var id: String
    var name: String?
    var provider: String?
    var reasoning: Bool?
    var contextWindow: Int?

    var domain: AgentModel {
        AgentModel(
            id: id,
            name: name ?? id,
            provider: provider ?? "",
            reasoning: reasoning ?? false,
            contextWindow: contextWindow
        )
    }
}

nonisolated struct TokensDTO: Decodable {
    var input: Int?
    var output: Int?
    var cacheRead: Int?
    var cacheWrite: Int?
    var total: Int?
}

nonisolated struct ContextUsageDTO: Decodable {
    var tokens: Int?
    var contextWindow: Int?
    /// pi 返回的是小数（如 `11.4525`），不能用 `Int`。
    var percent: Double?
}

/// `message_update.assistantMessageEvent`。
nonisolated struct AssistantMessageEventDTO: Decodable {
    var type: String
    var contentIndex: Int?
    var delta: String?
    var content: String?
    var toolName: String?
}

/// 事件里的消息：只关心 role 与合并后的文本。
nonisolated struct MessageDTO: Decodable {
    var role: String
    var content: MessageContentDTO
    var stopReason: String?
    var errorMessage: String?
}

/// 消息内容可能是字符串（system）或内容块数组（user/assistant）。
nonisolated enum MessageContentDTO: Decodable {
    case text(String)
    case blocks([ContentBlockDTO])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
            return
        }
        self = .blocks(try container.decode([ContentBlockDTO].self))
    }

    /// 拼接所有 `text` 块（忽略 thinking / toolCall 块）。
    var joinedText: String {
        switch self {
        case .text(let value):
            return value
        case .blocks(let blocks):
            return blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
    }

    /// 拼接所有 `thinking` 块（助手的思考过程）。
    var joinedThinking: String {
        guard case .blocks(let blocks) = self else { return "" }
        return blocks.compactMap { $0.type == "thinking" ? $0.thinking : nil }.joined()
    }
}

/// 内容块。
nonisolated struct ContentBlockDTO: Decodable {
    var type: String
    var text: String?
    var thinking: String?
    // toolCall 块
    var id: String?
    var name: String?
    var arguments: JSONValue?
}

/// 线上报文 → 领域事件的映射（纯函数，便于单测）。
nonisolated enum RPCProtocol {
    static func decode(_ line: Data) -> RPCRecord? {
        try? JSONDecoder().decode(RPCRecord.self, from: line)
    }

    /// 把一条记录映射为领域事件；`response` 与未知记录返回 `nil`。
    static func agentEvent(from record: RPCRecord) -> AgentEvent? {
        switch record.type {
        case "agent_start":
            return .agentStarted

        case "message_update":
            guard let update = record.assistantMessageEvent else { return nil }
            switch update.type {
            case "text_delta":
                return update.delta.map(AgentEvent.textDelta)
            case "thinking_delta":
                return update.delta.map(AgentEvent.thinkingDelta)
            default:
                return nil
            }

        case "tool_execution_start":
            guard let id = record.toolCallId, let name = record.toolName else { return nil }
            return .toolCallStarted(id: id, name: name, arguments: record.args?.compactDescription)

        case "tool_execution_update":
            guard let id = record.toolCallId, let output = record.partialResult?.content?.joinedText else {
                return nil
            }
            return .toolCallUpdated(id: id, output: output)

        case "tool_execution_end":
            guard let id = record.toolCallId, let name = record.toolName else { return nil }
            return .toolCallFinished(
                id: id,
                name: name,
                isError: record.isError ?? false,
                durationMs: record.durationMs,
                output: record.result?.content?.joinedText
            )

        case "message_end":
            // 只关心助手消息；用户/系统消息由本地写入或忽略。
            guard let message = record.message, message.role == "assistant" else { return nil }
            return .assistantMessageCompleted(
                text: message.content.joinedText,
                stopReason: message.stopReason,
                errorMessage: message.errorMessage
            )

        case "auto_retry_start":
            return .retryStarted(attempt: record.attempt ?? 1, maxAttempts: record.maxAttempts ?? 1)

        case "auto_retry_end":
            return .retryFinished(success: record.success ?? true)

        case "compaction_start":
            return .compactionStarted

        case "compaction_end":
            return .compactionFinished(aborted: record.aborted ?? false, errorMessage: record.errorMessage)

        case "agent_settled":
            return .settled(aborted: record.aborted ?? false)

        default:
            return nil
        }
    }
}
