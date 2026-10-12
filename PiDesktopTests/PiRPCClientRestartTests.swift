//
//  PiRPCClientRestartTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest

@testable import PiDesktop

/// 子进程退出后传输仍可复用（回归：曾因未清理 `process` 而静默丢弃后续 prompt）。
///
/// 用一个「启动即退出」的假可执行文件验证，不依赖真实 pi。
final class PiRPCClientRestartTests: XCTestCase {
    func test_processExit_releasesProcessAndAllowsRestart() async throws {
        let fileManager = FileManager.default
        let counter = fileManager.temporaryDirectory.appending(path: "pi-restart-\(UUID().uuidString).txt")
        let script = fileManager.temporaryDirectory.appending(path: "fake-pi-\(UUID().uuidString).sh")
        // 每次启动追加一行再退出：行数即进程被拉起的次数。
        try "#!/bin/sh\necho run >> \"\(counter.path)\"\nexit 1\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        defer {
            try? fileManager.removeItem(at: script)
            try? fileManager.removeItem(at: counter)
        }

        let client = PiRPCClient(executable: script, workingDirectory: nil)
        let stream = await client.events()

        // 第一次启动：脚本立即退出，应收到传输失败。
        let failed = expectation(description: "failed")
        let collector = Task {
            for await event in stream {
                if case .failed = event {
                    failed.fulfill()
                    return
                }
            }
        }
        await fulfillment(of: [failed], timeout: 10)
        collector.cancel()

        // 进程退出后必须清理句柄，后续命令应能重新拉起进程（而非静默失败）。
        _ = await client.sessionState()

        // 子进程写文件是异步的，轮询等待第二次启动落盘。
        var runs = 0
        for _ in 0..<60 {
            runs = Self.lineCount(at: counter)
            if runs >= 2 { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        await client.shutdown()

        XCTAssertEqual(runs, 2, "进程退出后应能重新启动，而不是保留死进程引用")
    }

    private static func lineCount(at url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(whereSeparator: \.isNewline).count
    }
}
