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
        XCTAssertEqual(summary.messageCount, 3)
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

        let messages = PiSessionFiles.messages(in: url)
        XCTAssertEqual(messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(messages.map(\.text), ["Hello", "Hi there"])
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

    // MARK: - Helpers

    private func writeSession(named name: String, lines: [String]) throws -> URL {
        let url = temporaryDirectory.appending(path: "\(name).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }
}
