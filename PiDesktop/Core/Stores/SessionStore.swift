//
//  SessionStore.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import SwiftData

/// 会话状态的唯一可变来源：把 `Core/Agent` 的领域事件落成 SwiftData 消息。
///
/// 遵循单向数据流（`docs/architecture.md`）：View 发意图、读状态；状态变更只发生在这里。
@MainActor
@Observable
final class SessionStore {
    /// 为会话创建传输实例。测试/预览注入 mock，生产注入 `PiRPCClient`。
    /// 参数为工作目录与会话文件路径（nil 表示新建会话）。
    /// 标注 `@MainActor`：工厂仅在主 actor 上调用，且 `PiRPCClient` 的初始化器受主 actor 隔离。
    typealias TransportFactory = @MainActor (_ workingDirectory: URL?, _ sessionPath: String?) -> any AgentTransport

    /// 新会话被 pi 落盘（获得会话文件路径）后回调，用于刷新工作区列表。
    var onSessionPersisted: (@MainActor () -> Void)?

    /// 持有容器（而非仅 `ModelContext`）：`ModelContext` 不持有其容器，
    /// 容器被释放后再使用 context 会崩溃，因此这里必须强引用。
    private let container: ModelContainer
    private let makeTransport: TransportFactory

    private var modelContext: ModelContext { container.mainContext }
    private var transports: [UUID: any AgentTransport] = [:]
    private var subscriptions: [UUID: Task<Void, Never>] = [:]
    private var streaming: [UUID: Streaming] = [:]
    /// 流式会话对应的领域对象，用于在落盘后发现 pi 会话路径。
    private var openSessions: [UUID: Session] = [:]
    /// 正在执行的工具（toolCallID → 工具名），支持并行工具调用。
    private var runningTools: [String: String] = [:]
    /// 流式期间的工具调用索引：sessionID → toolCallID → ToolCall。
    private var toolCalls: [UUID: [String: ToolCall]] = [:]
    /// 每个会话的运行时状态（模型 / 思考等级）。
    private var states: [UUID: AgentSessionState] = [:]
    /// 每个会话的用量与上下文占用。
    private var usage: [UUID: AgentUsage] = [:]
    /// 每个会话的进行中活动（重试 / 压缩 / 摘要）。
    private var activities: [UUID: AgentActivity] = [:]
    /// 每个会话待处理的 steering / follow-up 队列（`queue_update`）。
    private var queues: [UUID: AgentQueue] = [:]
    /// 每个会话的自动重试开关。pi 不在 `get_state` 里暴露该值，故本地跟踪（默认开启）。
    private var autoRetryEnabled: [UUID: Bool] = [:]
    /// 每个会话已应用的历史指纹，用于跳过无变化的重建。
    private var historyFingerprints: [UUID: PiHistoryFingerprint] = [:]
    /// 每个会话的增量同步游标（已见最后一条条目 id）。
    private var historyCursors: [UUID: String] = [:]
    /// 每个会话记录的活动分支叶子 id，用于发现分支切换。
    private var historyLeafs: [UUID: String?] = [:]
    /// 正在激活（加载历史 / 启动传输 / 读取状态）的会话，用于展示等待动画。
    private var activating: Set<UUID> = []

    /// 当前正在执行的工具名（转瞬状态，仅供 UI 展示）。
    var activeToolName: String? { runningTools.values.first }

    /// 流式助手消息的累积状态。
    private struct Streaming {
        var message: Message
        var text: String
        var thinking: String
    }

    init(container: ModelContainer, makeTransport: @escaping TransportFactory) {
        self.container = container
        self.makeTransport = makeTransport
    }

    /// 该会话是否正在流式接收。
    func isStreaming(_ session: Session) -> Bool {
        streaming[session.id] != nil
    }

    /// 该工具调用当前是否仍在执行。
    ///
    /// 以 `runningTools` 为准：历史导入的工具调用从未产生开始事件，因此不会出现在其中，
    /// 只能视为已完成——哪怕它没有 `durationMs`（pi 只在实时结束事件里给出耗时）。
    func isRunningTool(_ toolCallID: String) -> Bool {
        runningTools[toolCallID] != nil
    }

    /// 该会话是否正在激活（首次加载历史、启动 pi、读取模型 / 思考等级）。
    func isLoading(_ session: Session) -> Bool { activating.contains(session.id) }

    /// 该会话当前累积的思考内容（仅流式期间有值）。
    func reasoning(in session: Session) -> String? {
        guard let text = streaming[session.id]?.thinking, !text.isEmpty else { return nil }
        return text
    }

    /// 该会话的模型 / 思考等级状态。
    func state(for session: Session) -> AgentSessionState? { states[session.id] }

    /// 该会话的用量与上下文占用。
    func usage(for session: Session) -> AgentUsage? { usage[session.id] }

    /// 该会话正在进行的活动（重试 / 压缩 / 摘要），用于状态栏提示。
    func activity(for session: Session) -> AgentActivity? { activities[session.id] }

    /// 该会话待处理的 steering / follow-up 消息（对应 pi 的 `queue_update`）。
    func queued(for session: Session) -> AgentQueue { queues[session.id] ?? AgentQueue() }

    /// 打开会话：先用会话文件快速填充历史，再启动传输、加载状态，最后用 pi 校准。
    func activate(_ session: Session) async {
        // 先标记为加载中：`syncHistory` 内的 `Task.yield()` 会让 SwiftUI 有机会先渲染等待动画，
        // 再把同步重建的耗时挡在首帧之后。
        activating.insert(session.id)
        defer { activating.remove(session.id) }
        // 文件解析不依赖 pi 进程，可立即渲染历史，不必等子进程启动。
        await syncHistory(for: session)
        _ = await ensureTransport(for: session)
        await refreshState(for: session)
        // 再用 pi 的权威历史校准（例如应用外续聊、压缩后的变化）。
        await syncHistory(for: session)
    }

    /// 用 pi 的历史校准本地镜像（ADR-0009）。
    ///
    /// 已记录游标时走**增量**：只取 `get_entries(since:)` 之后的新条目并追加，避免长会话重复
    /// 拉取与重建；游标失效、活动分支切换或首次打开时退回全量。
    func syncHistory(for session: Session) async {
        guard !isStreaming(session) else { return }

        // 增量路径：需要游标（来自上一次 RPC 全量/增量同步）与活动传输。
        if let cursor = historyCursors[session.id], let transport = transports[session.id] {
            guard let page = await transport.sessionEntries(since: cursor) else {
                // 游标失效（会话被重置等）：丢掉游标，退回全量。
                historyCursors[session.id] = nil
                await fullSyncHistory(for: session)
                return
            }
            if page.entries.isEmpty {
                // 没有新条目；但活动分支可能被切换到别处（leaf 变化）→ 需要整体重建。
                if let leaf = page.leafId, leaf != historyLeafs[session.id] {
                    await fullSyncHistory(for: session)
                }
                historyLeafs[session.id] = page.leafId
                return
            }
            let snapshots = page.entries.map(\.historyEntry)
            // 归一化与历史构造放后台，避免阻塞主 actor。
            let history = await Task.detached(priority: .userInitiated) {
                PiHistory.make(from: snapshots)
            }.value
            // 重建前重新确认：等待期间可能已开始新一轮对话。
            guard !isStreaming(session) else { return }
            if let lastEntryID = page.entries.last?.id { historyCursors[session.id] = lastEntryID }
            historyLeafs[session.id] = page.leafId
            guard !history.isEmpty else { return }
            await appendHistory(history, to: session)
            // 增量追加后旧指纹不再代表完整历史；失效以免后续误判。
            historyFingerprints[session.id] = nil
            return
        }

        await fullSyncHistory(for: session)
    }

    /// 全量校准：拉取完整历史，仅在指纹变化时重建。
    private func fullSyncHistory(for session: Session) async {
        guard !isStreaming(session) else { return }
        let loaded = await loadHistory(for: session)
        // 记录游标供后续增量同步；文件来源没有条目 id，不会设置游标。
        if let lastEntryID = loaded.lastEntryID { historyCursors[session.id] = lastEntryID }
        historyLeafs[session.id] = loaded.leafID
        // 重建前重新确认：等待期间可能已开始新一轮对话，不能抹掉它。
        guard !loaded.history.isEmpty, !isStreaming(session) else { return }

        let fingerprint = PiHistoryFingerprint(loaded.history)
        guard historyFingerprints[session.id] != fingerprint else { return }
        await replaceHistory(of: session, with: loaded.history)
        historyFingerprints[session.id] = fingerprint
    }

    /// 一次全量历史读取的结果：历史 + 增量同步游标。
    private struct LoadedHistory {
        var history = PiHistory()
        /// 追加顺序中的最后一条条目 id；文件来源为 nil。
        var lastEntryID: String?
        /// 当前活动分支的叶子 id（`get_entries` 的 `leafId`）。
        var leafID: String?
    }

    /// 读取该会话的完整历史快照（优先 RPC，回退会话文件）。
    private func loadHistory(for session: Session) async -> LoadedHistory {
        if let transport = transports[session.id] {
            if let page = await transport.sessionEntries(since: nil), !page.entries.isEmpty {
                // 归一化与历史构造可能涉及上千条记录，放后台，避免阻塞主 actor。
                let snapshots = page.entries.map(\.historyEntry)
                let leafID = page.leafId
                let history = await Task.detached(priority: .userInitiated) {
                    // `get_entries` 是追加式树：按叶子回溯活动分支，避免混入被遗弃分支。
                    PiHistory.make(from: snapshots, leafID: leafID)
                }.value
                return LoadedHistory(
                    history: history,
                    lastEntryID: page.entries.last?.id,
                    leafID: page.leafId
                )
            }
        }
        guard let path = session.piSessionPath else { return LoadedHistory() }
        let url = URL(fileURLWithPath: path)
        // 文件解析放后台，避免长会话文件阻塞主线程。
        let history = await Task.detached(priority: .userInitiated) {
            PiSessionFiles.history(in: url)
        }.value
        return LoadedHistory(history: history)
    }

    /// 把增量历史追加到本地镜像（不删除已有对象，保留滚动位置与对象标识）。
    private func appendHistory(_ history: PiHistory, to session: Session) async {
        await Task.yield()
        var newMessages: [Message] = []
        for entry in history.messages {
            let message = Message(
                role: entry.role,
                content: entry.text,
                thinking: entry.thinking,
                createdAt: entry.timestamp
            )
            if !entry.images.isEmpty {
                let images = entry.images.map { MessageImage(mimeType: $0.mimeType, data: $0.data) }
                for image in images { modelContext.insert(image) }
                message.images = images
            }
            newMessages.append(message)
        }
        let newToolCalls = history.toolCalls.map { toolCall in
            ToolCall(
                toolCallID: toolCall.toolCallID,
                name: toolCall.name,
                arguments: toolCall.arguments,
                output: toolCall.output,
                isError: toolCall.isError,
                createdAt: toolCall.timestamp
            )
        }
        // 先注册再建立关系（与 `replaceHistory` 同一原因：避免 O(n²) 关系解析）。
        for message in newMessages { modelContext.insert(message) }
        for toolCall in newToolCalls { modelContext.insert(toolCall) }
        session.messages.append(contentsOf: newMessages)
        session.toolCalls.append(contentsOf: newToolCalls)
        let timestamps = history.messages.map(\.timestamp) + history.toolCalls.map(\.timestamp)
        if let latest = timestamps.max() { session.updatedAt = max(session.updatedAt, latest) }
    }

    /// 用历史替换本地镜像的消息与工具调用。
    ///
    /// 全部本地内容都来自 pi，因此整体替换是安全的；先摘除关系再删除，
    /// 避免数组里残留已删除对象。
    ///
    /// 性能关键：新建的对象必须先用 `modelContext.insert` 注册，再一次性赋值关系数组。
    /// 直接把未注册的对象塞进关系里，SwiftData 会在关系解析时逐个插入并触发 O(n²) 开销；
    /// 长会话（数千条）下会卡住主线程数十秒（曾有 6000 条耗时 32s，改为预注册后 ~0.1s）。
    private func replaceHistory(of session: Session, with history: PiHistory) async {
        // 主动让出主 actor：先让加载中的等待动画完成一次渲染，再执行同步的批量重建。
        await Task.yield()
        let messages = session.messages
        let toolCalls = session.toolCalls
        session.messages = []
        session.toolCalls = []
        for message in messages { modelContext.delete(message) }
        for toolCall in toolCalls { modelContext.delete(toolCall) }

        var newMessages: [Message] = []
        for entry in history.messages {
            let message = Message(
                role: entry.role,
                content: entry.text,
                thinking: entry.thinking,
                createdAt: entry.timestamp
            )
            if !entry.images.isEmpty {
                // 先注册图片对象，再建立关系，避免未注册对象触发 SwiftData 的 O(n²) 关系解析。
                let images = entry.images.map { MessageImage(mimeType: $0.mimeType, data: $0.data) }
                for image in images { modelContext.insert(image) }
                message.images = images
            }
            newMessages.append(message)
        }
        let newToolCalls = history.toolCalls.map { toolCall in
            ToolCall(
                toolCallID: toolCall.toolCallID,
                name: toolCall.name,
                arguments: toolCall.arguments,
                output: toolCall.output,
                isError: toolCall.isError,
                createdAt: toolCall.timestamp
            )
        }
        for message in newMessages { modelContext.insert(message) }
        for toolCall in newToolCalls { modelContext.insert(toolCall) }
        session.messages = newMessages
        session.toolCalls = newToolCalls
        // 批量赋值不会像 `append`/`record` 那样刷新 `updatedAt`，这里补上最近活动时间。
        let timestamps = history.messages.map(\.timestamp) + history.toolCalls.map(\.timestamp)
        if let latest = timestamps.max() { session.updatedAt = latest }
    }

    /// 关闭会话：非流式时释放其传输，避免闲置进程累积。
    func deactivate(_ session: Session) {
        guard !isStreaming(session), let transport = transports.removeValue(forKey: session.id) else { return }
        subscriptions.removeValue(forKey: session.id)?.cancel()
        openSessions.removeValue(forKey: session.id)
        states.removeValue(forKey: session.id)
        usage.removeValue(forKey: session.id)
        activities.removeValue(forKey: session.id)
        queues.removeValue(forKey: session.id)
        historyFingerprints.removeValue(forKey: session.id)
        Task { await transport.shutdown() }
    }

    /// 可选模型列表。
    func availableModels(for session: Session) async -> [AgentModel] {
        await transports[session.id]?.availableModels() ?? []
    }

    /// 可发现的命令（扩展 / prompt 模板 / 技能），用于斜杠命令面板。
    func availableCommands(for session: Session) async -> [AgentCommand] {
        await transports[session.id]?.availableCommands() ?? []
    }

    /// 可 fork 的用户消息（从某条消息处创建新分支）。
    func forkMessages(for session: Session) async -> [AgentForkMessage] {
        await transports[session.id]?.forkMessages() ?? []
    }

    /// 从指定用户消息创建分支（`fork`）。
    func fork(_ session: Session, from entryId: String) async {
        guard let transport = transports[session.id], await transport.fork(entryId: entryId) else { return }
        await resyncAfterBranchChange(session)
    }

    /// 把当前分支复制为新会话（`clone`）。
    func clone(_ session: Session) async {
        guard let transport = transports[session.id], await transport.clone() else { return }
        await resyncAfterBranchChange(session)
    }

    /// fork / clone 后 pi 会切到新的会话文件：重读状态、丢弃游标并全量重建，
    /// 让侧栏与新会话文件重新对应。
    private func resyncAfterBranchChange(_ session: Session) async {
        historyCursors[session.id] = nil
        historyFingerprints[session.id] = nil
        if let transport = transports[session.id], let state = await transport.sessionState() {
            states[session.id] = state
            if let path = state.sessionFile, !path.isEmpty { session.piSessionPath = path }
            if let name = state.sessionName, !name.isEmpty { session.title = name }
        }
        await fullSyncHistory(for: session)
        onSessionPersisted?()
    }

    /// 切换模型并刷新状态。
    func selectModel(_ model: AgentModel, in session: Session) async {
        guard let transport = transports[session.id], await transport.setModel(model) else { return }
        await refreshState(for: session)
    }

    /// 切换思考等级并刷新状态。
    func selectThinkingLevel(_ level: String, in session: Session) async {
        guard let transport = transports[session.id], await transport.setThinkingLevel(level) else { return }
        await refreshState(for: session)
    }

    /// 手动压缩上下文；可选自定义摘要指令。
    func compact(_ session: Session, instructions: String? = nil) async {
        guard let transport = transports[session.id] else { return }
        _ = await transport.compact(customInstructions: instructions)
        await refreshState(for: session)
    }

    /// 开关该会话的自动压缩。
    func setAutoCompaction(_ enabled: Bool, in session: Session) async {
        guard let transport = transports[session.id],
              await transport.setAutoCompaction(enabled: enabled)
        else { return }
        await refreshState(for: session)
    }

    /// 该会话是否开启自动重试（pi 默认开启）。
    func isAutoRetryEnabled(in session: Session) -> Bool { autoRetryEnabled[session.id] ?? true }

    /// 开关自动重试。
    func setAutoRetry(_ enabled: Bool, in session: Session) async {
        autoRetryEnabled[session.id] = enabled
        guard let transport = transports[session.id] else { return }
        _ = await transport.setAutoRetry(enabled: enabled)
    }

    /// 中止进行中的重试。
    func abortRetry(in session: Session) async {
        _ = await transports[session.id]?.abortRetry()
    }

    /// 导出会话为 HTML；返回 pi 写入的路径，失败为 nil。
    ///
    /// 若会话尚未激活（无传输），先拉起进程再导出，避免菜单项对未打开的会话失效。
    func exportHTML(_ session: Session, to path: String?) async -> String? {
        _ = await ensureTransport(for: session)
        return await transports[session.id]?.exportHTML(outputPath: path)
    }

    /// 重命名会话：经 pi 的 `set_session_name` 写入，并同步本地标题。
    func rename(_ session: Session, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // 若为仅重命名而临时启动进程，完成后释放。
        let wasActive = transports[session.id] != nil
        _ = await ensureTransport(for: session)
        guard let transport = transports[session.id], await transport.setSessionName(trimmed) else { return }
        session.title = trimmed
        if wasActive {
            await refreshState(for: session)
        } else {
            deactivate(session)
        }
        onSessionPersisted?()
    }

    /// 拉取并缓存该会话的状态与用量。
    private func refreshState(for session: Session) async {
        guard let transport = transports[session.id] else { return }
        if let state = await transport.sessionState() { states[session.id] = state }
        if let stats = await transport.sessionStats() { usage[session.id] = stats }
    }

    /// 发送一条用户消息并开始接收助手回复。
    func send(_ rawText: String, images: [AgentImage] = [], in session: Session) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        // 允许「仅图片」的消息：pi 同样接受空文本 + images。
        guard !text.isEmpty || !images.isEmpty, !isStreaming(session) else { return }

        let transport = await ensureTransport(for: session)

        session.append(makeUserMessage(text: text, images: images))
        // 先插入占位的助手消息，流式增量就地更新它。
        let assistant = Message(role: .assistant, content: "")
        session.append(assistant)
        streaming[session.id] = Streaming(message: assistant, text: "", thinking: "")

        do {
            let disposition = try await transport.prompt(text, images: images)
            // 扩展命令/输入处理器会立即消费 prompt（`handled`），不会启动运行、也不会有
            // `agent_settled`；必须主动收尾，否则占位助手气泡会一直转圈。
            if disposition == .handled {
                finish(sessionID: session.id)
            }
        } catch {
            finish(sessionID: session.id, error: error.localizedDescription)
        }
    }

    /// 流式期间排队一条 steering 消息：在当前回合的工具调用执行完后投递。
    func steer(_ rawText: String, images: [AgentImage] = [], in session: Session) async {
        await enqueue(rawText, images: images, in: session) { transport, text, images in
            try await transport.steer(text, images: images)
        }
    }

    /// 流式期间排队一条 follow-up 消息：仅在 agent 完全停下后投递。
    func followUp(_ rawText: String, images: [AgentImage] = [], in session: Session) async {
        await enqueue(rawText, images: images, in: session) { transport, text, images in
            try await transport.followUp(text, images: images)
        }
    }

    /// 排队消息的公共入口。
    ///
    /// 不在本地乐观写入用户消息：pi 的 `queue_update` 事件会回传权威队列，UI 据此渲染；
    /// 投递后的历史则由 `syncHistory` 统一校准，避免与 pi 的真实顺序不一致。
    private func enqueue(
        _ rawText: String,
        images: [AgentImage],
        in session: Session,
        using enqueue: (any AgentTransport, String, [AgentImage]) async throws -> PromptDisposition
    ) async {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !images.isEmpty,
              isStreaming(session),
              let transport = transports[session.id]
        else { return }
        do {
            _ = try await enqueue(transport, text, images)
        } catch {
            // 排队失败不终止当前运行：真正的连接问题会经由事件流触发 `.failed`。
        }
    }

    /// 构造带图片的用户消息；图片先注册进 context，再一次性建立关系。
    private func makeUserMessage(text: String, images: [AgentImage]) -> Message {
        let message = Message(role: .user, content: text)
        guard !images.isEmpty else { return message }
        let models = images.map { MessageImage(mimeType: $0.mimeType, data: $0.data) }
        for model in models { modelContext.insert(model) }
        message.images = models
        return message
    }

    /// 清空待处理队列，并返回被清空的文本（供输入框还原，pi 的 Esc 语义）。
    @discardableResult
    func clearQueue(in session: Session) async -> AgentQueue {
        guard let transport = transports[session.id] else { return AgentQueue() }
        let cleared = await transport.clearQueue()
        queues[session.id] = AgentQueue()
        return cleared
    }

    /// 中断该会话当前运行。
    func interrupt(_ session: Session) async {
        await transports[session.id]?.abort()
    }

    /// 关闭所有传输与订阅（App 退出时调用）。
    func shutdown() {
        for task in subscriptions.values { task.cancel() }
        subscriptions.removeAll()
        for transport in transports.values {
            Task { await transport.shutdown() }
        }
        transports.removeAll()
        subscriptions.removeAll()
        streaming.removeAll()
        openSessions.removeAll()
        runningTools.removeAll()
        toolCalls.removeAll()
        states.removeAll()
        usage.removeAll()
        activities.removeAll()
        queues.removeAll()
        autoRetryEnabled.removeAll()
        historyFingerprints.removeAll()
        historyCursors.removeAll()
        historyLeafs.removeAll()
        activating.removeAll()
    }

    // MARK: - Transport wiring

    private func ensureTransport(for session: Session) async -> any AgentTransport {
        if let existing = transports[session.id] { return existing }

        let workingDirectory = session.workingDirectory.map { URL(fileURLWithPath: $0) }
        let transport = makeTransport(workingDirectory, session.piSessionPath)
        transports[session.id] = transport
        openSessions[session.id] = session

        // 先建立订阅、再返回，确保 prompt 之前事件流已就绪。
        let stream = await transport.events()
        let sessionID = session.id
        subscriptions[sessionID] = Task { [weak self] in
            for await event in stream {
                self?.handle(event, sessionID: sessionID)
            }
        }
        return transport
    }

    // MARK: - Event handling

    private func handle(_ event: AgentEvent, sessionID: UUID) {
        switch event {
        case .agentStarted:
            break

        case .textDelta(let delta):
            guard var state = streaming[sessionID] else { return }
            state.text += delta
            state.message.content = state.text
            streaming[sessionID] = state

        case .thinkingDelta(let delta):
            guard var state = streaming[sessionID] else { return }
            state.thinking += delta
            streaming[sessionID] = state

        case .toolCallStarted(let id, let name, let arguments):
            runningTools[id] = name
            recordToolCallStart(id: id, name: name, arguments: arguments, sessionID: sessionID)

        case .toolCallUpdated(let id, let output):
            toolCalls[sessionID]?[id]?.output = output

        case .toolCallFinished(let id, let name, let isError, let durationMs, let output):
            runningTools.removeValue(forKey: id)
            // 未记录到开始事件（如中断后补发）时补建一条，避免丢失。
            if toolCalls[sessionID]?[id] == nil {
                recordToolCallStart(id: id, name: name, arguments: nil, sessionID: sessionID)
            }
            if let call = toolCalls[sessionID]?[id] {
                if let output, !output.isEmpty { call.output = output }
                call.isError = isError
                call.durationMs = durationMs
            }

        case .assistantMessageCompleted(let text, _, let errorMessage):
            guard var state = streaming[sessionID] else { return }
            if !text.isEmpty { state.text = text }
            if state.text.isEmpty, let errorMessage {
                state.message.content = errorMessage
            } else {
                state.message.content = state.text
            }
            // 把累积的思考一并持久化，便于事后回看（ADR-0007）。
            if !state.thinking.isEmpty { state.message.thinking = state.thinking }
            streaming[sessionID] = state

        case .retryStarted(let attempt, let maxAttempts):
            activities[sessionID] = .retrying(attempt: attempt, maxAttempts: maxAttempts)

        case .retryFinished:
            activities[sessionID] = nil

        case .compactionStarted:
            activities[sessionID] = .compacting

        case .compactionFinished:
            activities[sessionID] = nil

        case .queueUpdated(let queue):
            queues[sessionID] = queue

        case .sessionInfoChanged(let name):
            // 外部（pi 自动命名、扩展、TUI）改了会话名，同步到侧栏标题。
            if let name, !name.isEmpty { openSessions[sessionID]?.title = name }

        case .thinkingLevelChanged(let level):
            if var state = states[sessionID] {
                state.thinkingLevel = level
                states[sessionID] = state
            }

        case .summarizationRetryStarted:
            activities[sessionID] = .summarizing

        case .summarizationRetryFinished:
            activities[sessionID] = nil

        case .entryAppended:
            // 会话树被外部追加（扩展写入等）：空闲时重新校准本地镜像。
            if let session = openSessions[sessionID] {
                Task { await syncHistory(for: session) }
            }

        case .settled:
            finish(sessionID: sessionID)

        case .failed(let message):
            finish(sessionID: sessionID, error: message)
        }
    }

    /// 结束流式状态；若助手消息仍为空则移除占位，避免空气泡。
    private func finish(sessionID: UUID, error: String? = nil) {
        runningTools.removeAll()
        toolCalls.removeValue(forKey: sessionID)
        activities.removeValue(forKey: sessionID)
        // 这一轮结束意味着 pi 已把会话写入磁盘，可发现其文件路径。
        discoverSessionPath(for: sessionID)
        // 用量与上下文占用也会随回合更新。
        if let session = openSessions[sessionID] {
            Task { await refreshState(for: session) }
        }
        guard let state = streaming.removeValue(forKey: sessionID) else { return }

        if let error {
            if state.message.content.isEmpty {
                state.message.content = error
            } else {
                state.message.content += "\n\n\(error)"
            }
        } else if state.message.content.isEmpty, state.message.thinking?.isEmpty ?? true {
            // 仅当既无正文也无思考时才移除占位，避免空气泡。
            modelContext.delete(state.message)
        }
    }

    /// 记录一次工具调用的开始（写入 SwiftData 并建索引）。
    private func recordToolCallStart(id: String, name: String, arguments: String?, sessionID: UUID) {
        guard let session = openSessions[sessionID] else { return }
        let call = ToolCall(toolCallID: id, name: name, arguments: arguments)
        session.record(call)
        toolCalls[sessionID, default: [:]][id] = call
    }

    /// 新会话首轮结束后，从 pi 取回会话文件路径并回写领域对象。
    private func discoverSessionPath(for sessionID: UUID) {
        guard let session = openSessions[sessionID], session.piSessionPath == nil,
              let transport = transports[sessionID] else { return }
        Task {
            guard let state = await transport.sessionState() else { return }
            if let path = state.sessionFile, !path.isEmpty {
                session.piSessionPath = path
            }
            if session.title.isEmpty, let name = state.sessionName, !name.isEmpty {
                session.title = name
            }
            if session.piSessionPath != nil {
                onSessionPersisted?()
            }
        }
    }
}
