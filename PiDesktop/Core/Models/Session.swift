//
//  Session.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// 一次 agent 会话：标题、工作目录、状态与消息集合。
///
/// 领域模型（见 ADR-0004）。`messages` 采用级联删除：删除会话即删除其全部消息。
@Model
final class Session {
    /// 领域标识，供 agent 事件（ADR-0003）跨层引用；独立于 SwiftData 的 `persistentModelID`。
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    /// 最近活动时间；`append(_:)` 会同步更新，列表据此倒序排列。
    var updatedAt: Date
    /// 工作目录；nil 表示尚未绑定项目。
    var workingDirectory: String?
    /// 对应的 pi 会话文件路径；nil 表示尚未落盘（新会话或未启用持久化）。
    var piSessionPath: String?
    var status: SessionStatus

    @Relationship(deleteRule: .cascade, inverse: \Message.session)
    var messages: [Message]

    init(
        title: String = "",
        workingDirectory: String? = nil,
        piSessionPath: String? = nil,
        createdAt: Date = .now,
        status: SessionStatus = .active
    ) {
        self.id = UUID()
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.workingDirectory = workingDirectory
        self.piSessionPath = piSessionPath
        self.status = status
        self.messages = []
    }

    /// 追加一条消息并刷新 `updatedAt`。
    ///
    /// 只负责维护关系；持久化交给 SwiftData 的自动保存，调用方无需显式 `save()`。
    func append(_ message: Message) {
        messages.append(message)
        updatedAt = message.createdAt
    }
}

/// 会话状态。以 `String` 原始值持久化，保证新增枚举值不影响旧数据解码。
enum SessionStatus: String, Codable, CaseIterable {
    case active
    case archived
}
