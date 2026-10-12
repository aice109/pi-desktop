//
//  TurnNotifier.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import AppKit
import UserNotifications

/// 回合结束时发送系统通知。
///
/// 只在应用不在前台、或该会话并非当前可见会话时提示，避免打断正盯着结果的人；
/// 未获授权时静默降级，不影响任何功能。授权在启动时请求一次。
@MainActor
final class TurnNotifier {
    private let center: UNUserNotificationCenter
    /// 注入以便测试/预览：应用是否在前台。
    private let isActive: () -> Bool
    private var authorized = false

    init(
        center: UNUserNotificationCenter = .current(),
        isActive: @escaping () -> Bool = { NSApp?.isActive ?? false }
    ) {
        self.center = center
        self.isActive = isActive
    }

    /// 请求通知授权（首次会弹系统弹窗）；失败只是关闭通知。
    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            Task { @MainActor in self?.authorized = granted }
        }
    }

    /// 由 `SessionStore.onTurnFinished` 触发；自行判断是否需要提示。
    func handle(session: Session, error: String?, visible: Bool) {
        // 用户正看着该会话且应用在前台：无需提示。
        guard !visible || !isActive() else { return }
        let title = session.title.isEmpty ? "Pi" : session.title
        let body = error.map { "Failed: \($0)" } ?? "Response ready."
        Task { await post(title: title, body: body, sessionPath: session.piSessionPath) }
    }

    private func post(title: String, body: String, sessionPath: String?) async {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let sessionPath { content.userInfo["sessionPath"] = sessionPath }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await center.add(request)
    }
}
