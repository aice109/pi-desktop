//
//  PiRPCClient.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 通过子进程运行 `pi --mode rpc` 并对话的传输实现（ADR-0003）。
///
/// 协议：stdin 写 JSONL 命令、stdout 读 JSONL 响应/事件，stderr 仅作诊断。
/// 见 pi 官方 `docs/rpc.md`、`docs/json.md`。
actor PiRPCClient: AgentTransport {
    private let executableOverride: URL?
    private let workingDirectory: URL?
    private let additionalArguments: [String]

    private var process: Process?
    private var stdinHandle: FileHandle?
    /// 必须持有 Pipe（而非仅 FileHandle）：Pipe 释放会关闭其 fd，导致读取提前结束。
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readTask: Task<Void, Never>?
    private var eventContinuation: AsyncStream<AgentEvent>.Continuation?
    private var pending: [String: CheckedContinuation<RPCRecord?, Never>] = [:]
    private var requestCounter = 0

    /// - Parameters:
    ///   - executable: 覆盖 pi 路径；nil 时按 `PiExecutable` 自动定位。
    ///   - workingDirectory: pi 的工作目录（会话绑定的项目目录）。
    ///   - sessionPath: 续聊已有会话时传入其文件路径；nil 时由 pi 新建并持久化一个会话。
    ///   - additionalArguments: 追加的 CLI 参数（如 `--no-session` 用于临时会话）。
    init(
        executable: URL? = nil,
        workingDirectory: URL?,
        sessionPath: String? = nil,
        additionalArguments: [String] = []
    ) {
        self.executableOverride = executable
        self.workingDirectory = workingDirectory
        if let sessionPath {
            self.additionalArguments = ["--session", sessionPath] + additionalArguments
        } else {
            self.additionalArguments = additionalArguments
        }
    }

    // MARK: - AgentTransport

    func events() -> AsyncStream<AgentEvent> {
        let (stream, continuation) = AsyncStream<AgentEvent>.makeStream(bufferingPolicy: .unbounded)
        eventContinuation = continuation
        do {
            try startProcessIfNeeded()
        } catch {
            continuation.yield(.failed(error.localizedDescription))
        }
        return stream
    }

    func prompt(_ message: String) async throws {
        try startProcessIfNeeded()
        let response = await send(["type": "prompt", "message": message])
        if response?.success == false {
            throw AgentTransportError.commandFailed(response?.error ?? "unknown")
        }
    }

    func abort() async {
        _ = await send(["type": "abort"])
    }

    func sessionState() async -> AgentSessionState? {
        guard let record = await command(["type": "get_state"]), let data = record.data else { return nil }
        let levels = await availableThinkingLevels()
        return AgentSessionState(
            model: data.model?.domain,
            thinkingLevel: data.thinkingLevel,
            availableThinkingLevels: levels,
            sessionFile: data.sessionFile,
            sessionId: data.sessionId,
            sessionName: data.sessionName,
            isStreaming: data.isStreaming ?? false
        )
    }

    func availableModels() async -> [AgentModel] {
        guard let record = await command(["type": "get_available_models"]) else { return [] }
        return (record.data?.models ?? []).map(\.domain)
    }

    func setModel(_ model: AgentModel) async -> Bool {
        await command(["type": "set_model", "provider": model.provider, "modelId": model.id]) != nil
    }

    func setThinkingLevel(_ level: String) async -> Bool {
        await command(["type": "set_thinking_level", "level": level]) != nil
    }

    func setSessionName(_ name: String) async -> Bool {
        await command(["type": "set_session_name", "name": name]) != nil
    }

    func sessionStats() async -> AgentUsage? {
        guard let record = await command(["type": "get_session_stats"]), let data = record.data else {
            return nil
        }
        let tokens = data.tokens
        return AgentUsage(
            inputTokens: tokens?.input ?? 0,
            outputTokens: tokens?.output ?? 0,
            cacheReadTokens: tokens?.cacheRead ?? 0,
            cacheWriteTokens: tokens?.cacheWrite ?? 0,
            totalTokens: tokens?.total ?? 0,
            costUSD: data.cost ?? 0,
            contextTokens: data.contextUsage?.tokens,
            contextWindow: data.contextUsage?.contextWindow,
            contextPercent: data.contextUsage?.percent
        )
    }

    private func availableThinkingLevels() async -> [String] {
        (await command(["type": "get_available_thinking_levels"]))?.data?.levels ?? []
    }

    /// 发送一条命令并等待其响应；失败返回 nil。
    private func command(_ object: [String: Any]) async -> RPCRecord? {
        do {
            try startProcessIfNeeded()
        } catch {
            return nil
        }
        guard let response = await send(object), response.success != false else { return nil }
        return response
    }

    func shutdown() async {
        readTask?.cancel()
        readTask = nil
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinHandle?.close()
        stdinHandle = nil
        process?.terminate()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        eventContinuation?.finish()
        eventContinuation = nil
        resumePending(with: nil)
    }

    // MARK: - Process lifecycle

    private func startProcessIfNeeded() throws {
        guard process == nil else { return }
        guard let executable = executableOverride ?? PiExecutable.locate() else {
            throw AgentTransportError.executableNotFound
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--mode", "rpc"] + additionalArguments
        process.environment = PiExecutable.childEnvironment()
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { await self?.handleTermination(status: status) }
        }

        do {
            try process.run()
        } catch {
            throw AgentTransportError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdinPipe = stdinPipe
        self.stdoutPipe = stdoutPipe
        self.stderrPipe = stderrPipe
        self.stdinHandle = stdinPipe.fileHandleForWriting
        startReading(stdoutPipe.fileHandleForReading)
        discard(stderrPipe.fileHandleForReading)
    }

    private func handleTermination(status: Int32) {
        yield(.failed("pi 进程已退出（status \(status)）"))
        resumePending(with: nil)
    }

    // MARK: - Reading

    /// 读取 stdout 并按 LF 切分。
    ///
    /// 用 `readabilityHandler`（而非 `FileHandle.bytes`）：后者在管道上不可靠，
    /// 只吐出第一段数据后就静默停止。刻意不用 `lines`：它会把 `U+2028/U+2029`
    /// 误当记录边界，而这些字符在 JSON 字符串内合法（见 pi `docs/rpc.md`）。
    private func startReading(_ handle: FileHandle) {
        readTask = Task { [weak self] in
            var buffer = Data()
            for await chunk in Self.byteStream(from: handle) {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[buffer.startIndex..<newline])
                    buffer.removeSubrange(buffer.startIndex...newline)
                    if !line.isEmpty { await self?.consume(line) }
                }
            }
            await self?.yield(.failed("pi 的 stdout 已关闭"))
        }
    }

    /// 把 `FileHandle` 的可用数据桥接为 `AsyncStream`（`readabilityHandler` 版本）。
    nonisolated private static func byteStream(from handle: FileHandle) -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { _ in
                handle.readabilityHandler = nil
            }
        }
    }

    /// 持续消费 stderr，避免管道写满阻塞 pi；内容不参与协议。
    private func discard(_ handle: FileHandle) {
        handle.readabilityHandler = { handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
            }
        }
    }

    private func consume(_ line: Data) {
        guard let record = RPCProtocol.decode(line) else {
            // 解码失败也必须归还对应请求，否则调用方会永久挂起（例如 pi 改了字段类型）。
            if let id = Self.responseID(in: line), let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: nil)
            }
            return
        }
        if record.type == "response" {
            if let id = record.id, let continuation = pending.removeValue(forKey: id) {
                continuation.resume(returning: record)
            }
            return
        }
        if let event = RPCProtocol.agentEvent(from: record) {
            yield(event)
        }
    }

    /// 在类型化解码失败时，仍尽量从报文里取出响应 id。
    nonisolated private static func responseID(in line: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "response"
        else { return nil }
        return object["id"] as? String
    }

    // MARK: - Writing

    private func send(_ object: [String: Any]) async -> RPCRecord? {
        guard let stdin = stdinHandle else { return nil }
        requestCounter += 1
        let id = "req-\(requestCounter)"
        var payload = object
        payload["id"] = id
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }

        return await withCheckedContinuation { (continuation: CheckedContinuation<RPCRecord?, Never>) in
            pending[id] = continuation
            do {
                try stdin.write(contentsOf: data)
                try stdin.write(contentsOf: Data([0x0A]))
            } catch {
                pending.removeValue(forKey: id)
                continuation.resume(returning: nil)
            }
        }
    }

    private func resumePending(with record: RPCRecord?) {
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(returning: record) }
    }

    private func yield(_ event: AgentEvent) {
        eventContinuation?.yield(event)
    }
}

/// 定位可执行的 `pi`。按 PATH 与常见安装位置查找，可用 `PI_EXECUTABLE` 覆盖。
nonisolated enum PiExecutable {
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let fileManager = FileManager.default

        if let override = environment["PI_EXECUTABLE"], fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        var candidates: [String] = []
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/pi" })
        }
        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            "\(home)/.pi/agent/bin/pi",
            "/opt/homebrew/bin/pi",
            "/usr/local/bin/pi",
            "/usr/bin/pi",
        ])

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    /// 构造子进程环境：给 `PATH` 补充常见 Node/工具安装位置。
    ///
    /// GUI App 从 Finder/测试宿主启动时 `PATH` 很精简，而 pi 的启动脚本
    /// `exec` 的是 `#!/usr/bin/env node`，找不到 `node` 会以 status 127 退出。
    static func childEnvironment(
        base: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> [String: String] {
        var environment = base
        // 去掉注入类变量：测试宿主会设置 DYLD_INSERT_LIBRARIES / XCTest 变量，
        // 传给 node 子进程会导致启动异常。生产环境一般没有这些，清除后更干净。
        for key in Array(environment.keys)
        where key.hasPrefix("DYLD_") || key.hasPrefix("XCTest") || key.hasPrefix("XCInject") {
            environment[key] = nil
        }
        let dataHome = base["XDG_DATA_HOME"] ?? "\(home)/.local/share"
        let candidates = [
            "\(dataHome)/pi-node/current/bin",
            "\(home)/.volta/bin",
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var entries = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        for candidate in candidates where !entries.contains(candidate) {
            entries.append(candidate)
        }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }
}
