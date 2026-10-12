//
//  PiSessionSummary.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 一个 pi 会话文件的摘要，用于工作区会话列表（只读，不修改 pi 的数据）。
///
/// 来源：`~/.pi/agent/sessions/--<path>--/*.jsonl`（见 pi `docs/session-format.md`）。
nonisolated struct PiSessionSummary: Identifiable, Sendable, Equatable, Hashable {
    /// pi 的会话 id（会话文件头部的 `id`）。
    var sessionID: String
    /// 会话文件路径；同时作为列表标识（比 `sessionID` 更能唯一定位）。
    var fileURL: URL
    /// 用户通过 `/name`、`--name` 设置的显示名。
    var name: String?
    /// 会话绑定的工作目录（文件头部的 `cwd`）。
    var cwd: String
    /// 会话开始时间（文件头部时间戳）。
    var startedAt: Date?
    /// 文件修改时间，近似「最近活动时间」。
    var updatedAt: Date
    /// 参与对话的消息条数（user / assistant / toolResult）。
    var messageCount: Int
    /// 首条用户消息的预览文本。
    var preview: String?

    /// 列表标识用文件路径：即使两个文件共享 id，也能各自区分。
    var id: URL { fileURL }

    /// 列表主标题：显示名 → 首条用户消息 → 兜底文案。
    var displayTitle: String {
        if let name, !name.isEmpty { return name }
        if let preview, !preview.isEmpty { return preview }
        return "Untitled Session"
    }
}

/// 从会话文件解析出的、可直接展示的消息。
nonisolated struct PiDisplayMessage: Sendable, Equatable {
    var role: MessageRole
    var text: String
    var timestamp: Date
}
