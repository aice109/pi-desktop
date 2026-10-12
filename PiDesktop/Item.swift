//
//  Item.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// Xcode 模板生成的示例模型，仅用于验证 SwiftData 链路，正式开发时删除。
///
/// 计划中的真实模型：`Session` / `Message` / `ToolCall` / `AppSettings`（见 docs/architecture.md）。
/// `@Model` 使类型具备 SwiftData 持久化能力，并自动提供变更观察。
@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
