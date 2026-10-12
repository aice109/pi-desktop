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

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
