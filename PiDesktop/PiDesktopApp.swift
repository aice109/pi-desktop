//
//  PiDesktopApp.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData
import SwiftUI

/// 应用入口。
///
/// PiDesktop 是 pi coding agent 的 macOS 原生 GUI。当前已接入 pi（RPC 子进程，见 ADR-0003）：
/// 可在会话中发送消息并流式接收助手回复。
@main
struct PiDesktopApp: App {
    private let modelContainer: ModelContainer
    /// 仅 DEBUG 下用于把 Dock 图标换成带「测」标记的测试版图标（见 `AppDelegate`）。
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sessionStore: SessionStore
    @State private var workspaceStore: WorkspaceStore
    @State private var appSettings: AppSettingsStore

    init() {
        let container = Self.makeModelContainer()
        modelContainer = container
        let workspace = WorkspaceStore()
        let settings = AppSettingsStore()
        // 生产环境用真实 pi 子进程；会话由 pi 持久化到工作目录对应的会话目录。
        let sessions = SessionStore(
            container: container,
            makeTransport: { workingDirectory, sessionPath in
                PiRPCClient(workingDirectory: workingDirectory, sessionPath: sessionPath)
            }
        )
        // 新会话落盘后刷新侧栏列表，使其立即出现。
        sessions.onSessionPersisted = { workspace.refresh() }
        // 回合结束时（后台/他页）发系统通知；未读标记由 store 自行维护。
        let notifier = TurnNotifier()
        notifier.requestAuthorization()
        sessions.onTurnFinished = { [weak sessions] session, error in
            notifier.handle(
                session: session,
                error: error,
                visible: sessions?.visibleSessionID == session.id
            )
        }
        _workspaceStore = State(initialValue: workspace)
        _sessionStore = State(initialValue: sessions)
        _appSettings = State(initialValue: settings)
    }

    /// 应用展示名：Debug 为「Pi Desktop 测试版」，Release 为「Pi Desktop」。
    /// 未打开会话时用它作为窗口标题，避免窗口标题与 Finder / Dock 中的名字不一致。
    private static var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "PiDesktop"
    }

    var body: some Scene {
        // 单主窗口（ADR-0011）：Store 是应用级单例（transports 按 session.id 索引、visibleSessionID 为单值），
        // 多窗口会争抢同一会话并错乱未读/通知判断。
        Window(Self.appDisplayName, id: "main") {
            ContentView()
                .environment(sessionStore)
                .environment(workspaceStore)
                .environment(appSettings)
                .preferredColorScheme(appSettings.appearance.colorScheme)
        }
        .defaultSize(width: 1100, height: 720)
        .modelContainer(modelContainer)
        .commands { PiDesktopCommands() }

        // 偏好设置窗口（⌘,）。外观需同样应用，否则设置窗不会跟随。
        Settings {
            SettingsView()
                .environment(appSettings)
                .preferredColorScheme(appSettings.appearance.colorScheme)
        }
    }

    /// 应用菜单：文件 / 会话命令。
    ///
    /// 从聚焦窗口读取处理器（`FocusedValue`）；没有匹配窗口时菜单项自动禁用。
    private struct PiDesktopCommands: Commands {
        @FocusedValue(\.sessionCommands) private var commands

        var body: some Commands {
            CommandGroup(replacing: .newItem) {
                Button("New Session") { commands?.newSession() }
                    .keyboardShortcut("n", modifiers: .command)
                    .disabled(commands == nil)
                Button("Open Workspace…") { commands?.chooseWorkspace() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(commands == nil)
                Divider()
                Button("Export as HTML…") { commands?.exportHTML() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(!(commands?.canExport() ?? false))
            }

            CommandMenu("Chat") {
                Button("Next Model") { commands?.cycleModel() }
                    .keyboardShortcut("m", modifiers: [.command, .control])
                    .disabled(!(commands?.canChat() ?? false))
                Button("Next Thinking Level") { commands?.cycleThinkingLevel() }
                    .keyboardShortcut("t", modifiers: [.command, .control])
                    .disabled(!(commands?.canChat() ?? false))
                Divider()
                Button("Copy Last Response") { commands?.copyLastResponse() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .disabled(!(commands?.canChat() ?? false))
                Button("Retry Last Message") { commands?.retryLast() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(!(commands?.canRetryLast() ?? false))
            }

            CommandMenu("Session") {
                Button("Refresh Sessions") { commands?.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(commands == nil)
                Button("Stop") { commands?.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!(commands?.isStreaming() ?? false))
                Divider()
                Button("Close Workspace") { commands?.closeWorkspace() }
                    .disabled(commands == nil)
            }
        }
    }

    /// 创建全局 SwiftData 容器。
    ///
    /// 容器是应用的硬依赖，创建失败意味着 schema 或存储配置有误；带着半残状态启动
    /// 只会制造更难排查的问题，因此启动时明确崩溃（`coding-conventions.md` §7）。
    private static func makeModelContainer() -> ModelContainer {
        // 领域模型见 ADR-0004 / ADR-0006；偏好存于 `UserDefaults`（ADR-0008），不入 schema。
        let schema = Schema([Session.self, Message.self, ToolCall.self, MessageImage.self])
        let configuration = ModelConfiguration(schema: schema, url: modelStoreURL())
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// SwiftData 存储路径（测试 / 生产隔离，见 ADR-0012）。
    ///
    /// 应用未开启 App Sandbox，SwiftData 默认的 `default.store` 位于共享的
    /// `~/Library/Application Support/`，**不会随 bundle id 隔离**：Debug 与 Release
    /// 都用默认值时，从 Xcode 运行会直接改写已安装版本的数据。
    /// 因此两种配置各用专属目录：
    /// - Release：`Application Support/PiDesktop/default.store`
    /// - Debug：  `Application Support/PiDesktop-Dev/default.store`
    ///
    /// 本地镜像可由 pi 会话文件重建（ADR-0009），切换目录不会丢失 pi 的源数据。
    private static func modelStoreURL() -> URL {
        #if DEBUG
            let directoryName = "PiDesktop-Dev"
        #else
            let directoryName = "PiDesktop"
        #endif
        let directory = URL.applicationSupportDirectory
            .appending(path: directoryName, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            fatalError("Could not create the model store directory: \(error)")
        }
        return directory.appending(path: "default.store")
    }
}
