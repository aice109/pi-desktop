//
//  WorkspaceStore.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import Observation

/// 当前工作区（项目目录）及其 pi 会话列表的状态源。
///
/// 工作区选择会持久化到 `UserDefaults`，重启后自动恢复；未选择工作区时
/// UI 显示引导页（见 `WorkspaceGateView`）。
@MainActor
@Observable
final class WorkspaceStore {
    /// `UserDefaults` 键：所选目录的绝对路径。
    static let workspacePathKey = "workspacePath"
    /// `UserDefaults` 键：最近使用的目录列表。
    static let recentWorkspacesKey = "recentWorkspaces"
    private static let maxRecent = 6

    private let defaults: UserDefaults
    private let root: URL
    private var loadTask: Task<Void, Never>?

    /// 当前工作区目录；`nil` 表示尚未选择。
    private(set) var workspace: URL?
    /// 该工作区下的 pi 会话，按最近活动倒序。
    private(set) var sessions: [PiSessionSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// 最近使用的工作区（最新的在前）。
    private(set) var recentWorkspaces: [URL] = []

    init(defaults: UserDefaults = .standard, root: URL? = nil) {
        self.defaults = defaults
        self.root = root ?? PiSessionFiles.defaultRoot()
        recentWorkspaces = (defaults.stringArray(forKey: Self.recentWorkspacesKey) ?? [])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let path = defaults.string(forKey: Self.workspacePathKey), !path.isEmpty {
            workspace = URL(fileURLWithPath: path, isDirectory: true)
        }
        // 上次选择的目录仍在，启动即加载它的会话列表。
        if workspace != nil { refresh() }
    }

    /// 选择（或切换）工作区并刷新会话列表。
    func setWorkspace(_ url: URL) {
        let standardized = url.standardizedFileURL
        workspace = standardized
        defaults.set(standardized.path, forKey: Self.workspacePathKey)
        remember(standardized)
        refresh()
    }

    /// 清除选择，回到引导页。
    func clearWorkspace() {
        loadTask?.cancel()
        workspace = nil
        sessions = []
        isLoading = false
        errorMessage = nil
        defaults.removeObject(forKey: Self.workspacePathKey)
    }

    /// 记录一次选择目录失败，供 UI 提示。
    func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }

    /// 清除当前的错误提示（用户关闭 alert 后调用）。
    func dismissError() {
        errorMessage = nil
    }

    /// 把目录记入最近列表（去重、限长、最新在前）。
    private func remember(_ url: URL) {
        var paths = recentWorkspaces.map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > Self.maxRecent { paths = Array(paths.prefix(Self.maxRecent)) }
        recentWorkspaces = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        defaults.set(paths, forKey: Self.recentWorkspacesKey)
    }

    /// 重新扫描该工作区的会话目录（新会话落盘、切换目录后调用）。
    func refresh() {
        guard let workspace else {
            sessions = []
            return
        }
        let directory = PiSessionFiles.sessionsDirectory(forWorkingDirectory: workspace.path, root: root)
        loadTask?.cancel()
        isLoading = true
        loadTask = Task { [weak self] in
            // 文件解析放后台，避免长会话文件阻塞主线程。
            let loaded = await Task.detached(priority: .userInitiated) {
                PiSessionFiles.summaries(in: directory)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.sessions = loaded
            self.isLoading = false
        }
    }
}
