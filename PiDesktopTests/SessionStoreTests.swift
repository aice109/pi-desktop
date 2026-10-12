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
            for: Session.self, Message.self, ToolCall.self,
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

        fixture.transport.emit(.toolCallUpdated(id: "call_1", output: "partial"))
        await waitUntil { fixture.session.toolCalls.first?.output == "partial" }

        fixture.transport.emit(.toolCallFinished(
            id: "call_1", name: "bash", isError: false, durationMs: 12, output: "done"
        ))
        await waitUntil { fixture.session.toolCalls.first?.durationMs == 12 }
        XCTAssertEqual(fixture.session.toolCalls.first?.output, "done")
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
