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
    @Environment(SessionStore.self) private var sessionStore

    /// 侧栏选中项：pi 会话文件路径。
    @State private var selection: URL?
    /// 当前打开的领域会话。
    @State private var opened: Session?
    @State private var isPickingFolder = false
    @State private var searchText = ""
    /// 待确认删除的会话（移到废纸篓）。
    @State private var pendingDeletion: PiSessionSummary?
    /// 待重命名的会话。
    @State private var renaming: PiSessionSummary?

    var body: some View {
        if workspaceStore.workspace == nil {
            WorkspaceGateView()
        } else {
            NavigationSplitView {
                sidebar
            } detail: {
                detail
            }
            .fileImporter(
                isPresented: $isPickingFolder,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false,
                onCompletion: handleWorkspacePick
            )
            .confirmationDialog(
                "Move this session to the Trash?",
                isPresented: deletionDialogBinding,
                presenting: pendingDeletion
            ) { summary in
                Button("Move to Trash", role: .destructive) { delete(summary) }
                Button("Cancel", role: .cancel) {}
            } message: { summary in
                Text(summary.displayTitle)
            }
            .sheet(item: $renaming) { summary in
                RenameSessionSheet(initialName: summary.name ?? summary.displayTitle) { newName in
                    rename(summary, to: newName)
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let opened {
            ChatView(session: opened).id(opened.id)
        } else {
            ContentUnavailableView(
                "No Session Selected",
                systemImage: "bubble.left.and.bubble.right",
                description: Text("Pick a session on the left, or create a new one.")
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
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search sessions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { workspaceStore.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .help("Refresh Sessions")

                Button(action: startNewSession) {
                    Label("New Session", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
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
            if filteredSessions.isEmpty {
                Text(emptyListMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredSessions) { summary in
                    PiSessionRow(summary: summary)
                        .tag(summary.fileURL)
                        .contextMenu {
                            Button("Rename…") { renaming = summary }
                            Divider()
                            Button("Move to Trash", role: .destructive) { pendingDeletion = summary }
                        }
                }
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue,
                  let summary = workspaceStore.sessions.first(where: { $0.fileURL == newValue })
            else { return }
            open(summary)
        }
    }

    private var emptyListMessage: String {
        if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return "No matching sessions."
        }
        return workspaceStore.isLoading ? "Loading…" : "No pi sessions in this folder yet."
    }

    /// 侧栏展示项：按搜索词过滤标题与预览。
    private var filteredSessions: [PiSessionSummary] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return workspaceStore.sessions }
        return workspaceStore.sessions.filter { summary in
            summary.displayTitle.localizedCaseInsensitiveContains(query)
                || (summary.preview?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Actions

    /// 在当前工作区新建会话；首次发送后 pi 会为其落盘并出现在列表中。
    private func startNewSession() {
        let session = Session(title: "", workingDirectory: workspaceStore.workspace?.path)
        modelContext.insert(session)
        activate(session)
        selection = nil
    }

    /// 打开已有 pi 会话。
    private func open(_ summary: PiSessionSummary) {
        activate(openSession(for: summary))
    }

    /// 切换当前会话，并释放上一个以释放闲置的 pi 进程。
    private func activate(_ session: Session) {
        if let previous = opened, previous.id != session.id {
            sessionStore.deactivate(previous)
        }
        opened = session
    }

    /// 打开 pi 会话：优先复用本地已镜像的 `Session`，否则新建并把历史导入。
    private func openSession(for summary: PiSessionSummary) -> Session {
        if let existing = localSession(matchingPiPath: summary.fileURL.path) { return existing }

        let session = mirror(for: summary)
        for message in PiSessionFiles.messages(in: summary.fileURL) {
            session.append(Message(
                role: message.role,
                content: message.text,
                thinking: message.thinking,
                createdAt: message.timestamp
            ))
        }
        for toolCall in PiSessionFiles.toolCalls(in: summary.fileURL) {
            session.record(ToolCall(
                toolCallID: toolCall.toolCallID,
                name: toolCall.name,
                arguments: toolCall.arguments,
                output: toolCall.output,
                isError: toolCall.isError,
                createdAt: toolCall.timestamp
            ))
        }
        return session
    }

    /// 建立一个指向 pi 会话文件的本地镜像（不导入历史）。
    private func mirror(for summary: PiSessionSummary) -> Session {
        let workingDirectory = summary.cwd.isEmpty ? workspaceStore.workspace?.path : summary.cwd
        let session = Session(
            title: summary.displayTitle,
            workingDirectory: workingDirectory,
            piSessionPath: summary.fileURL.path
        )
        modelContext.insert(session)
        return session
    }

    /// 重命名会话：经 pi 写入会话文件，并同步本地镜像标题。
    private func rename(_ summary: PiSessionSummary, to name: String) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let session = localSession(matchingPiPath: summary.fileURL.path) ?? mirror(for: summary)
        Task { await sessionStore.rename(session, to: name) }
    }

    /// 把会话文件移到废纸篓（可恢复），并清理本地镜像。
    private func delete(_ summary: PiSessionSummary) {
        do {
            try FileManager.default.trashItem(at: summary.fileURL, resultingItemURL: nil)
        } catch {
            workspaceStore.report(error)
            return
        }
        if let local = localSession(matchingPiPath: summary.fileURL.path) {
            if opened == local { opened = nil }
            modelContext.delete(local)
        }
        if selection == summary.fileURL { selection = nil }
        workspaceStore.refresh()
    }

    private func localSession(matchingPiPath path: String) -> Session? {
        (try? modelContext.fetch(FetchDescriptor<Session>()))?.first { $0.piSessionPath == path }
    }

    private func handleWorkspacePick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            // 切换目录后清空当前选择，避免指向旧工作区的会话。
            selection = nil
            opened = nil
            searchText = ""
            workspaceStore.setWorkspace(url)
        case .failure(let error):
            workspaceStore.report(error)
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
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

/// 重命名会话的弹窗。
private struct RenameSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onRename: (String) -> Void
    @State private var name: String

    init(initialName: String, onRename: @escaping (String) -> Void) {
        self.onRename = onRename
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename Session")
                .font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                .onSubmit(submit)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(20)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmedName.isEmpty else { return }
        onRename(trimmedName)
        dismiss()
    }
}

#Preview {
    // 预览专用内存容器；创建失败即视为开发环境异常。
    let container: ModelContainer
    do {
        container = try ModelContainer(
            for: Session.self, Message.self, ToolCall.self,
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
