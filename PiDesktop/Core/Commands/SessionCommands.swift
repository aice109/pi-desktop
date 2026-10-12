//
//  SessionCommands.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI

/// 当前窗口提供的会话级命令，供 App 菜单调用。
///
/// 用聚焦值（`FocusedValue`）而非全局单例：命令只对**聚焦窗口**生效，
/// 这是 SwiftUI 的官方机制，也避免视图与 App 之间互相持有（见 `docs/design-system.md`）。
@MainActor
struct SessionCommandHandlers {
    var newSession: @MainActor () -> Void
    var chooseWorkspace: @MainActor () -> Void
    var refresh: @MainActor () -> Void
    var stop: @MainActor () -> Void
    var closeWorkspace: @MainActor () -> Void
    var exportHTML: @MainActor () -> Void
    var cycleModel: @MainActor () -> Void
    var cycleThinkingLevel: @MainActor () -> Void
    var copyLastResponse: @MainActor () -> Void
    var retryLast: @MainActor () -> Void
    var isStreaming: @MainActor () -> Bool
    var canExport: @MainActor () -> Bool
    var canChat: @MainActor () -> Bool
    var canRetryLast: @MainActor () -> Bool
}

private struct SessionCommandsKey: FocusedValueKey {
    typealias Value = SessionCommandHandlers
}

extension FocusedValues {
    /// 聚焦窗口的会话命令；无窗口提供时为 `nil`，菜单项随之禁用。
    var sessionCommands: SessionCommandHandlers? {
        get { self[SessionCommandsKey.self] }
        set { self[SessionCommandsKey.self] = newValue }
    }
}
