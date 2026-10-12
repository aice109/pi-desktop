//
//  ContentView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import SwiftData

/// 根视图。
///
/// 目前是 Xcode 模板生成的「列表 + 详情」骨架，用于验证 SwiftData 读写链路。
/// 正式开发时替换为 pi agent 主界面（会话列表 + 聊天详情 + 工具调用可视化），
/// 布局与数据流见 docs/architecture.md、docs/pi-agent.md。
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    /// 由 SwiftData 驱动：数据变更后 `items` 自动刷新，无需手动维护列表状态。
    @Query private var items: [Item]

    var body: some View {
        // 双栏结构（侧栏 + 详情），符合 macOS 的导航习惯，
        // 也是后续「会话列表 + 聊天区」的雏形。
        NavigationSplitView {
            List {
                ForEach(items) { item in
                    NavigationLink {
                        Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                    } label: {
                        Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .toolbar {
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select an item")
        }
    }

    private func addItem() {
        // 用动画包裹，让列表变化更自然；SwiftData 会在插入后自动持久化。
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        // 删除同样包在动画里；`offsets` 来自 List 的滑动删除手势。
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    // 预览用内存容器，避免写入真实数据库。
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
