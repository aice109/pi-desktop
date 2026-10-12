//
//  PiHistoryTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest

@testable import PiDesktop

/// `PiHistory` 的条目 → 消息 / 工具调用映射测试。
final class PiHistoryTests: XCTestCase {
    private func textBlock(_ text: String) -> ContentBlockDTO {
        ContentBlockDTO(type: "text", text: text, thinking: nil, id: nil, name: nil, arguments: nil)
    }

    private func thinkingBlock(_ text: String) -> ContentBlockDTO {
        ContentBlockDTO(type: "thinking", text: nil, thinking: text, id: nil, name: nil, arguments: nil)
    }

    private func toolCallBlock(id: String, name: String, command: String) -> ContentBlockDTO {
        ContentBlockDTO(
            type: "toolCall",
            text: nil,
            thinking: nil,
            id: id,
            name: name,
            arguments: .object(["command": .string(command)])
        )
    }

    private func imageBlock(base64: String, mimeType: String = "image/png") -> ContentBlockDTO {
        ContentBlockDTO(
            type: "image",
            text: nil,
            thinking: nil,
            id: nil,
            name: nil,
            arguments: nil,
            data: base64,
            mimeType: mimeType
        )
    }

    private func entry(
        _ role: String,
        _ content: MessageContentDTO,
        timestamp: Date? = nil,
        toolCallId: String? = nil,
        toolName: String? = nil,
        isError: Bool? = nil,
        id: String? = nil,
        parentId: String? = nil
    ) -> PiHistoryEntry {
        PiHistoryEntry(
            role: role,
            content: content,
            timestamp: timestamp,
            toolCallId: toolCallId,
            toolName: toolName,
            isError: isError,
            id: id,
            parentId: parentId
        )
    }

    func test_make_mapsMessagesAndAssociatesToolArguments() {
        let history = PiHistory.make(from: [
            entry("user", .blocks([textBlock("run ls")])),
            entry(
                "assistant",
                .blocks([
                    thinkingBlock("Let me look."),
                    toolCallBlock(id: "call_1", name: "bash", command: "ls"),
                ])),
            entry("toolResult", .blocks([textBlock("AGENTS.md")]), toolCallId: "call_1", toolName: "bash"),
        ])

        XCTAssertEqual(history.messages.count, 2)
        XCTAssertEqual(history.messages[0].role, .user)
        XCTAssertEqual(history.messages[0].text, "run ls")
        XCTAssertEqual(history.messages[1].thinking, "Let me look.")
        XCTAssertEqual(history.toolCalls.count, 1)
        XCTAssertEqual(history.toolCalls[0].arguments, "command: ls")
        XCTAssertEqual(history.toolCalls[0].output, "AGENTS.md")
        XCTAssertFalse(history.toolCalls[0].isError)
    }

    func test_make_carriesToolErrorFlag() {
        let history = PiHistory.make(from: [
            entry(
                "toolResult", .blocks([textBlock("boom")]), toolCallId: "call_9", toolName: "bash",
                isError: true)
        ])
        XCTAssertTrue(history.toolCalls[0].isError)
    }

    func test_make_keepsThinkingOnlyAssistantMessages() {
        let history = PiHistory.make(from: [
            entry("assistant", .blocks([thinkingBlock("hmm")]))
        ])
        XCTAssertEqual(history.messages.count, 1)
        XCTAssertEqual(history.messages[0].text, "")
        XCTAssertEqual(history.messages[0].thinking, "hmm")
    }

    func test_make_ignoresUnknownRolesAndEmptyContent() {
        let history = PiHistory.make(from: [
            entry("system", .text("You are pi")),
            entry("user", .blocks([])),
            entry("custom", .blocks([textBlock("hi")])),
        ])
        XCTAssertTrue(history.isEmpty)
    }

    func test_make_acceptsPlainStringContent() {
        let history = PiHistory.make(from: [entry("user", .text("hello"))])
        XCTAssertEqual(history.messages.map(\.text), ["hello"])
    }

    func test_make_fallsBackToNowWhenTimestampMissing() {
        let now = Date(timeIntervalSince1970: 1_000)
        let history = PiHistory.make(from: [entry("user", .text("hi"))], now: now)
        XCTAssertEqual(history.messages[0].timestamp, now)
    }

    func test_make_namesUnknownTools() {
        let history = PiHistory.make(from: [
            entry("toolResult", .blocks([textBlock("x")]), toolCallId: "call_1", toolName: nil)
        ])
        XCTAssertEqual(history.toolCalls[0].name, "tool")
    }

    func test_make_mapsBashExecutionToToolMessage() {
        let history = PiHistory.make(from: [
            PiHistoryEntry(
                role: "bashExecution",
                content: .text(""),
                timestamp: nil,
                toolCallId: nil,
                toolName: nil,
                isError: nil,
                id: "b1",
                parentId: nil,
                command: "ls",
                output: "file.txt"
            )
        ])

        XCTAssertEqual(history.messages.count, 1)
        XCTAssertEqual(history.messages[0].role, .tool)
        XCTAssertEqual(history.messages[0].text, "! ls\nfile.txt")
    }

    func test_make_filtersToActiveBranch() {
        // 追加式树：root → 两个分支，leafID 指向分支 B。
        let entries = [
            entry("user", .blocks([textBlock("root")]), id: "u", parentId: nil),
            entry("assistant", .blocks([textBlock("branch A")]), id: "a", parentId: "u"),
            entry("assistant", .blocks([textBlock("branch B")]), id: "b", parentId: "u"),
        ]

        let history = PiHistory.make(from: entries, leafID: "b")

        XCTAssertEqual(history.messages.map(\.text), ["root", "branch B"])
    }

    func test_make_withoutLeafKeepsAppendOrder() {
        let entries = [
            entry("user", .blocks([textBlock("root")]), id: "u", parentId: nil),
            entry("assistant", .blocks([textBlock("branch A")]), id: "a", parentId: "u"),
            entry("assistant", .blocks([textBlock("branch B")]), id: "b", parentId: "u"),
        ]

        let history = PiHistory.make(from: entries)

        XCTAssertEqual(history.messages.map(\.text), ["root", "branch A", "branch B"])
    }

    func test_make_parsesImageBlocks() {
        let raw = Data("hello".utf8).base64EncodedString()
        let history = PiHistory.make(from: [
            entry("user", .blocks([textBlock("look"), imageBlock(base64: raw)]))
        ])

        XCTAssertEqual(history.messages.count, 1)
        XCTAssertEqual(history.messages[0].images.count, 1)
        XCTAssertEqual(history.messages[0].images[0].mimeType, "image/png")
        XCTAssertEqual(history.messages[0].images[0].data, Data("hello".utf8))
    }

    func test_make_keepsImageOnlyUserMessage() {
        let raw = Data([0x01, 0x02]).base64EncodedString()
        let history = PiHistory.make(from: [entry("user", .blocks([imageBlock(base64: raw)]))])

        XCTAssertEqual(history.messages.count, 1)
        XCTAssertEqual(history.messages[0].text, "")
        XCTAssertEqual(history.messages[0].images.count, 1)
    }

    func test_make_skipsInvalidBase64Image() {
        let history = PiHistory.make(from: [
            entry("user", .blocks([textBlock("hi"), imageBlock(base64: "!!!not-base64")]))
        ])
        XCTAssertEqual(history.messages[0].images.count, 0)
    }

    func test_fingerprint_changesWithContent() {
        let base = PiHistory.make(from: [entry("user", .text("one"))])
        var extended = base
        extended.messages.append(
            PiDisplayMessage(role: .assistant, text: "two", thinking: nil, timestamp: .now))

        XCTAssertNotEqual(PiHistoryFingerprint(base), PiHistoryFingerprint(extended))
        XCTAssertEqual(PiHistoryFingerprint(base), PiHistoryFingerprint(base))
    }
}
