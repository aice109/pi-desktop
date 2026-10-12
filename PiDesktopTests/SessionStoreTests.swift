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
            for: Session.self, Message.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let transport = MockAgentTransport()
        let store = SessionStore(container: container, makeTransport: { _ in transport })
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

    // MARK: - Helpers

    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
