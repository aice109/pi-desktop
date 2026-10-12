//
//  ToolCall.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// 一次工具调用（`bash`、`read`、`edit`…）。
///
/// 领域模型（见 ADR-0006）。与 `Message` 并列组成会话时间线：工具调用是一次独立活动，
/// 有自己的参数、输出、状态与耗时，不适合塞进 `Message.content`。
@Model
final class ToolCall {
    /// 本地领域标识。
    @Attribute(.unique) var id: UUID
    /// pi 的 `toolCallId`，用于关联开始/更新/结束事件。
    var toolCallID: String
    var name: String
    /// 参数的紧凑文本（如 `command: ls -la`）；历史导入时可能缺失。
    var arguments: String?
    /// 输出文本；运行中可能为部分结果。
    var output: String?
    var isError: Bool
    /// 工具 `execute()` 的耗时（毫秒）；未运行/未知时为 nil。
    var durationMs: Int?
    var createdAt: Date
    /// 反向关系；`Session.toolCalls` 持有数组并负责级联删除。
    var session: Session?

    init(
        toolCallID: String,
        name: String,
        arguments: String? = nil,
        output: String? = nil,
        isError: Bool = false,
        durationMs: Int? = nil,
        createdAt: Date = .now
    ) {
        self.id = UUID()
        self.toolCallID = toolCallID
        self.name = name
        self.arguments = arguments
        self.output = output
        self.isError = isError
        self.durationMs = durationMs
        self.createdAt = createdAt
    }
}
