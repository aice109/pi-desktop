//
//  PiSessionFilesTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
@testable import PiDesktop

/// `PiSessionFiles` 的解析测试：目录名编码、摘要与消息解析。
final class PiSessionFilesTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appending(path: "PiSessionFilesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func test_directoryName_matchesPiGroupingRules() {
        XCTAssertEqual(
            PiSessionFiles.directoryName(for: "/Users/me/Developer/Proj"),
            "--Users-me-Developer-Proj--"
        )
        XCTAssertEqual(PiSessionFiles.directoryName(for: "/Users/me"), "--Users-me--")
        // Windows 风格路径：`:` 与 `\` 均归一为 `-`（pi 的规则）。
        XCTAssertEqual(PiSessionFiles.directoryName(for: "C:\\Users\\me"), "--C--Users-me--")
    }

    func test_summary_parsesHeaderNamePreviewAndCount() throws {
        let url = try writeSession(named: "one", lines: [
            #"{"type":"session","version":3,"id":"session-1","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}"#,
            #"{"type":"model_change","id":"a","parentId":null,"timestamp":"2024-12-03T14:00:01.000Z","provider":"x","modelId":"y"}"#,
            #"{"type":"message","id":"b","parentId":"a","timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"Hello there"}}"#,
            #"{"type":"message","id":"c","parentId":"b","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi!"}]}}"#,
            #"{"type":"message","id":"d","parentId":"c","timestamp":"2024-12-03T14:00:04.000Z","message":{"role":"toolResult","toolCallId":"x","toolName":"bash","content":[{"type":"text","text":"out"}],"isError":false}}"#,
            #"{"type":"session_info","id":"e","parentId":"d","timestamp":"2024-12-03T14:00:05.000Z","name":"Refactor auth"}"#,
        ])

        let summary = try XCTUnwrap(PiSessionFiles.summary(of: url))
        XCTAssertEqual(summary.sessionID, "session-1")
        XCTAssertEqual(summary.cwd, "/tmp/proj")
        XCTAssertEqual(summary.name, "Refactor auth")
        // 工具结果不再计入消息数（它们属于 ToolCall）。
        XCTAssertEqual(summary.messageCount, 2)
        XCTAssertEqual(summary.preview, "Hello there")
        XCTAssertEqual(summary.displayTitle, "Refactor auth")
    }

    func test_summary_fallsBackToPreviewWhenUnnamed() throws {
        let url = try writeSession(named: "unnamed", lines: [
            #"{"type":"session","version":3,"id":"s2","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}"#,
            #"{"type":"message","id":"b","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"What does this project do?"}}"#,
        ])

        let summary = try XCTUnwrap(PiSessionFiles.summary(of: url))
        XCTAssertNil(summary.name)
        XCTAssertEqual(summary.displayTitle, "What does this project do?")
    }

    func test_messages_mapsRolesAndText() throws {
        let url = try writeSession(named: "messages", lines: [
            #"{"type":"session","version":3,"id":"s3","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}"#,
            #"{"type":"message","id":"b","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"Hello"}}"#,
            #"{"type":"message","id":"c","parentId":"b","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Hi "},{"type":"text","text":"there"}]}}"#,
            #"{"type":"message","id":"d","parentId":"c","timestamp":"2024-12-03T14:00:04.000Z","message":{"role":"system","content":""}}"#,
        ])

        let messages = PiSessionFiles.history(in: url).messages
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.map(\.text), ["Hello", "Hi there"])
    }

    func test_messages_parsesAssistantThinking() throws {
        let url = try writeSession(named: "thinking", lines: [
            #"{"type":"session","version":3,"id":"s5","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}"#,
            #"{"type":"message","id":"b","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"why?"}}"#,
            #"{"type":"message","id":"c","parentId":"b","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"assistant","content":[{"type":"thinking","thinking":"Let me think."},{"type":"text","text":"Answer"}]}}"#,
        ])

        let messages = PiSessionFiles.history(in: url).messages
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[1].text, "Answer")
        XCTAssertEqual(messages[1].thinking, "Let me think.")
        XCTAssertNil(messages[0].thinking)
    }

    func test_toolCalls_parsesToolResultEntries() throws {
        let url = try writeSession(named: "tools", lines: [
            #"{"type":"session","version":3,"id":"s4","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}"#,
            #"{"type":"message","id":"b","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"list files"}}"#,
            #"{"type":"message","id":"c","parentId":"b","timestamp":"2024-12-03T14:00:02.500Z","message":{"role":"assistant","content":[{"type":"toolCall","id":"call_1","name":"bash","arguments":{"command":"ls"}}]}}"#,
            #"{"type":"message","id":"d","parentId":"c","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"toolResult","toolCallId":"call_1","toolName":"bash","content":[{"type":"text","text":"README.md"}],"isError":false}}"#,
        ])

        let toolCalls = PiSessionFiles.history(in: url).toolCalls
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls.first?.toolCallID, "call_1")
        XCTAssertEqual(toolCalls.first?.name, "bash")
        // 参数来自助手消息的 toolCall 块。
        XCTAssertEqual(toolCalls.first?.arguments, "command: ls")
        XCTAssertEqual(toolCalls.first?.output, "README.md")
        XCTAssertEqual(toolCalls.first?.isError, false)
        // 工具结果/仅含 toolCall 的助手消息都不应作为消息出现。
        XCTAssertEqual(PiSessionFiles.history(in: url).messages.map(\.role), [.user])
    }

    func test_summaries_sortsByRecencyAndIgnoresInvalidFiles() throws {
        let older = try writeSession(named: "older", lines: [
            #"{"type":"session","version":3,"id":"old","timestamp":"2024-12-01T14:00:00.000Z","cwd":"/tmp/proj"}"#,
        ])
        let newer = try writeSession(named: "newer", lines: [
            #"{"type":"session","version":3,"id":"new","timestamp":"2024-12-02T14:00:00.000Z","cwd":"/tmp/proj"}"#,
        ])
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000)],
            ofItemAtPath: older.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2_000)],
            ofItemAtPath: newer.path
        )
        // 非会话文件应被忽略。
        try Data("not json".utf8).write(to: temporaryDirectory.appending(path: "broken.jsonl"))

        let summaries = PiSessionFiles.summaries(in: temporaryDirectory)
        XCTAssertEqual(summaries.map(\.sessionID), ["new", "old"])
    }

    func test_summary_cache_invalidatesWhenFileChanges() throws {
        let header = #"{"type":"session","version":3,"id":"cache","timestamp":"2024-12-03T14:00:00.000Z","cwd":"/tmp/proj"}"#
        let user = #"{"type":"message","id":"b","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":"one"}}"#
        let assistant = #"{"type":"message","id":"c","parentId":"b","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"two"}]}}"#
        let url = try writeSession(named: "cache", lines: [header, user])

        XCTAssertEqual(PiSessionFiles.summary(of: url)?.messageCount, 1)

        // 追加一条消息并推进修改时间：缓存应失效并重新解析。
        try Data(([header, user, assistant].joined(separator: "\n") + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 9_999)],
            ofItemAtPath: url.path
        )

        XCTAssertEqual(PiSessionFiles.summary(of: url)?.messageCount, 2)
    }

    // MARK: - Helpers

    private func writeSession(named name: String, lines: [String]) throws -> URL {
        let url = temporaryDirectory.appending(path: "\(name).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }
}
