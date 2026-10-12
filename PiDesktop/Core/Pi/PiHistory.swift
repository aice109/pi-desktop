//
//  PiHistory.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 一条 pi 历史条目。
///
/// 由会话文件的 `message` 行或 RPC `get_entries` 的条目归一化而来；只承载原始字段，
/// 领域语义由 `PiHistory.make(from:)` 赋予（见 ADR-0004 / ADR-0006）。
nonisolated struct PiHistoryEntry: Sendable, Equatable {
    var role: String
    var content: MessageContentDTO
    var timestamp: Date?
    var toolCallId: String?
    var toolName: String?
    var isError: Bool?
    /// 会话树里的条目 id；会话文件/ RPC 都提供。
    var id: String?
    /// 父条目 id；用于回溯活动分支。
    var parentId: String?
}

/// 一次历史解析的结果：可展示消息 + 工具调用。
nonisolated struct PiHistory: Sendable, Equatable {
    var messages: [PiDisplayMessage] = []
    var toolCalls: [PiStoredToolCall] = []

    var isEmpty: Bool { messages.isEmpty && toolCalls.isEmpty }

    /// 从条目序列构造（纯函数，便于单测）。
    ///
    /// `get_entries` 返回的是**追加式树**，含被遗弃的分支；传入 `leafID` 时先回溯出活动分支，
    /// 只展示该分支（否则分支历史会混成一条线）。文件来源没有叶子信息时保持追加顺序。
    ///
    /// 工具的**参数**不在 `toolResult` 条目里，而属于助手消息的 `toolCall` 块，
    /// 因此先按 id 收集参数，再与 `toolResult` 关联。
    static func make(from entries: [PiHistoryEntry], leafID: String? = nil, now: Date = .now) -> PiHistory {
        // 第一步：按叶子回溯活动分支（如可）。
        let entries = activeBranch(of: entries, leafID: leafID)
        var history = PiHistory()

        // 第一遍：助手消息里的 toolCall 块（携带名称与参数）。
        var byID: [String: (name: String, arguments: String?)] = [:]
        for entry in entries where entry.role == "assistant" {
            guard case .blocks(let blocks) = entry.content else { continue }
            for block in blocks where block.type == "toolCall" {
                guard let id = block.id else { continue }
                byID[id] = (block.name ?? "tool", block.arguments?.compactDescription)
            }
        }

        // 第二遍：按角色产出消息与工具调用，保持条目顺序。
        for entry in entries {
            switch entry.role {
            case "user", "assistant":
                guard let role = displayRole(for: entry.role) else { continue }
                let text = entry.content.joinedText
                let thinking = entry.content.joinedThinking
                let images = entry.content.images
                // 允许仅含思考的助手消息，以及仅含图片的用户消息（ADR-0010）。
                guard !text.isEmpty || !thinking.isEmpty || !images.isEmpty else { continue }
                history.messages.append(PiDisplayMessage(
                    role: role,
                    text: text,
                    thinking: thinking.isEmpty ? nil : thinking,
                    images: images,
                    timestamp: entry.timestamp ?? now
                ))

            case "toolResult":
                let id = entry.toolCallId ?? UUID().uuidString
                let block = byID[id]
                history.toolCalls.append(PiStoredToolCall(
                    toolCallID: id,
                    name: entry.toolName ?? block?.name ?? "tool",
                    arguments: block?.arguments,
                    output: entry.content.joinedText,
                    isError: entry.isError ?? false,
                    timestamp: entry.timestamp ?? now
                ))

            default:
                continue
            }
        }
        return history
    }

    /// 从 `leafID` 沿 `parentId` 回溯到根，返回活动分支（保持时间顺序）。
    ///
    /// 找不到叶子或缺少 id 信息时原样返回，保证向后兼容。
    private static func activeBranch(of entries: [PiHistoryEntry], leafID: String?) -> [PiHistoryEntry] {
        guard let leafID else { return entries }
        var byID: [String: PiHistoryEntry] = [:]
        for entry in entries {
            if let id = entry.id { byID[id] = entry }
        }
        guard byID[leafID] != nil else { return entries }

        var chain: [PiHistoryEntry] = []
        var current: String? = leafID
        // 防御性上限：即使数据里有环也不会死循环。
        for _ in 0...byID.count {
            guard let id = current, let entry = byID[id] else { break }
            chain.append(entry)
            current = entry.parentId
        }
        return chain.reversed()
    }

    /// 条目角色 → 领域角色；工具结果（`toolResult`）单独处理。
    static func displayRole(for role: String) -> MessageRole? {        switch role {
        case "user": return .user
        case "assistant": return .assistant
        default: return nil
        }
    }
}

/// 历史指纹：内容未变时跳过重建本地镜像。
///
/// 只取“形状 + 末尾内容”：足够发现新增回合，又不受时间戳精度差异影响。
nonisolated struct PiHistoryFingerprint: Equatable {
    var messageCount: Int
    var lastMessageText: String
    var lastThinking: String?
    var toolCallCount: Int
    var lastToolCallID: String?

    init(_ history: PiHistory) {
        messageCount = history.messages.count
        lastMessageText = history.messages.last?.text ?? ""
        lastThinking = history.messages.last?.thinking
        toolCallCount = history.toolCalls.count
        lastToolCallID = history.toolCalls.last?.toolCallID
    }
}

/// 把 RPC `get_entries` 的条目接入同一套历史映射。
///
/// 依赖方向保持 `Core/Pi` → `Core/Agent`（与 `PiSessionFiles` 一致）：
/// 传输层只提供 DTO，历史语义留在 `Core/Pi`。
extension SessionEntryDTO {
    var historyEntry: PiHistoryEntry {
        PiHistoryEntry(
            role: message?.role ?? "unknown",
            content: message?.content ?? .text(""),
            timestamp: timestamp.flatMap(PiDate.parse),
            toolCallId: message?.toolCallId,
            toolName: message?.toolName,
            isError: message?.isError,
            id: id,
            parentId: parentId
        )
    }
}

/// pi 的时间戳解析：可能带也可能不带小数秒。
nonisolated enum PiDate {
    static func parse(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
