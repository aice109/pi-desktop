//
//  PiDesktopApp.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import SwiftData

/// 应用入口。
///
/// PiDesktop 是 pi coding agent 的 macOS 原生 GUI。当前已接入 pi（RPC 子进程，见 ADR-0003）：
/// 可在会话中发送消息并流式接收助手回复。
@main
struct PiDesktopApp: App {
    private let modelContainer: ModelContainer
    @State private var sessionStore: SessionStore
    @State private var workspaceStore: WorkspaceStore

    init() {
        let container = Self.makeModelContainer()
        modelContainer = container
        let workspace = WorkspaceStore()
        // 生产环境用真实 pi 子进程；会话由 pi 持久化到工作目录对应的会话目录。
        let sessions = SessionStore(
            container: container,
            makeTransport: { workingDirectory, sessionPath in
                PiRPCClient(workingDirectory: workingDirectory, sessionPath: sessionPath)
            }
        )
        // 新会话落盘后刷新侧栏列表，使其立即出现。
        sessions.onSessionPersisted = { workspace.refresh() }
        _workspaceStore = State(initialValue: workspace)
        _sessionStore = State(initialValue: sessions)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionStore)
                .environment(workspaceStore)
        }
        .modelContainer(modelContainer)
    }

    /// 创建全局 SwiftData 容器。
    ///
    /// 容器是应用的硬依赖，创建失败意味着 schema 或存储配置有误；带着半残状态启动
    /// 只会制造更难排查的问题，因此启动时明确崩溃（`coding-conventions.md` §7）。
    private static func makeModelContainer() -> ModelContainer {
        // 领域模型见 ADR-0004 / ADR-0006；AppSettings 待后续 ADR 补充。
        let schema = Schema([Session.self, Message.self, ToolCall.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
