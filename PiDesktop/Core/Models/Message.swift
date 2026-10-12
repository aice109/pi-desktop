//
//  Message.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// 会话中的一条消息（用户 / 助手 / 工具结果）。
///
/// 领域模型（见 ADR-0004）。仅存聚合后的内容；流式增量由 `Core/Agent` 聚合后再写入，
/// 避免为每个 delta 建一条记录。
@Model
final class Message {
    /// 领域标识，供 agent 事件（ADR-0003）跨层引用；独立于 SwiftData 的 `persistentModelID`。
    @Attribute(.unique) var id: UUID
    var role: MessageRole
    var content: String
    /// 助手的思考过程（reasoning）；非助手消息或未暴露时为 nil。
    var thinking: String?
    var createdAt: Date
    /// 反向关系；`Session.messages` 持有数组并负责级联删除。
    var session: Session?

    /// 附带的图片（ADR-0010）；仅为用户消息。
    @Relationship(deleteRule: .cascade, inverse: \MessageImage.message)
    var images: [MessageImage]

    init(role: MessageRole, content: String, thinking: String? = nil, createdAt: Date = .now) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.thinking = thinking
        self.createdAt = createdAt
        self.images = []
    }
}

/// 消息角色。以 `String` 原始值持久化，保证新增枚举值不影响旧数据解码。
enum MessageRole: String, Codable, CaseIterable {
    case user
    case assistant
    case tool
}
