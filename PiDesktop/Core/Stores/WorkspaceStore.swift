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

    private let defaults: UserDefaults
    private let root: URL
    private var loadTask: Task<Void, Never>?

    /// 当前工作区目录；`nil` 表示尚未选择。
    private(set) var workspace: URL?
    /// 该工作区下的 pi 会话，按最近活动倒序。
    private(set) var sessions: [PiSessionSummary] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    init(defaults: UserDefaults = .standard, root: URL? = nil) {
        self.defaults = defaults
        self.root = root ?? PiSessionFiles.defaultRoot()
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
