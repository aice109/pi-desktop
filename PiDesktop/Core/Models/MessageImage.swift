//
//  MessageImage.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// 用户消息附带的一张图片（ADR-0010）。
///
/// 字节存于外部存储，避免把 base64 截图塞进 SQLite 主库；一条消息可含多张图片，
/// 顺序即插入顺序。
@Model
final class MessageImage {
    @Attribute(.unique) var id: UUID
    /// 媒体类型（如 `image/png`）；发送时按 pi 的 `ImageContent.mimeType` 原样回传。
    var mimeType: String
    /// 原始图片字节（已在解码时从 base64 还原）。
    @Attribute(.externalStorage) var data: Data
    var createdAt: Date
    /// 反向关系；`Message.images` 持有数组并负责级联删除。
    var message: Message?

    init(mimeType: String, data: Data, createdAt: Date = .now) {
        self.id = UUID()
        self.mimeType = mimeType
        self.data = data
        self.createdAt = createdAt
    }
}
