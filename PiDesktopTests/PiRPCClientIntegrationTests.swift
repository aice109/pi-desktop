//
//  PiRPCClientIntegrationTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
@testable import PiDesktop

/// 真实 `pi` 子进程的端到端验证。
///
/// 默认跳过：会真实调用模型、产生费用且依赖外部环境。设置 `PI_INTEGRATION_TESTS=1` 才运行。
final class PiRPCClientIntegrationTests: XCTestCase {
    func test_realPi_streamsAssistantTextAndSettles() async throws {
        // 触发方式：环境变量 PI_INTEGRATION_TESTS=1，或存在哨兵文件 /tmp/pi_integration_enabled。
        let environmentEnabled = ProcessInfo.processInfo.environment["PI_INTEGRATION_TESTS"] == "1"
        let sentinelEnabled = FileManager.default.fileExists(atPath: "/tmp/pi_integration_enabled")
        try XCTSkipUnless(
            environmentEnabled || sentinelEnabled,
            "设置 PI_INTEGRATION_TESTS=1（或创建 /tmp/pi_integration_enabled）以运行真实 pi 集成测试"
        )
        guard let executable = PiExecutable.locate() else {
            throw XCTSkip("未找到可执行的 pi")
        }

        let client = PiRPCClient(executable: executable, workingDirectory: nil, additionalArguments: ["--no-session"])
        let stream = await client.events()

        let settled = expectation(description: "agent_settled")
        let collector = Task { () -> String in
            var text = ""
            for await event in stream {
                switch event {
                case .textDelta(let delta):
                    text += delta
                case .settled:
                    settled.fulfill()
                    return text
                case .failed(let message):
                    XCTFail("传输失败：\(message)")
                    settled.fulfill()
                    return text
                default:
                    break
                }
            }
            return text
        }

        try await client.prompt("Reply with exactly one word: pong. Do not use any tools.")
        await fulfillment(of: [settled], timeout: 120)
        let text = await collector.value
        await client.shutdown()

        XCTAssertTrue(text.lowercased().contains("pong"), "实际收到：\(text)")
    }

    /// 验证 `get_entries` 能在真实 pi 上取回完整历史（历史同步的依据）。
    ///
    /// 用真实会话文件的**副本**，不修改用户数据。
    func test_realPi_getEntriesReturnsHistory() async throws {
        let environmentEnabled = ProcessInfo.processInfo.environment["PI_INTEGRATION_TESTS"] == "1"
        let sentinelEnabled = FileManager.default.fileExists(atPath: "/tmp/pi_integration_enabled")
        try XCTSkipUnless(environmentEnabled || sentinelEnabled, "需要 PI_INTEGRATION_TESTS=1")
        guard let executable = PiExecutable.locate() else {
            throw XCTSkip("未找到可执行的 pi")
        }
        guard let source = Self.anyExistingSessionFile() else {
            throw XCTSkip("会话目录里没有可用于测试的会话文件")
        }

        let copy = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).jsonl")
        try FileManager.default.copyItem(at: source, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }

        let client = PiRPCClient(executable: executable, workingDirectory: nil, sessionPath: copy.path)
        _ = await client.events()
        let entries = await client.sessionEntries()
        await client.shutdown()

        XCTAssertFalse(entries.isEmpty, "get_entries 应返回条目")
        let history = PiHistory.make(from: entries.map(\.historyEntry))
        XCTAssertFalse(history.messages.isEmpty, "历史里应有可展示消息")
    }

    /// 会话目录中的任意一个会话文件（用于只读验证）。
    private static func anyExistingSessionFile() -> URL? {
        let root = PiSessionFiles.defaultRoot()
        guard let groups = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        for group in groups {
            let files = (try? FileManager.default.contentsOfDirectory(at: group, includingPropertiesForKeys: nil))
                ?? []
            if let file = files.first(where: { $0.pathExtension == "jsonl" }) { return file }
        }
        return nil
    }
}
