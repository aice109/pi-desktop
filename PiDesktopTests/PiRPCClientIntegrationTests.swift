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

        let client = PiRPCClient(executable: executable, workingDirectory: nil)
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
}
