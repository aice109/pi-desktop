//
//  PiSessionFiles.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 只读解析 pi 的会话文件。
///
/// pi 按**工作目录**分组保存会话（见 pi `docs/session-format.md`）：
/// `~/.pi/agent/sessions/--<path>--/<timestamp>_<session-id>.jsonl`。
/// 本类型只负责定位与解析；真正续聊、写入由 `PiRPCClient` 完成。
nonisolated enum PiSessionFiles {

    // MARK: - 定位

    /// 会话根目录：`PI_CODING_AGENT_SESSION_DIR` 优先，否则 `~/.pi/agent/sessions`。
    static func defaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: String = NSHomeDirectory()
    ) -> URL {
        if let override = environment["PI_CODING_AGENT_SESSION_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return URL(fileURLWithPath: home, isDirectory: true)
            .appending(path: ".pi/agent/sessions", directoryHint: .isDirectory)
    }

    /// 把工作目录路径编码为 pi 的分组目录名（pi `docs/session-format.md`）。
    ///
    /// 规则：去掉前导分隔符，把 `/`、`\`、`:` 替换为 `-`，整体再包在 `--` 之间。
    /// 例如 `/Users/me/Proj` → `--Users-me-Proj--`。
    static func directoryName(for path: String) -> String {
        var trimmed = path
        while trimmed.hasPrefix("/") || trimmed.hasPrefix("\\") {
            trimmed.removeFirst()
        }
        let body = trimmed.map { character -> Character in
            switch character {
            case "/", "\\", ":": return "-"
            default: return character
            }
        }
        return "--\(String(body))--"
    }

    /// 某个工作目录对应的会话目录。
    static func sessionsDirectory(forWorkingDirectory path: String, root: URL = defaultRoot()) -> URL {
        root.appending(path: directoryName(for: path), directoryHint: .isDirectory)
    }

    // MARK: - 列表

    /// 列出会话摘要，按最近修改时间倒序；无法解析的文件被跳过。
    static func summaries(in directory: URL) -> [PiSessionSummary] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let contents else { return [] }
        return contents
            .filter { $0.pathExtension == "jsonl" }
            .compactMap(summary(of:))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// 解析单个会话文件的摘要；文件不是有效的 pi 会话时返回 `nil`。
    static func summary(of fileURL: URL) -> PiSessionSummary? {
        guard let lines = readLines(fileURL),
              let firstLine = lines.first,
              let header = try? JSONDecoder().decode(Header.self, from: Data(firstLine.utf8)),
              header.type == "session"
        else { return nil }

        var name: String?
        var preview: String?
        var messageCount = 0

        for line in lines.dropFirst() {
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)) else { continue }
            switch entry.type {
            case "session_info":
                if let entryName = entry.name { name = entryName }
            case "message":
                guard let message = entry.message, let role = displayRole(for: message.role) else { continue }
                let text = message.content?.joinedText ?? ""
                guard !text.isEmpty else { continue }
                messageCount += 1
                if preview == nil, role == .user {
                    preview = Self.preview(from: text)
                }
            default:
                continue
            }
        }

        return PiSessionSummary(
            sessionID: header.id ?? fileURL.deletingPathExtension().lastPathComponent,
            fileURL: fileURL,
            name: name,
            cwd: header.cwd ?? "",
            startedAt: header.timestamp.flatMap(parseDate),
            updatedAt: modificationDate(of: fileURL),
            messageCount: messageCount,
            preview: preview
        )
    }

    // MARK: - 消息

    /// 解析会话文件里的可展示消息（user / assistant），保持文件顺序。
    static func messages(in fileURL: URL) -> [PiDisplayMessage] {
        guard let lines = readLines(fileURL) else { return [] }
        var result: [PiDisplayMessage] = []
        for line in lines {
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)),
                  entry.type == "message",
                  let message = entry.message,
                  let role = displayRole(for: message.role)
            else { continue }
            let text = message.content?.joinedText ?? ""
            guard !text.isEmpty else { continue }
            result.append(PiDisplayMessage(
                role: role,
                text: text,
                timestamp: entry.timestamp.flatMap(parseDate) ?? .now
            ))
        }
        return result
    }

    /// 解析会话文件里的工具调用（`toolResult` 条目），保持文件顺序。
    static func toolCalls(in fileURL: URL) -> [PiStoredToolCall] {
        guard let lines = readLines(fileURL) else { return [] }
        var result: [PiStoredToolCall] = []
        for line in lines {
            guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(line.utf8)),
                  entry.type == "message",
                  let message = entry.message,
                  message.role == "toolResult"
            else { continue }
            result.append(PiStoredToolCall(
                toolCallID: message.toolCallId ?? UUID().uuidString,
                name: message.toolName ?? "tool",
                output: message.content?.joinedText ?? "",
                isError: message.isError ?? false,
                timestamp: entry.timestamp.flatMap(parseDate) ?? .now
            ))
        }
        return result
    }

    // MARK: - 解码辅助

    /// 会话文件头部（第一行）。
    private struct Header: Decodable {
        var type: String
        var id: String?
        var timestamp: String?
        var cwd: String?
    }

    /// 树中的一条 entry；只解出列表/展示需要的字段，其余忽略。
    private struct Entry: Decodable {
        var type: String
        var timestamp: String?
        var name: String?
        var message: EntryMessage?
    }

    private struct EntryMessage: Decodable {
        var role: String
        /// 内容可能是字符串（system）或内容块数组（user/assistant/toolResult），复用 RPC 的解码。
        var content: MessageContentDTO?
        var toolCallId: String?
        var toolName: String?
        var isError: Bool?
    }

    /// 会话文件里的角色 → 领域角色；工具结果单独解析为 `PiStoredToolCall`。
    private static func displayRole(for role: String) -> MessageRole? {
        switch role {
        case "user": return .user
        case "assistant": return .assistant
        default: return nil
        }
    }

    /// 把首条用户消息压成单行预览并截断。
    private static func preview(from text: String, limit: Int = 140) -> String? {
        let collapsed = text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }

    private static func readLines(_ fileURL: URL) -> [Substring]? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)
        else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    private static func modificationDate(of fileURL: URL) -> Date {
        (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            ?? .distantPast
    }

    /// 解析 ISO 8601 时间戳；pi 可能带也可能不带小数秒。
    private static func parseDate(_ string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(string)
    }
}
