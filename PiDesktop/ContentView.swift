//
//  ContentView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// 根视图。
///
/// 流程：先选择工作区目录 → 列出该目录下的 pi 会话 → 选中后进入 `ChatView`。
/// 会话列表直接来自 pi 的会话文件（`Core/Pi`），选中时镜像为本地 `Session` 以便流式续聊。
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(WorkspaceStore.self) private var workspaceStore

    /// 侧栏选中项：pi 会话文件路径。
    @State private var selection: URL?
    /// 当前打开的领域会话。
    @State private var opened: Session?
    @State private var isPickingFolder = false

    var body: some View {
        if workspaceStore.workspace == nil {
            WorkspaceGateView()
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                if let opened {
                    ChatView(session: opened)
                } else {
                    ContentUnavailableView(
                        "No Session Selected",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Pick a session on the left, or create a new one.")
                    )
                }
            }
            .fileImporter(
                isPresented: $isPickingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: handleWorkspacePick
            )
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            workspaceBar
            Divider()
            sessionList
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: startNewSession) {
                    Label("New Session", systemImage: "plus")
                }
                .help("New Session")
            }
        }
    }

    /// 顶部工作区信息条：目录名 + 切换按钮。
    private var workspaceBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(workspaceStore.workspace?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(workspaceStore.workspace?.path ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button {
                isPickingFolder = true
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Change Folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var sessionList: some View {
        List(selection: $selection) {
            if workspaceStore.sessions.isEmpty {
                HStack(spacing: 6) {
                    if workspaceStore.isLoading {
                        ProgressView().controlSize(.small)
                    }
                    Text(workspaceStore.isLoading ? "Loading…" : "No pi sessions in this folder yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(workspaceStore.sessions) { summary in
                    PiSessionRow(summary: summary)
                        .tag(summary.fileURL)
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue,
                  let summary = workspaceStore.sessions.first(where: { $0.fileURL == newValue })
            else { return }
            opened = openSession(for: summary)
        }
    }

    // MARK: - Actions

    /// 在当前工作区新建会话；首次发送后 pi 会为其落盘并出现在列表中。
    private func startNewSession() {
        let session = Session(title: "", workingDirectory: workspaceStore.workspace?.path)
        modelContext.insert(session)
        selection = nil
        opened = session
    }

    /// 打开 pi 会话：优先复用本地已镜像的 `Session`，否则新建并把历史消息导入。
    private func openSession(for summary: PiSessionSummary) -> Session {
        let path = summary.fileURL.path
        let existing = (try? modelContext.fetch(FetchDescriptor<Session>()))?
            .first { $0.piSessionPath == path }
        if let existing { return existing }

        let workingDirectory = summary.cwd.isEmpty ? workspaceStore.workspace?.path : summary.cwd
        let session = Session(title: summary.displayTitle, workingDirectory: workingDirectory, piSessionPath: path)
        modelContext.insert(session)
        for message in PiSessionFiles.messages(in: summary.fileURL) {
            session.append(Message(role: message.role, content: message.text, createdAt: message.timestamp))
        }
        return session
    }

    private func handleWorkspacePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            // 切换目录后清空当前选择，避免指向旧工作区的会话。
            selection = nil
            opened = nil
            workspaceStore.setWorkspace(url)
        case .failure(let error):
            workspaceStore.report(error)
        }
    }
}

/// 侧栏会话行：标题 + 最近活动时间 + 消息数。
private struct PiSessionRow: View {
    let summary: PiSessionSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.displayTitle)
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(summary.updatedAt, format: .relative(presentation: .named))
                if summary.messageCount > 0 {
                    Text("·")
                    Text("\(summary.messageCount) msgs")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    // 预览专用内存容器；创建失败即视为开发环境异常。
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Session.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    } catch {
        fatalError("Failed to create preview container: \(error)")
    }

    let workspaceStore = WorkspaceStore(
        defaults: UserDefaults(suiteName: "ContentViewPreview") ?? .standard,
        root: URL(fileURLWithPath: "/tmp/pi-sessions-preview")
    )
    let sessionStore = SessionStore(container: container, makeTransport: { _, _ in MockAgentTransport() })
    return ContentView()
        .environment(workspaceStore)
        .environment(sessionStore)
        .modelContainer(container)
}
