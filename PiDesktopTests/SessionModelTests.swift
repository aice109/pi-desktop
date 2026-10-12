//
//  SessionModelTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftData
import XCTest

@testable import PiDesktop

/// 领域模型（ADR-0004）的持久化行为测试。
final class SessionModelTests: XCTestCase {
    /// 建一个独立的内存容器，避免用例间相互污染、也避免写入真实数据。
    ///
    /// 返回的是 `ModelContainer` 而非 `mainContext`：`ModelContext` 不持有其容器，
    /// 若容器在此处被释放，后续使用 context 会触发 SwiftData 断言崩溃（SIGTRAP）。
    /// 因此调用方必须持有容器，直到用例结束。
    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Session.self, Message.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @MainActor
    func test_appendMessage_persistsMessageAndUpdatesTimestamp() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let session = Session(title: "Test")
        context.insert(session)
        let message = Message(role: .user, content: "hello")
        session.append(message)
        try context.save()

        let sessions = try context.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.messages.count, 1)
        XCTAssertEqual(sessions.first?.messages.first?.content, "hello")
        // append 应把 updatedAt 同步到该消息时间。
        XCTAssertEqual(sessions.first?.updatedAt, message.createdAt)
    }

    @MainActor
    func test_deleteSession_cascadesToMessages() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let session = Session(title: "Doomed")
        context.insert(session)
        session.append(Message(role: .assistant, content: "bye"))
        try context.save()

        context.delete(session)
        try context.save()

        let messages = try context.fetch(FetchDescriptor<Message>())
        XCTAssertTrue(messages.isEmpty, "删除会话应级联删除其消息")
    }
}
