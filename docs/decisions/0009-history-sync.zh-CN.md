# ADR-0009：用 pi 历史校准本地镜像

[English](0009-history-sync.md) · [简体中文](0009-history-sync.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: 项目协作者

## Context

ADR-0005 把 pi 磁盘上的会话作为会话列表来源，并把打开的会话镜像为本地 `Session`。但镜像只在**首次
打开时**从会话文件填充一次，之后再不刷新；于是在应用之外改动的会话（在终端里续聊、发生压缩、其他
客户端）永远看不到。重新打开会话可能一直显示过期历史。

## Options

1. **保持一次性导入** —— 最简单，但在任何外部改动后就静默错误。
2. **每次打开都重读会话文件** —— 对文件路径是正确的，但看不到 pi 中尚未落盘的进行中内容，
   而且在 pi 内存里已有答案时仍反复解析可能很大的文件。
3. **打开时经 RPC 与 pi 校准**（选中）—— 向 pi 索要条目并重建镜像。

对方案 3，pi 提供两条命令：

- `get_messages` 返回**当前 LLM 上下文**：压缩后压缩前的回合就消失了，无法代表用户看过的内容。
- `get_entries` 返回整棵追加式树（含压缩前历史与遗弃分支），条目带稳定 id 与时间戳，并支持
  `since` 游标。

## Decision

选择方案 3，并把方案 2 作为离线回退。

- `AgentTransport.sessionEntries()` 封装 `get_entries`（暂不用游标）；传输层只提供 DTO
  （`SessionEntryDTO`），由 `Core/Pi` 经**同一个** `PiHistory.make(from:)` 映射成 `PiHistory`——
  与会话文件解析共用一套映射，一个映射、两个来源。
- `SessionStore.syncHistory(for:)` 在 `activate` 中调用：**先**用会话文件（快，无需等待 pi 进程），
  **再**用 `get_entries` 补齐文件尚未看到的内容。用 `PiHistoryFingerprint`（条数 + 末条消息文本 +
  末个工具调用 id）在内容未变时跳过重建，避免切换会话时频繁替换 `Message` 对象。
- 重建会整体替换镜像的消息与工具调用。这是安全的：本地每条消息与工具调用都源自 pi，
  `Message`/`ToolCall` 里没有仅属于本地、会因此丢失的数据。流式回合进行中会跳过重建，
  以免抹掉正在进行的内容。

## Consequences

- 重新打开会话会收敛到 pi 的真实状态，包括在应用外产生的回合。
- `SessionStore` 依赖 `Core/Pi`（作为粘合层）；`Core/Pi` 仍只依赖 `Core/Agent` 的 DTO，
  依赖方向保持无环。
- 重建会改变 `Message.id`。每次真实变化会让 SwiftUI 列表标识抖动一次；指纹保证常见路径
  （无变化）完全不变。
- 解码容错很重要：`get_entries` 的消息可能**缺少** `content` 键或为 `null`（`system`、
  `bashExecution`）。把这类字段当必填会让**整条**响应解码失败、静默得到空历史，因此
  `MessageDTO.content` 与 `MessageContentDTO` 同时接受两种形态。
- 将来可用 `get_entries` 的 `since` 游标做增量同步；id 已经拿到，只是尚未持久化。

## Related

- [ADR-0005](0005-workspace-and-pi-sessions.zh-CN.md) —— 工作区隔离与会话列表来源
- [ADR-0004](0004-domain-model.zh-CN.md) —— `Session` / `Message`
- [ADR-0006](0006-tool-calls.zh-CN.md) —— `ToolCall`
