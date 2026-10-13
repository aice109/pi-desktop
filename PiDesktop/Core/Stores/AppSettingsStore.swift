//
//  AppSettingsStore.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import Observation
import SwiftUI

/// 界面外观偏好。
nonisolated enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    /// 交给 SwiftUI 的配色方案；`nil` 表示跟随系统。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// 应用偏好（外观、启动行为、界面开关）。
///
/// 存放于 `UserDefaults`（macOS 惯例）：偏好是单条配置，没有关系与查询需求，
/// 不需要 SwiftData 的迁移机制（见 ADR-0008）。
@MainActor
@Observable
final class AppSettingsStore {
    /// `UserDefaults` 键。
    enum Keys {
        static let appearance = "settings.appearance"
        static let restoreLastSession = "settings.restoreLastSession"
        static let showUsageFooter = "settings.showUsageFooter"
        static let showAnchorPanel = "settings.showAnchorPanel"
        static let confirmDeletion = "settings.confirmDeletion"
        static let lastSessionPath = "settings.lastSessionPath"
    }

    private let defaults: UserDefaults

    /// 外观：跟随系统 / 浅色 / 深色。
    var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// 启动时是否自动重新打开上次的会话。
    var restoreLastSession: Bool {
        didSet { defaults.set(restoreLastSession, forKey: Keys.restoreLastSession) }
    }

    /// 是否在输入框下方显示上下文占用 / token / 费用。
    var showUsageFooter: Bool {
        didSet { defaults.set(showUsageFooter, forKey: Keys.showUsageFooter) }
    }

    /// 是否在窗口右侧显示对话锚点面板（快速定位到某个回合）。
    var showAnchorPanel: Bool {
        didSet { defaults.set(showAnchorPanel, forKey: Keys.showAnchorPanel) }
    }

    /// 删除会话（移入废纸篓）前是否二次确认。
    var confirmDeletion: Bool {
        didSet { defaults.set(confirmDeletion, forKey: Keys.confirmDeletion) }
    }

    /// 上次打开的 pi 会话文件路径，用于启动恢复；不写入 `UserDefaults` 以外的地方。
    var lastSessionPath: String? {
        didSet {
            if let lastSessionPath, !lastSessionPath.isEmpty {
                defaults.set(lastSessionPath, forKey: Keys.lastSessionPath)
            } else {
                defaults.removeObject(forKey: Keys.lastSessionPath)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = AppAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        // 默认开启：偏好“回到上次位置”更符合桌面应用直觉。
        restoreLastSession = defaults.object(forKey: Keys.restoreLastSession) as? Bool ?? true
        showUsageFooter = defaults.object(forKey: Keys.showUsageFooter) as? Bool ?? true
        // 默认关闭：右侧面板是可选导航，不占据默认阅读宽度。
        showAnchorPanel = defaults.object(forKey: Keys.showAnchorPanel) as? Bool ?? false
        confirmDeletion = defaults.object(forKey: Keys.confirmDeletion) as? Bool ?? true
        let path = defaults.string(forKey: Keys.lastSessionPath)
        lastSessionPath = (path?.isEmpty ?? true) ? nil : path
    }

    /// 启动时该恢复的会话：上次打开的会话仍在当前工作区时返回它，否则为 `nil`。
    ///
    /// 放在这里（而不是视图里）是为了可直接单测：恢复与否只取决于「偏好 + 会话列表」。
    func sessionToRestore(among sessions: [PiSessionSummary]) -> PiSessionSummary? {
        guard restoreLastSession, let path = lastSessionPath else { return nil }
        return sessions.first { $0.fileURL.path == path }
    }

    /// 清空所有偏好（仅测试使用）。
    func reset() {
        for key in [
            Keys.appearance, Keys.restoreLastSession, Keys.showUsageFooter,
            Keys.showAnchorPanel, Keys.confirmDeletion, Keys.lastSessionPath,
        ] {
            defaults.removeObject(forKey: key)
        }
        appearance = .system
        restoreLastSession = true
        showUsageFooter = true
        showAnchorPanel = false
        confirmDeletion = true
        lastSessionPath = nil
    }
}
