//
//  ContentView.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import AppKit
import SwiftData
import SwiftUI
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
    /// 工作区切换浮层（点项目卡片弹出）的开关。
    @State private var isShowingWorkspaceMenu = false
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
        // 操作结果横幅（压缩 / 导出 / 分支 / 复制等）：悬浮在内容之上，不遮挡工具栏。
        .overlay(alignment: .top) {
            if let notice = sessionStore.notice {
                NoticeBanner(notice: notice) { sessionStore.dismissNotice() }
                    // 限定宽度并居中；否则 `Spacer` 会让横幅撑满整个窗口。
                    .frame(maxWidth: 460)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: sessionStore.notice?.id)
        // 工作区错误（目录选择 / 删除失败）之前只写进 store，从不展示；这里统一弹出。
        .alert(
            "Something went wrong",
            isPresented: workspaceErrorBinding,
            presenting: workspaceStore.errorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        // 退出时释放 pi 子进程。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            sessionStore.shutdown()
        }
    }

    private var workspaceErrorBinding: Binding<Bool> {
        Binding(
            get: { workspaceStore.errorMessage != nil },
            set: { if !$0 { workspaceStore.dismissError() } }
        )
    }

    /// 暴露给 App 菜单的命令处理器（见 `Core/Commands/SessionCommands.swift`）。
    private var sessionCommands: SessionCommandHandlers {
        SessionCommandHandlers(
            newSession: { startNewSession() },
            chooseWorkspace: { isPickingFolder = true },
            refresh: { workspaceStore.refresh() },
            stop: { stopStreaming() },
            closeWorkspace: { closeWorkspace() },
            exportHTML: { exportOpenSession() },
            cycleModel: { cycleModel() },
            cycleThinkingLevel: { cycleThinkingLevel() },
            copyLastResponse: { copyLastResponse() },
            retryLast: { retryLast() },
            isStreaming: { opened.map { sessionStore.isStreaming($0) } ?? false },
            canExport: { opened != nil },
            canChat: { opened != nil },
            canRetryLast: {
                guard let opened else { return false }
                return !sessionStore.isStreaming(opened)
                    && opened.messages.contains { $0.role == .user }
            }
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
        // 硬性最小宽度：内容永不被裁切，同时让分隔条拖不到更窄。
        // 低于此宽度时 `NSSplitView` 会直接折叠侧栏（原生行为，见 `DesignTokens.Layout.sidebarWidth`）。
        .frame(minWidth: DesignTokens.Layout.sidebarWidth)
        // 再把原生侧栏项的 `minimumThickness` 钉到同一宽度：`.navigationSplitViewColumnWidth(min:)`
        // 并不总能写入它（系统默认仍是侧栏标准最小值），否则折叠前还会向内滑几个点。
        .background(SidebarSplitItemConfigurator(minimumWidth: DesignTokens.Layout.sidebarWidth))
        .navigationSplitViewColumnWidth(
            min: DesignTokens.Layout.sidebarWidth,
            ideal: DesignTokens.Layout.sidebarWidth
        )
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

    /// 顶部工作区卡片：文件夹徽标 + 项目名 + 缩写路径 + 展开指示。
    ///
    /// 整张卡片是一个按钮，点击弹出工作区切换浮层（最近项目 / 选择文件夹 / 关闭工作区）。
    /// 用卡片而不是普通菜单标签，是为了让「当前项目」在侧栏里足够醒目；右侧圆圈里的
    /// 上下 chevron 明确提示可点。路径统一走 `PathDisplay` 缩写家目录。
    private var workspaceBar: some View {
        Button {
            isShowingWorkspaceMenu.toggle()
        } label: {
            workspaceCard
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingWorkspaceMenu) {
            workspaceMenu
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    /// 卡片内容：徽标 + 文本 + 加载指示 + chevron。
    private var workspaceCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(
                    .tint.opacity(0.14),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(workspaceStore.workspace?.lastPathComponent ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(PathDisplay.abbreviated(workspaceStore.workspace))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if workspaceStore.isLoading {
                ProgressView().controlSize(.small)
            }
            // 明确的「可展开」提示：独立的圆形 chevron。
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(.quaternary.opacity(0.5), in: Circle())
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.control))
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous))
    }

    /// 工作区切换浮层：分组标题 + 最近项目列表 + 底部操作。
    ///
    /// 用自绘的行按钮（悬停高亮、当前项着色并打勾）而不是 `List`/`Menu`，
    /// 是因为系统列表在浮层里会带多余内边距与描边，与玻璃卡片不搭。
    private var workspaceMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !workspaceStore.recentWorkspaces.isEmpty {
                Text("Recent Projects")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 5)

                VStack(spacing: 1) {
                    ForEach(workspaceStore.recentWorkspaces, id: \.self) { url in
                        WorkspaceMenuButton(
                            title: url.lastPathComponent,
                            subtitle: PathDisplay.abbreviated(url.path),
                            systemImage: "folder.fill",
                            isCurrent: url.path == workspaceStore.workspace?.path
                        ) {
                            selectWorkspace(url)
                            isShowingWorkspaceMenu = false
                        }
                    }
                }
                .padding(.horizontal, 8)

                Divider()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
            } else {
                Spacer(minLength: 10)
            }

            VStack(spacing: 1) {
                WorkspaceMenuButton(
                    title: String(localized: "Choose Folder…"),
                    systemImage: "folder.badge.plus",
                    action: chooseWorkspaceFolder
                )
                WorkspaceMenuButton(
                    title: String(localized: "Close Workspace"),
                    systemImage: "xmark.circle",
                    role: .destructive,
                    action: closeWorkspaceFromMenu
                )
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .frame(width: 292)
    }

    /// 从浮层里选择文件夹：先收起浮层，待其关闭后再弹系统文件选择器，避免同层争用。
    private func chooseWorkspaceFolder() {
        isShowingWorkspaceMenu = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            isPickingFolder = true
        }
    }

    private func closeWorkspaceFromMenu() {
        isShowingWorkspaceMenu = false
        closeWorkspace()
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
                        PiSessionRow(
                            summary: summary,
                            isUnread: sessionStore.isUnread(path: summary.fileURL.path)
                        )
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

    /// 循环到下一个模型（菜单⌃⌘M）。
    private func cycleModel() {
        guard let opened else { return }
        Task { await sessionStore.cycleModel(in: opened) }
    }

    /// 循环到下一个思考等级（菜单⌃⌘T）。
    private func cycleThinkingLevel() {
        guard let opened else { return }
        Task { await sessionStore.cycleThinkingLevel(in: opened) }
    }

    /// 复制最后一条助手回复（取 pi 的权威文本）。
    private func copyLastResponse() {
        guard let opened else { return }
        Task {
            guard let text = await sessionStore.lastAssistantText(in: opened), !text.isEmpty else {
                sessionStore.showNotice(.failure(String(localized: "No response to copy.")))
                return
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            sessionStore.showNotice(.success(String(localized: "Copied last response.")))
        }
    }

    /// 重发最后一条用户消息（手动重试；进程崩溃/出错后使用）。
    private func retryLast() {
        guard let opened else { return }
        Task { await sessionStore.retryLast(in: opened) }
    }

    /// 导出当前会话为 HTML：用系统保存面板选路径，交给 pi 的 `export_html` 写入。
    private func exportOpenSession() {
        guard let opened else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.canCreateDirectories = true
        let base = opened.title.isEmpty ? "session" : opened.title
        panel.nameFieldStringValue = "\(base).html"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { _ = await sessionStore.exportHTML(opened, to: url.path) }
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
        sessionStore.markRead(path: summary.fileURL.path)
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
        // 供后台回合判断是否需标未读/通知。
        sessionStore.visibleSessionID = session.id
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
            if opened == local {
                opened = nil
                sessionStore.visibleSessionID = nil
            }
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
        sessionStore.visibleSessionID = nil
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

/// 工作区浮层里的一行：图标 + 标题（+ 可选副标题），悬停高亮、可整行点击。
///
/// 当前项目常驻淡色底并显示勾选；关闭工作区用 destructive 角色渲染成红色。
private struct WorkspaceMenuButton: View {
    let title: String
    var subtitle: String?
    let systemImage: String
    var isCurrent = false
    var role: ButtonRole?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(iconStyle)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(isCurrent ? .semibold : .regular))
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        // 悬停反馈：`plain` 按钮默认没有底色，这里补一个语义化的浅底。
        .onHover { isHovering = $0 }
    }

    /// 图标：关闭操作走红色警示，当前项目用主题色，其余次级色。
    private var iconStyle: AnyShapeStyle {
        if role == .destructive { return AnyShapeStyle(.red) }
        return isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
    }

    private var titleStyle: AnyShapeStyle {
        role == .destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
    }

    /// 底色优先级：当前项目 > 悬停 > 透明。
    private var backgroundStyle: AnyShapeStyle {
        if isCurrent { return AnyShapeStyle(.tint.opacity(0.12)) }
        return isHovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)
    }
}

/// 把侧栏内容所在的原生 `NSSplitViewItem` 的 `minimumThickness` 对齐到固定宽度。
///
/// `NavigationSplitView` 由 AppKit 的 `NSSplitViewController` 撑起，侧栏项默认的
/// `minimumThickness` 是系统侧栏最小值（约 140）。仅靠 `.frame(minWidth:)` 约束内容时，
/// 分隔条在折叠前仍能向内滑动一两个点，视觉上就是「侧栏先缩短一点点再收起」。
/// 这里从侧栏内容向上找到该 split view，直接把 `minimumThickness` 设为固定宽度，
/// 让侧栏在折叠前保持精确宽度。找不到时安静跳过，不影响原有布局。
private struct SidebarSplitItemConfigurator: NSViewRepresentable {
    let minimumWidth: CGFloat

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        // 布局阶段视图尚未挂到窗口；放到下一轮 runloop 再配置。
        DispatchQueue.main.async { configure(from: view) }
    }

    private func configure(from view: NSView) {
        var current: NSView? = view.superview
        while let candidate = current {
            if let split = candidate as? NSSplitView,
                let controller = split.delegate as? NSSplitViewController,
                let sidebar = controller.splitViewItems.first
            {
                if sidebar.minimumThickness != minimumWidth {
                    sidebar.minimumThickness = minimumWidth
                }
                if !sidebar.canCollapse {
                    sidebar.canCollapse = true
                }
                return
            }
            current = candidate.superview
        }
    }
}

/// 侧栏会话行：图标 + 标题 + 最近活动时间与消息数；未读时右侧显示小圆点。
private struct PiSessionRow: View {
    let summary: PiSessionSummary
    let isUnread: Bool

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
            if isUnread {
                Circle()
                    .fill(.tint)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("Unread")
            }
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

/// 顶部操作反馈横幅：图标 + 文案 + 关闭按钮，悬浮在内容之上。
///
/// 用系统玻璃材质（`.glassEffect`）而非自绘底色，与工具栏 / 状态胶囊保持一致。
private struct NoticeBanner: View {
    let notice: OperationNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(
                systemName: notice.kind == .success
                    ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(notice.kind == .success ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
            Text(notice.message)
                .font(.callout)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .rect(cornerRadius: DesignTokens.Radius.card))
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
