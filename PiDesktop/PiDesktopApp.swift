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

    init() {
        let container = Self.makeModelContainer()
        modelContainer = container
        // 生产环境用真实 pi 子进程；会话/消息由本 App 持久化（`--no-session`）。
        _sessionStore = State(initialValue: SessionStore(
            container: container,
            makeTransport: { workingDirectory in
                PiRPCClient(workingDirectory: workingDirectory)
            }
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionStore)
        }
        .modelContainer(modelContainer)
    }

    /// 创建全局 SwiftData 容器。
    ///
    /// 容器是应用的硬依赖，创建失败意味着 schema 或存储配置有误；带着半残状态启动
    /// 只会制造更难排查的问题，因此启动时明确崩溃（`coding-conventions.md` §7）。
    private static func makeModelContainer() -> ModelContainer {
        // 领域模型见 ADR-0004；ToolCall / AppSettings 待后续 ADR 补充。
        let schema = Schema([Session.self, Message.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
}
