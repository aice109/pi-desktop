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
    @Environment(AppSettingsStore.self) private var appSettings

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
        Group {
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
                .onChange(of: workspaceStore.sessions) { _, sessions in
                    restoreLastSessionIfNeeded(in: sessions)
                }
                .onAppear {
                    restoreLastSessionIfNeeded(in: workspaceStore.sessions)
                }
                .sheet(item: $renaming) { summary in
                    RenameSessionSheet(initialName: summary.name ?? summary.displayTitle) { newName in
                        rename(summary, to: newName)
                    }
                }
            }
        }
        .focusedSceneValue(\.sessionCommands, sessionCommands)
        // 退出时释放 pi 子进程。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            sessionStore.shutdown()
        }
    }

    /// 暴露给 App 菜单的命令处理器（见 `Core/Commands/SessionCommands.swift`）。
    private var sessionCommands: SessionCommandHandlers {
        SessionCommandHandlers(
            newSession: { startNewSession() },
            chooseWorkspace: { isPickingFolder = true },
            refresh: { workspaceStore.refresh() },
            stop: { stopStreaming() },
            closeWorkspace: { closeWorkspace() },
            isStreaming: { opened.map { sessionStore.isStreaming($0) } ?? false }
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let opened {
            ChatView(session: opened)
                .id(opened.id)
                .transition(.opacity)
        } else {
            ContentUnavailableView {
                Label("No Session Selected", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text("Pick a session on the left, or start a new one.")
            } actions: {
                Button("New Session", action: startNewSession)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            workspaceBar
            sessionList
        }
        .navigationSplitViewColumnWidth(min: 240, ideal: 280)
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search sessions")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { workspaceStore.refresh() }) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh Sessions (⌘R)")

                Button(action: startNewSession) {
                    Label("New Session", systemImage: "plus")
                }
                .help("New Session (⌘N)")
            }
        }
    }

    /// 顶部工作区信息条：文件夹徽标 + 目录名/路径 + 工作区菜单。
    private var workspaceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card))
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
            Spacer(minLength: 6)
            if workspaceStore.isLoading {
                ProgressView().controlSize(.small)
            }
            Menu {
                Button("Choose Folder…") { isPickingFolder = true }
                if !workspaceStore.recentWorkspaces.isEmpty {
                    Divider()
                    ForEach(workspaceStore.recentWorkspaces, id: \.self) { url in
                        Button(url.path) { selectWorkspace(url) }
                    }
                }
                Divider()
                Button("Close Workspace") { closeWorkspace() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Workspace")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var sessionList: some View {
        List(selection: $selection) {
            Section {
                if filteredSessions.isEmpty {
                    Text(emptyListMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                } else {
                    ForEach(filteredSessions) { summary in
                        PiSessionRow(summary: summary)
                            .tag(summary.fileURL)
                            .contextMenu {
                                Button("Rename…") { renaming = summary }
                                Divider()
                                Button("Move to Trash", role: .destructive) { requestDelete(summary) }
                            }
                    }
                }
            } header: {
                HStack(spacing: 6) {
                    Text(searchText.isEmpty ? "Sessions" : "Results")
                    Spacer(minLength: 0)
                    if !filteredSessions.isEmpty {
                        Text("\(filteredSessions.count)")
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption.weight(.semibold))
                .textCase(nil)
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue,
                  let summary = workspaceStore.sessions.first(where: { $0.fileURL == newValue })
            else { return }
            open(summary)
        }
        .listStyle(.sidebar)
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

    /// 中断当前会话的运行（菜单「Stop」与工具栏共用）。
    private func stopStreaming() {
        guard let opened else { return }
        Task { await sessionStore.interrupt(opened) }
    }

    /// 打开 pi 会话。
    private func open(_ summary: PiSessionSummary) {
        // 记住位置，供启动恢复（ADR-0008）。
        appSettings.lastSessionPath = summary.fileURL.path
        activate(openSession(for: summary))
    }

    /// 启动（或切换工作区）后恢复上次打开的会话；找不到则忽略。
    private func restoreLastSessionIfNeeded(in sessions: [PiSessionSummary]) {
        guard selection == nil, opened == nil,
              let summary = appSettings.sessionToRestore(among: sessions)
        else { return }
        selection = summary.fileURL
        open(summary)
    }

    /// 删除请求：按偏好决定是否二次确认。
    private func requestDelete(_ summary: PiSessionSummary) {
        if appSettings.confirmDeletion {
            pendingDeletion = summary
        } else {
            delete(summary)
        }
    }

    /// 切换当前会话，并释放上一个以释放闲置的 pi 进程。
    private func activate(_ session: Session) {
        if let previous = opened, previous.id != session.id {
            sessionStore.deactivate(previous)
        }
        // 交叉淡入旧/新会话，掩盖历史加载与进程启动的短暂空白。
        withAnimation(.easeInOut(duration: 0.18)) {
            opened = session
        }
    }

    /// 打开 pi 会话：优先复用本地已镜像的 `Session`，否则新建一个镜像。
    ///
    /// 历史由 `SessionStore.syncHistory` 在激活时填充（先会话文件、再 pi 校准），
    /// 因此应用外续聊的内容也会同步过来。
    private func openSession(for summary: PiSessionSummary) -> Session {
        localSession(matchingPiPath: summary.fileURL.path) ?? mirror(for: summary)
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
            selectWorkspace(url)
        case .failure(let error):
            workspaceStore.report(error)
        }
    }

    /// 切换工作区：清空当前选择，避免指向旧工作区的会话。
    private func selectWorkspace(_ url: URL) {
        // 沙盒已关闭（ADR-0003），此处通常返回 false；保留调用以便将来开启沙盒时仍正确。
        _ = url.startAccessingSecurityScopedResource()
        if let opened { sessionStore.deactivate(opened) }
        selection = nil
        opened = nil
        searchText = ""
        workspaceStore.setWorkspace(url)
    }

    /// 关闭当前工作区，回到引导页。
    private func closeWorkspace() {
        if let opened { sessionStore.deactivate(opened) }
        selection = nil
        opened = nil
        searchText = ""
        workspaceStore.clearWorkspace()
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }
}

/// 侧栏会话行：图标 + 标题 + 最近活动时间与消息数。
private struct PiSessionRow: View {
    let summary: PiSessionSummary

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: isNamed ? "tag.fill" : "bubble.left.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isNamed ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.displayTitle)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    /// 副标题：相对时间，有消息时附带数量。
    private var subtitle: String {
        let time = summary.updatedAt.formatted(.relative(presentation: .named))
        guard summary.messageCount > 0 else { return time }
        return "\(time) · \(summary.messageCount) msgs"
    }

    /// 用户显式命名的会话用标签图标区分于默认按首条消息命名的会话。
    private var isNamed: Bool {
        !(summary.name?.isEmpty ?? true)
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
            Label("Rename Session", systemImage: "pencil")
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
            for: Session.self, Message.self, ToolCall.self, MessageImage.self,
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
        .environment(AppSettingsStore(defaults: UserDefaults(suiteName: "ContentViewPreview") ?? .standard))
        .modelContainer(container)
}
