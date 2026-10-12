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
/// PiDesktop 是 pi coding agent 的 macOS 原生 GUI。当前仅为模板骨架：
/// App 入口 + SwiftData 容器 + 根视图，用于跑通构建与数据链路。
@main
struct PiDesktopApp: App {
    /// 全局 SwiftData 容器，持有应用的持久化 schema。
    ///
    /// 这里故意用 `fatalError`：容器是应用的硬依赖，创建失败意味着 schema 或
    /// 存储配置有误；带着半残状态启动只会制造更难排查的问题，不如在启动时明确崩。
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            // TODO: 替换为真实领域模型（Session / Message / ToolCall / AppSettings）。
            // 模型结构变更属于重大改动，需先记 ADR，见 docs/architecture.md。
            Item.self,
        ])
        // 磁盘持久化；预览/测试改用 `isStoredInMemoryOnly: true`（见 ContentView 的 #Preview），
        // 避免污染真实数据。
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // 向整个视图树下发容器，子视图通过 @Query / @Environment(\.modelContext) 存取。
        .modelContainer(sharedModelContainer)
    }
}
