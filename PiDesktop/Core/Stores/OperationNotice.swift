//
//  OperationNotice.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 一次用户触发操作的结果反馈，用于根视图的顶部横幅。
///
/// 每次调用都是新值（自带 `id`），因此即使文案相同也能重新触发出现动画与自动消失计时。
nonisolated struct OperationNotice: Sendable, Equatable, Identifiable {
    /// 反馈类型：成功可自动消失，失败保留到用户关闭。
    nonisolated enum Kind: Sendable, Equatable {
        case success
        case failure
    }

    let id: UUID
    let kind: Kind
    let message: String

    private init(kind: Kind, message: String) {
        self.id = UUID()
        self.kind = kind
        self.message = message
    }

    static func success(_ message: String) -> OperationNotice {
        OperationNotice(kind: .success, message: message)
    }

    static func failure(_ message: String) -> OperationNotice {
        OperationNotice(kind: .failure, message: message)
    }
}
