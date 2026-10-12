//
//  SessionStoreTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
import SwiftData
@testable import PiDesktop

/// `SessionStore` 的事件 → 消息映射测试。用 `MockAgentTransport`，不启动真实进程。
@MainActor
final class SessionStoreTests: XCTestCase {
    private struct Fixture {
        let store: SessionStore
        let container: ModelContainer
        let transport: MockAgentTransport
        let session: Session

        var assistantMessage: Message? {
            session.messages.first { $0.role == .assistant }
        }
    }

    /// 持有 container：`ModelContext` 不持有其容器，容器被释放会导致崩溃。
    private func makeFixture() throws -> Fixture {
        let container = try ModelContainer(
            for: Session.self, Message.self, ToolCall.self, MessageImage.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let transport = MockAgentTransport()
        let store = SessionStore(container: container, makeTransport: { _, _ in transport })
        let session = Session(title: "Test")
        container.mainContext.insert(session)
        return Fixture(store: store, container: container, transport: transport, session: session)
    }

    func test_send_insertsUserMessageAndPromptsTransport() async throws {
        let fixture = try makeFixture()

        await fixture.store.send("hello", in: fixture.session)

        XCTAssertEqual(fixture.transport.sentPrompts, ["hello"])
        XCTAssertEqual(fixture.session.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(fixture.session.messages.first { $0.role == .user }?.content, "hello")
        XCTAssertTrue(fixture.store.isStreaming(fixture.session))
    }

    func test_send_persistsImagesAndForwardsThem() async throws {
        let fixture = try makeFixture()
        let image = AgentImage(mimeType: "image/png", data: Data([1, 2, 3]))

        await fixture.store.send("look", images: [image], in: fixture.session)

        XCTAssertEqual(fixture.transport.sentImageBatches.last?.count, 1)
        let user = fixture.session.messages.first { $0.role == .user }
        XCTAssertEqual(user?.images.count, 1)
        XCTAssertEqual(user?.images.first?.mimeType, "image/png")
        XCTAssertEqual(user?.images.first?.data, Data([1, 2, 3]))
    }

    func test_send_allowsImageOnlyMessages() async throws {
        let fixture = try makeFixture()

        await fixture.store.send("", images: [AgentImage(mimeType: "image/png", data: Data([9]))], in: fixture.session)

        XCTAssertEqual(fixture.transport.sentPrompts, [""])
        XCTAssertEqual(fixture.session.messages.filter { $0.role == .user }.count, 1)
    }

    func test_streamingText_updatesAssistantMessage() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        fixture.transport.emit(.textDelta("Hel"))
        fixture.transport.emit(.textDelta("lo"))
        await waitUntil { fixture.assistantMessage?.content == "Hello" }

        XCTAssertEqual(fixture.assistantMessage?.content, "Hello")
        XCTAssertTrue(fixture.store.isStreaming(fixture.session))
    }

    func test_settled_stopsStreamingAndKeepsAuthoritativeText() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        // 增量内容最终应被 message_end 的权威内容替换。
        fixture.transport.emit(.textDelta("Hel"))
        fixture.transport.emit(.assistantMessageCompleted(text: "Hello!", stopReason: "stop", errorMessage: nil))
        fixture.transport.emit(.settled(aborted: false))
        await waitUntil { !fixture.store.isStreaming(fixture.session) }

        XCTAssertEqual(fixture.assistantMessage?.content, "Hello!")
    }

    func test_settledWithNoContent_removesEmptyAssistantMessage() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        fixture.transport.emit(.settled(aborted: true))
        await waitUntil { !fixture.store.isStreaming(fixture.session) }

        XCTAssertEqual(fixture.session.messages.filter { $0.role == .assistant }.count, 0)
    }

    func test_failed_surfacesErrorAndStopsStreaming() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        fixture.transport.emit(.failed("boom"))
        await waitUntil { !fixture.store.isStreaming(fixture.session) }

        XCTAssertEqual(fixture.assistantMessage?.content, "boom")
    }

    func test_handledPrompt_stopsStreamingWithoutWaitingForSettled() async throws {
        let fixture = try makeFixture()
        // 扩展命令/输入处理器立即消费 prompt：不会再有 agent_settled。
        fixture.transport.promptDispositionValue = .handled

        await fixture.store.send("/some-command", in: fixture.session)
        // 删除占位消息后，SwiftData 的关系数组需要一次运行循环才更新，等待其传播。
        await waitUntil {
            !fixture.store.isStreaming(fixture.session)
                && fixture.session.messages.allSatisfy { $0.role != .assistant }
        }

        // 无正文的占位助手气泡应被移除，用户消息保留。
        XCTAssertEqual(fixture.session.messages.filter { $0.role == .assistant }.count, 0)
        XCTAssertEqual(fixture.session.messages.filter { $0.role == .user }.count, 1)
    }

    func test_streamingReasoning_isExposedWhileStreaming() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        XCTAssertNil(fixture.store.reasoning(in: fixture.session))
        fixture.transport.emit(.thinkingDelta("Let me "))
        fixture.transport.emit(.thinkingDelta("think."))
        await waitUntil { fixture.store.reasoning(in: fixture.session) == "Let me think." }

        XCTAssertEqual(fixture.store.reasoning(in: fixture.session), "Let me think.")

        fixture.transport.emit(.settled(aborted: false))
        await waitUntil { !fixture.store.isStreaming(fixture.session) }
        XCTAssertNil(fixture.store.reasoning(in: fixture.session))
    }

    func test_toolCalls_arePersistedWithOutputAndDuration() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        fixture.transport.emit(.toolCallStarted(id: "call_1", name: "bash", arguments: "command: ls"))
        await waitUntil { fixture.session.toolCalls.count == 1 }
        XCTAssertEqual(fixture.store.activeToolName, "bash")
        XCTAssertEqual(fixture.session.toolCalls.first?.arguments, "command: ls")
        XCTAssertNil(fixture.session.toolCalls.first?.durationMs)
        XCTAssertTrue(fixture.store.isRunningTool("call_1"))

        fixture.transport.emit(.toolCallUpdated(id: "call_1", output: "partial"))
        await waitUntil { fixture.session.toolCalls.first?.output == "partial" }

        fixture.transport.emit(.toolCallFinished(
            id: "call_1", name: "bash", isError: false, durationMs: 12, output: "done"
        ))
        await waitUntil { fixture.session.toolCalls.first?.durationMs == 12 }
        XCTAssertEqual(fixture.session.toolCalls.first?.output, "done")
        XCTAssertFalse(fixture.store.isRunningTool("call_1"))
        XCTAssertNil(fixture.store.activeToolName)

        fixture.transport.emit(.settled(aborted: false))
        await waitUntil { !fixture.store.isStreaming(fixture.session) }
    }

    func test_activate_loadsStateAndUsage() async throws {
        let fixture = try makeFixture()
        let model = AgentModel(id: "m1", name: "Model One", provider: "p", reasoning: true, contextWindow: 1000)
        fixture.transport.sessionStateValue = AgentSessionState(
            model: model,
            thinkingLevel: "high",
            availableThinkingLevels: ["off", "high"]
        )
        fixture.transport.availableModelsValue = [model]
        fixture.transport.sessionStatsValue = AgentUsage(
            inputTokens: 1, outputTokens: 2, cacheReadTokens: 0, cacheWriteTokens: 0,
            totalTokens: 3, costUSD: 0.5, contextTokens: 10, contextWindow: 1000, contextPercent: 1
        )

        await fixture.store.activate(fixture.session)

        XCTAssertEqual(fixture.store.state(for: fixture.session)?.model?.id, "m1")
        XCTAssertEqual(fixture.store.state(for: fixture.session)?.thinkingLevel, "high")
        XCTAssertEqual(fixture.store.usage(for: fixture.session)?.totalTokens, 3)
        let models = await fixture.store.availableModels(for: fixture.session)
        XCTAssertEqual(models.count, 1)
    }

    func test_activate_clearsLoadingFlag() async throws {
        let fixture = try makeFixture()
        XCTAssertFalse(fixture.store.isLoading(fixture.session))

        await fixture.store.activate(fixture.session)

        XCTAssertFalse(fixture.store.isLoading(fixture.session))
    }

    func test_agentModel_matchesByProviderAndID() {
        let model = AgentModel(id: "m1", name: "Model One", provider: "p", reasoning: true, contextWindow: 1000)
        // 同一模型来自不同命令时，展示字段（name / contextWindow / reasoning）可能不同。
        let other = AgentModel(id: "m1", name: "Catalog Name", provider: "p", reasoning: false, contextWindow: nil)
        XCTAssertTrue(model.matches(other))
        XCTAssertFalse(model.matches(AgentModel(id: "m2", name: "Model One", provider: "p", reasoning: true, contextWindow: nil)))
        XCTAssertFalse(model.matches(AgentModel(id: "m1", name: "Model One", provider: "q", reasoning: true, contextWindow: nil)))
    }

    func test_selectModel_updatesState() async throws {
        let fixture = try makeFixture()
        await fixture.store.activate(fixture.session)

        let model = AgentModel(id: "m2", name: "Two", provider: "p", reasoning: false, contextWindow: nil)
        await fixture.store.selectModel(model, in: fixture.session)

        XCTAssertEqual(fixture.store.state(for: fixture.session)?.model?.id, "m2")
    }

    func test_rename_setsTitleAndCallsTransport() async throws {
        let fixture = try makeFixture()
        fixture.session.title = "Old"

        await fixture.store.rename(fixture.session, to: "  New Name  ")

        XCTAssertEqual(fixture.session.title, "New Name")
        XCTAssertEqual(fixture.transport.sessionStateValue?.sessionName, "New Name")
    }

    func test_reasoning_isPersistedIntoAssistantMessage() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        fixture.transport.emit(.thinkingDelta("step 1 "))
        fixture.transport.emit(.thinkingDelta("step 2"))
        fixture.transport.emit(.assistantMessageCompleted(text: "Done", stopReason: "stop", errorMessage: nil))
        await waitUntil { fixture.assistantMessage?.content == "Done" }

        XCTAssertEqual(fixture.assistantMessage?.thinking, "step 1 step 2")
    }

    func test_retryAndCompaction_setAndClearActivity() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)
        XCTAssertNil(fixture.store.activity(for: fixture.session))

        fixture.transport.emit(.retryStarted(attempt: 2, maxAttempts: 3))
        await waitUntil { fixture.store.activity(for: fixture.session) != nil }
        XCTAssertEqual(fixture.store.activity(for: fixture.session)?.displayText, "Retrying (2/3)…")

        fixture.transport.emit(.retryFinished(success: true))
        await waitUntil { fixture.store.activity(for: fixture.session) == nil }

        fixture.transport.emit(.compactionStarted)
        await waitUntil { fixture.store.activity(for: fixture.session)?.displayText == "Compacting context…" }

        fixture.transport.emit(.compactionFinished(aborted: false, errorMessage: nil))
        await waitUntil { fixture.store.activity(for: fixture.session) == nil }
    }

    func test_steer_forwardsOnlyWhileStreaming() async throws {
        let fixture = try makeFixture()
        // 空闲时忽略：由调用方（UI）退回普通发送。
        await fixture.store.steer("stop", in: fixture.session)
        XCTAssertTrue(fixture.transport.steeredMessages.isEmpty)

        await fixture.store.send("hi", in: fixture.session)
        await fixture.store.steer("stop", in: fixture.session)
        XCTAssertEqual(fixture.transport.steeredMessages, ["stop"])
    }

    func test_followUp_forwardsWhileStreaming() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)

        await fixture.store.followUp("then test", in: fixture.session)

        XCTAssertEqual(fixture.transport.followUpMessages, ["then test"])
        XCTAssertTrue(fixture.transport.steeredMessages.isEmpty)
    }

    func test_clearQueue_returnsClearedTextAndEmptiesLocalQueue() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)
        fixture.transport.emit(.queueUpdated(AgentQueue(steering: ["stop"], followUp: ["then"])))
        await waitUntil { !fixture.store.queued(for: fixture.session).isEmpty }

        fixture.transport.clearedQueueValue = AgentQueue(steering: ["stop"], followUp: ["then"])
        let cleared = await fixture.store.clearQueue(in: fixture.session)

        XCTAssertEqual(cleared.steering, ["stop"])
        XCTAssertEqual(cleared.followUp, ["then"])
        XCTAssertTrue(fixture.store.queued(for: fixture.session).isEmpty)
    }

    func test_forkMessages_areExposed() async throws {
        let fixture = try makeFixture()
        let message = AgentForkMessage(entryId: "e1", text: "hello")
        fixture.transport.forkMessagesValue = [message]
        await fixture.store.activate(fixture.session)

        let messages = await fixture.store.forkMessages(for: fixture.session)

        XCTAssertEqual(messages, [message])
    }

    func test_fork_forwardsEntryAndResyncs() async throws {
        let fixture = try makeFixture()
        await fixture.store.activate(fixture.session)

        await fixture.store.fork(fixture.session, from: "entry-1")

        XCTAssertEqual(fixture.transport.forkedEntryIDsValue, ["entry-1"])
    }

    func test_clone_forwardsToTransport() async throws {
        let fixture = try makeFixture()
        await fixture.store.activate(fixture.session)

        await fixture.store.clone(fixture.session)

        XCTAssertEqual(fixture.transport.cloneCountValue, 1)
    }

    func test_queueUpdate_isExposed() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)
        XCTAssertTrue(fixture.store.queued(for: fixture.session).isEmpty)

        fixture.transport.emit(.queueUpdated(AgentQueue(steering: ["stop"], followUp: ["then test"])))
        await waitUntil { fixture.store.queued(for: fixture.session).steering == ["stop"] }

        XCTAssertEqual(fixture.store.queued(for: fixture.session).followUp, ["then test"])
    }

    func test_sessionInfoChanged_updatesTitle() async throws {
        let fixture = try makeFixture()
        await fixture.store.activate(fixture.session)

        fixture.transport.emit(.sessionInfoChanged(name: "renamed by pi"))
        await waitUntil { fixture.session.title == "renamed by pi" }

        XCTAssertEqual(fixture.session.title, "renamed by pi")
    }

    func test_thinkingLevelChanged_updatesState() async throws {
        let fixture = try makeFixture()
        fixture.transport.sessionStateValue = AgentSessionState(thinkingLevel: "low")
        await fixture.store.activate(fixture.session)
        XCTAssertEqual(fixture.store.state(for: fixture.session)?.thinkingLevel, "low")

        fixture.transport.emit(.thinkingLevelChanged(level: "high"))
        await waitUntil { fixture.store.state(for: fixture.session)?.thinkingLevel == "high" }

        XCTAssertEqual(fixture.store.state(for: fixture.session)?.thinkingLevel, "high")
    }

    func test_settled_discoversPiSessionPathAndNotifies() async throws {
        let fixture = try makeFixture()
        fixture.transport.sessionStateValue = AgentSessionState(
            sessionFile: "/tmp/sessions/abc.jsonl",
            sessionId: "abc",
            sessionName: "My Session"
        )
        var refreshed = false
        fixture.store.onSessionPersisted = { refreshed = true }

        // 空标题时才采用 pi 的会话名。
        fixture.session.title = ""
        await fixture.store.send("hi", in: fixture.session)
        fixture.transport.emit(.settled(aborted: false))
        await waitUntil { fixture.session.piSessionPath != nil }

        XCTAssertEqual(fixture.session.piSessionPath, "/tmp/sessions/abc.jsonl")
        XCTAssertEqual(fixture.session.title, "My Session")
        XCTAssertTrue(refreshed)
    }

    // MARK: - History sync

    func test_activate_syncsHistoryFromTransport() async throws {
        let fixture = try makeFixture()
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("run ls")]), timestamp: "2024-12-03T14:00:02.000Z"),
            entry("assistant", .blocks([
                thinking("Let me look."),
                toolCall(id: "call_1", name: "bash", command: "ls"),
            ]), timestamp: "2024-12-03T14:00:03.000Z"),
            entry(
                "toolResult",
                .blocks([text("AGENTS.md")]),
                timestamp: "2024-12-03T14:00:04.000Z",
                toolCallId: "call_1",
                toolName: "bash"
            ),
        ]

        await fixture.store.activate(fixture.session)

        XCTAssertEqual(fixture.session.messages.count, 2)
        XCTAssertEqual(fixture.session.messages.first?.content, "run ls")
        XCTAssertEqual(fixture.session.messages.last?.thinking, "Let me look.")
        XCTAssertEqual(fixture.session.toolCalls.count, 1)
        XCTAssertEqual(fixture.session.toolCalls.first?.arguments, "command: ls")
        XCTAssertEqual(fixture.session.toolCalls.first?.output, "AGENTS.md")
        // 历史工具仅有 output、没有 durationMs；不能据此判定它仍在运行，
        // 否则工具卡片会永远转圈（长会话尤其明显）。
        XCTAssertFalse(fixture.store.isRunningTool("call_1"))
    }

    /// 性能回归：长历史重建曾是 O(n²) 的 SwiftData 关系赋值（逐条注册/插入），
    /// 数千条会卡住主线程数十秒（6000 条约 32s）。这里用宽松阈值兜底，
    /// 防止退回逐条 `append` 的实现；修好后 6000 条约 0.1s。
    func test_activate_longHistory_doesNotBlockForSeconds() async throws {
        let fixture = try makeFixture()
        let count = 6000
        fixture.transport.sessionEntriesValue = (0..<count).map { index in
            entry(
                index.isMultiple(of: 2) ? "user" : "assistant",
                .blocks([text("message \(index)")]),
                timestamp: "2024-12-03T14:00:02.000Z"
            )
        }

        let started = CFAbsoluteTimeGetCurrent()
        await fixture.store.activate(fixture.session)
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        XCTAssertEqual(fixture.session.messages.count, count)
        XCTAssertLessThan(elapsed, 3, "长历史重建不得长时间阻塞主 actor")
    }

    func test_syncHistory_rebuildsOnlyWhenContentChanges() async throws {
        let fixture = try makeFixture()
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("one")]), timestamp: "2024-12-03T14:00:02.000Z"),
        ]
        // `activate` 会建立传输，使 `syncHistory` 走 RPC 而不是会话文件。
        await fixture.store.activate(fixture.session)
        let firstIDs = fixture.session.messages.map(\.id)
        XCTAssertEqual(fixture.session.messages.map(\.content), ["one"])

        // 内容未变：不应替换对象（否则切换会话时会丢失滚动位置）。
        await fixture.store.syncHistory(for: fixture.session)
        XCTAssertEqual(fixture.session.messages.map(\.id), firstIDs)

        // 新增一轮（例如应用外续聊）：应同步过来。
        fixture.transport.sessionEntriesValue.append(
            entry("assistant", .blocks([text("two")]), timestamp: "2024-12-03T14:00:05.000Z")
        )
        await fixture.store.syncHistory(for: fixture.session)
        XCTAssertEqual(fixture.session.messages.map(\.content), ["one", "two"])
        // 增量追加保留已有对象标识（不是整体重建）。
        XCTAssertEqual(fixture.session.messages.first?.id, firstIDs.first)
    }

    func test_syncHistory_invalidCursorFallsBackToFull() async throws {
        let fixture = try makeFixture()
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("one")]), timestamp: "2024-12-03T14:00:02.000Z"),
        ]
        await fixture.store.activate(fixture.session)
        XCTAssertEqual(fixture.session.messages.map(\.content), ["one"])

        // 游标不再是已知 id（会话被重置）：应退回全量重建。
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("fresh")]), timestamp: "2024-12-04T10:00:00.000Z"),
        ]
        await fixture.store.syncHistory(for: fixture.session)

        XCTAssertEqual(fixture.session.messages.map(\.content), ["fresh"])
    }

    func test_syncHistory_leafChangeTriggersFullRebuild() async throws {
        let fixture = try makeFixture()
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("one")]), timestamp: "2024-12-03T14:00:02.000Z"),
        ]
        await fixture.store.activate(fixture.session)

        // 分支切换：增量无新条目但 leaf 变了；全量数据已含另一分支的内容。
        fixture.transport.sessionEntriesPageValue = SessionEntriesPage(entries: [], leafId: "branch-b")
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("branch-b content")]), timestamp: "2024-12-03T14:00:02.000Z"),
        ]
        await fixture.store.syncHistory(for: fixture.session)

        XCTAssertEqual(fixture.session.messages.map(\.content), ["branch-b content"])
    }

    func test_syncHistory_fallsBackToSessionFile() async throws {
        let fixture = try makeFixture()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jsonl")
        try Self.sessionFile.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        fixture.session.piSessionPath = url.path

        // 尚无传输：直接走会话文件。
        await fixture.store.syncHistory(for: fixture.session)

        XCTAssertEqual(fixture.session.messages.map(\.content), ["hello"])
        XCTAssertEqual(fixture.session.messages.first?.role, .user)
    }

    func test_syncHistory_isSkippedWhileStreaming() async throws {
        let fixture = try makeFixture()
        await fixture.store.send("hi", in: fixture.session)
        fixture.transport.sessionEntriesValue = [
            entry("user", .blocks([text("from pi")]), timestamp: "2024-12-03T14:00:02.000Z"),
        ]

        await fixture.store.syncHistory(for: fixture.session)

        // 流式期间不能抹掉进行中的本地消息。
        XCTAssertEqual(fixture.session.messages.map(\.content), ["hi", ""])
    }

    // MARK: - Helpers

    /// 一个最小可解析的 pi 会话文件。
    private static let sessionFile = """
    {"type":"session","version":3,"id":"s1","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}
    {"type":"message","id":"a","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"hello"}}
    """

    private func text(_ value: String) -> ContentBlockDTO {
        ContentBlockDTO(type: "text", text: value, thinking: nil, id: nil, name: nil, arguments: nil)
    }

    private func thinking(_ value: String) -> ContentBlockDTO {
        ContentBlockDTO(type: "thinking", text: nil, thinking: value, id: nil, name: nil, arguments: nil)
    }

    private func toolCall(id: String, name: String, command: String) -> ContentBlockDTO {
        ContentBlockDTO(
            type: "toolCall",
            text: nil,
            thinking: nil,
            id: id,
            name: name,
            arguments: .object(["command": .string(command)])
        )
    }

    private func entry(
        _ role: String,
        _ content: MessageContentDTO,
        timestamp: String,
        toolCallId: String? = nil,
        toolName: String? = nil,
        isError: Bool? = nil
    ) -> SessionEntryDTO {
        SessionEntryDTO(
            type: "message",
            id: UUID().uuidString,
            timestamp: timestamp,
            message: MessageDTO(
                role: role,
                content: content,
                stopReason: nil,
                errorMessage: nil,
                toolCallId: toolCallId,
                toolName: toolName,
                isError: isError
            )
        )
    }

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
