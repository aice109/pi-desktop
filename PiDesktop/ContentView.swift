//
//  ContentView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import SwiftData

/// 根视图：左侧会话列表 + 右侧会话详情。
///
/// 数据链路：`Session`/`Message`（SwiftData）↔ `SessionStore` ↔ `ChatView`。
/// 领域事件由 `Core/Agent` 提供，数据流见 docs/architecture.md。
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    /// 按最近活动倒序；SwiftData 在数据变更后自动刷新。
    @Query(sort: \Session.updatedAt, order: .reverse) private var sessions: [Session]

    var body: some View {
        // 双栏结构（侧栏 + 详情），符合 macOS 导航习惯。
        NavigationSplitView {
            List {
                ForEach(sessions) { session in
                    NavigationLink {
                        ChatView(session: session)
                    } label: {
                        SessionRow(session: session)
                    }
                }
                .onDelete(perform: deleteSessions)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                ToolbarItem {
                    Button(action: addSession) {
                        Label("New Session", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select a session")
                .foregroundStyle(.secondary)
        }
    }

    private func addSession() {
        withAnimation {
            modelContext.insert(Session(title: "New Session"))
        }
    }

    private func deleteSessions(offsets: IndexSet) {
        // 级联删除由 Session.messages 的 deleteRule 保证。
        withAnimation {
            for index in offsets {
                modelContext.delete(sessions[index])
            }
        }
    }
}

/// 会话列表行：标题 + 最近活动时间。
private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title.isEmpty ? "Untitled Session" : session.title)
            Text(session.updatedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Session.self, Message.self], inMemory: true)
}
