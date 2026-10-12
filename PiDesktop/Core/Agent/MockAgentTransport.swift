//
//  MockAgentTransport.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation
import Synchronization

/// 测试与预览用的传输实现：不启动进程，事件由调用方手动注入。
///
/// 放在 App target 以便 `#Preview` 与单元测试共用（避免各自维护一份）。
final class MockAgentTransport: AgentTransport, @unchecked Sendable {
    private let stream: AsyncStream<AgentEvent>
    private let continuation: AsyncStream<AgentEvent>.Continuation
    /// 用 `Mutex` 而非 `NSLock`：`NSLock` 在 async 上下文中不可用（Swift 6 起为错误）。
    private let sent = Mutex<[String]>([])
    /// `sessionState()` 的返回值，测试/预览可注入。
    private let state = Mutex<AgentSessionState?>(nil)
    /// `availableModels()` 的返回值。
    private let models = Mutex<[AgentModel]>([])
    /// `availableCommands()` 的返回值。
    private let commands = Mutex<[AgentCommand]>([])
    /// `forkMessages()` 的返回值。
    private let forks = Mutex<[AgentForkMessage]>([])
    /// 已 fork 的 entryId / 已 clone 次数，供断言。
    private let forkedEntryIDs = Mutex<[String]>([])
    private let cloneCount = Mutex<Int>(0)
    /// `fork` 返回的原始文本。
    private let forkText = Mutex<String?>(nil)
    /// `sessionTree()` 的返回值与调用次数。
    private let sessionTreeResult = Mutex<AgentSessionTree?>(nil)
    private let sessionTreeCount = Mutex<Int>(0)
    /// 已设置的自动压缩开关 / 压缩调用，供断言。
    private let autoCompaction = Mutex<Bool?>(nil)
    private let compactionInstructions = Mutex<[String?]>([])
    /// 已设置的自动重试开关 / 中止次数，供断言。
    private let autoRetry = Mutex<Bool?>(nil)
    private let abortRetryCount = Mutex<Int>(0)
    /// `exportHTML` 的入参与返回值。
    private let exportPaths = Mutex<[String?]>([])
    private let exportResult = Mutex<String?>(nil)
    /// 直接 shell 的调用记录 / 返回值 / 中止次数。
    private let bashCommands = Mutex<[String]>([])
    private let bashResult = Mutex<AgentBashResult?>(nil)
    private let abortBashCount = Mutex<Int>(0)
    /// `cycle_model` / `cycle_thinking_level` / `get_last_assistant_text` 的返回值与调用次数。
    private let cycleModelResult = Mutex<AgentModel?>(nil)
    private let cycleThinkingResult = Mutex<String?>(nil)
    private let lastAssistant = Mutex<String?>(nil)
    private let cycleModelCount = Mutex<Int>(0)
    private let cycleThinkingCount = Mutex<Int>(0)
    /// `sessionStats()` 的返回值。
    private let usage = Mutex<AgentUsage?>(nil)
    /// `sessionEntries(since:)` 的返回值（按 `since` 过滤前的全量）。
    private let entries = Mutex<[SessionEntryDTO]>([])
    /// 非空时直接作为 `sessionEntries(since:)` 的结果（可注入游标/叶子）。
    private let entriesPage = Mutex<SessionEntriesPage?>(nil)
    /// `prompt(_:)` 的返回值。
    private let disposition = Mutex<PromptDisposition>(.started)
    /// 已发送的 steering / follow-up 文本，供断言。
    private let steered = Mutex<[String]>([])
    private let followUps = Mutex<[String]>([])
    /// 每次 `prompt` 附带的图片批次，供断言。
    private let sentImages = Mutex<[[AgentImage]]>([])
    /// `clearQueue()` 的返回值。
    private let clearedQueue = Mutex<AgentQueue>(AgentQueue())

    nonisolated init() {
        (stream, continuation) = AsyncStream<AgentEvent>.makeStream(bufferingPolicy: .unbounded)
    }

    /// 已发送的 prompt 文本，供断言。
    var sentPrompts: [String] { sent.withLock { $0 } }

    /// 注入 `sessionState()` 的返回值。
    var sessionStateValue: AgentSessionState? {
        get { state.withLock { $0 } }
        set { state.withLock { $0 = newValue } }
    }

    /// 注入 `availableModels()` 的返回值。
    var availableModelsValue: [AgentModel] {
        get { models.withLock { $0 } }
        set { models.withLock { $0 = newValue } }
    }

    /// 注入 `availableCommands()` 的返回值。
    var availableCommandsValue: [AgentCommand] {
        get { commands.withLock { $0 } }
        set { commands.withLock { $0 = newValue } }
    }

    /// 注入 `forkMessages()` 的返回值。
    var forkMessagesValue: [AgentForkMessage] {
        get { forks.withLock { $0 } }
        set { forks.withLock { $0 = newValue } }
    }

    /// 已 fork 的 entryId。
    var forkedEntryIDsValue: [String] { forkedEntryIDs.withLock { $0 } }

    /// 已 clone 的次数。
    var cloneCountValue: Int { cloneCount.withLock { $0 } }

    /// 注入 `fork` 返回的文本。
    var forkTextValue: String? {
        get { forkText.withLock { $0 } }
        set { forkText.withLock { $0 = newValue } }
    }

    /// 注入 `sessionTree()` 的返回值 / 读取调用次数。
    var sessionTreeValue: AgentSessionTree? {
        get { sessionTreeResult.withLock { $0 } }
        set { sessionTreeResult.withLock { $0 = newValue } }
    }
    var sessionTreeCountValue: Int { sessionTreeCount.withLock { $0 } }

    /// 最近一次设置的自动压缩开关。
    var autoCompactionValue: Bool? { autoCompaction.withLock { $0 } }

    /// 每次 `compact` 传入的指令。
    var compactionInstructionsValue: [String?] { compactionInstructions.withLock { $0 } }

    /// 最近一次设置的自动重试开关。
    var autoRetryValue: Bool? { autoRetry.withLock { $0 } }

    /// `abortRetry` 被调用的次数。
    var abortRetryCountValue: Int { abortRetryCount.withLock { $0 } }

    /// 每次 `exportHTML` 传入的路径。
    var exportPathsValue: [String?] { exportPaths.withLock { $0 } }

    /// 注入 `exportHTML` 的返回值。
    var exportResultValue: String? {
        get { exportResult.withLock { $0 } }
        set { exportResult.withLock { $0 = newValue } }
    }

    /// 每次 `runBash` 传入的命令。
    var bashCommandsValue: [String] { bashCommands.withLock { $0 } }

    /// 注入 `runBash` 的返回值。
    var bashResultValue: AgentBashResult? {
        get { bashResult.withLock { $0 } }
        set { bashResult.withLock { $0 = newValue } }
    }

    /// `abortBash` 被调用的次数。
    var abortBashCountValue: Int { abortBashCount.withLock { $0 } }

    /// 注入 `cycleModel` / `cycleThinkingLevel` / `lastAssistantText` 的返回值。
    var cycleModelValue: AgentModel? {
        get { cycleModelResult.withLock { $0 } }
        set { cycleModelResult.withLock { $0 = newValue } }
    }
    var cycleThinkingLevelValue: String? {
        get { cycleThinkingResult.withLock { $0 } }
        set { cycleThinkingResult.withLock { $0 = newValue } }
    }
    var lastAssistantTextValue: String? {
        get { lastAssistant.withLock { $0 } }
        set { lastAssistant.withLock { $0 = newValue } }
    }

    /// `cycleModel` / `cycleThinkingLevel` 的调用次数。
    var cycleModelCountValue: Int { cycleModelCount.withLock { $0 } }
    var cycleThinkingCountValue: Int { cycleThinkingCount.withLock { $0 } }

    /// 注入 `sessionStats()` 的返回值。
    var sessionStatsValue: AgentUsage? {
        get { usage.withLock { $0 } }
        set { usage.withLock { $0 = newValue } }
    }

    /// 注入 `sessionEntries(since:)` 的全量返回值。
    var sessionEntriesValue: [SessionEntryDTO] {
        get { entries.withLock { $0 } }
        set { entries.withLock { $0 = newValue } }
    }

    /// 直接注入 `sessionEntries(since:)` 的结果，覆盖游标过滤（用于测试分支/游标场景）。
    var sessionEntriesPageValue: SessionEntriesPage? {
        get { entriesPage.withLock { $0 } }
        set { entriesPage.withLock { $0 = newValue } }
    }

    /// 注入 `prompt(_:)` 的返回值。
    var promptDispositionValue: PromptDisposition {
        get { disposition.withLock { $0 } }
        set { disposition.withLock { $0 = newValue } }
    }

    /// 已发送的 steering 文本。
    var steeredMessages: [String] { steered.withLock { $0 } }

    /// 已发送的 follow-up 文本。
    var followUpMessages: [String] { followUps.withLock { $0 } }

    /// 每次 `prompt` 附带的图片批次。
    var sentImageBatches: [[AgentImage]] { sentImages.withLock { $0 } }

    /// 注入 `clearQueue()` 的返回值。
    var clearedQueueValue: AgentQueue {
        get { clearedQueue.withLock { $0 } }
        set { clearedQueue.withLock { $0 = newValue } }
    }

    func events() async -> AsyncStream<AgentEvent> {
        stream
    }

    @discardableResult
    func prompt(_ message: String, images: [AgentImage]) async throws -> PromptDisposition {
        sent.withLock { $0.append(message) }
        sentImages.withLock { $0.append(images) }
        return promptDispositionValue
    }

    @discardableResult
    func steer(_ message: String, images: [AgentImage]) async throws -> PromptDisposition {
        steered.withLock { $0.append(message) }
        return .queued
    }

    @discardableResult
    func followUp(_ message: String, images: [AgentImage]) async throws -> PromptDisposition {
        followUps.withLock { $0.append(message) }
        return .queued
    }

    func clearQueue() async -> AgentQueue {
        clearedQueueValue
    }

    func abort() async {}

    func sessionState() async -> AgentSessionState? {
        state.withLock { $0 }
    }

    func availableModels() async -> [AgentModel] {
        models.withLock { $0 }
    }

    func availableCommands() async -> [AgentCommand] {
        commands.withLock { $0 }
    }

    func forkMessages() async -> [AgentForkMessage] {
        forks.withLock { $0 }
    }

    func fork(entryId: String) async -> String? {
        forkedEntryIDs.withLock { $0.append(entryId) }
        return forkTextValue
    }

    func clone() async -> Bool {
        cloneCount.withLock { $0 += 1 }
        return true
    }

    func setModel(_ model: AgentModel) async -> Bool {
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.model = model
            current = updated
        }
        return true
    }

    func setThinkingLevel(_ level: String) async -> Bool {
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.thinkingLevel = level
            current = updated
        }
        return true
    }

    func setSessionName(_ name: String) async -> Bool {
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.sessionName = name
            current = updated
        }
        return true
    }

    func compact(customInstructions: String?) async -> Bool {
        compactionInstructions.withLock { $0.append(customInstructions) }
        return true
    }

    func setAutoCompaction(enabled: Bool) async -> Bool {
        autoCompaction.withLock { $0 = enabled }
        state.withLock { current in
            var updated = current ?? AgentSessionState()
            updated.autoCompactionEnabled = enabled
            current = updated
        }
        return true
    }

    func setAutoRetry(enabled: Bool) async -> Bool {
        autoRetry.withLock { $0 = enabled }
        return true
    }

    func abortRetry() async -> Bool {
        abortRetryCount.withLock { $0 += 1 }
        return true
    }

    func exportHTML(outputPath: String?) async -> String? {
        exportPaths.withLock { $0.append(outputPath) }
        return exportResultValue
    }

    func cycleModel() async -> AgentModel? {
        cycleModelCount.withLock { $0 += 1 }
        return cycleModelValue
    }

    func cycleThinkingLevel() async -> String? {
        cycleThinkingCount.withLock { $0 += 1 }
        return cycleThinkingLevelValue
    }

    func lastAssistantText() async -> String? {
        lastAssistantTextValue
    }

    func runBash(command: String) async -> AgentBashResult? {
        bashCommands.withLock { $0.append(command) }
        return bashResultValue
    }

    func abortBash() async -> Bool {
        abortBashCount.withLock { $0 += 1 }
        return true
    }

    func sessionStats() async -> AgentUsage? {
        usage.withLock { $0 }
    }

    func sessionEntries(since: String?) async -> SessionEntriesPage? {
        // 仅增量路径使用注入页；全量路径（since == nil）仍从 `sessionEntriesValue` 构造。
        if since != nil, let page = sessionEntriesPageValue { return page }
        let all = entries.withLock { $0 }
        guard let since else { return SessionEntriesPage(entries: all, leafId: nil) }
        // 模拟 pi：`since` 必须命中某条 id，否则视为失效游标（nil → 调用方退回全量）。
        guard let index = all.firstIndex(where: { $0.id == since }) else { return nil }
        return SessionEntriesPage(entries: Array(all[(index + 1)...]), leafId: nil)
    }

    func sessionTree() async -> AgentSessionTree? {
        sessionTreeCount.withLock { $0 += 1 }
        return sessionTreeValue
    }

    func shutdown() async {
        continuation.finish()
    }

    /// 注入一个事件（测试/预览用）。
    func emit(_ event: AgentEvent) {
        continuation.yield(event)
    }
}
