# ADR-0006：持久化工具调用并渲染为卡片

[English](0006-tool-calls.md) · [简体中文](0006-tool-calls.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: 项目协作者

## Context

“实时查看工具调用过程”是本应用的核心卖点，但初版只有一个瞬时的「Running <tool>…」提示，
调用结束后信息就丢失了。pi 的实时事件现在已带足够信息：`tool_execution_start` 有 `args`，
`tool_execution_update` 有 `partialResult`，`tool_execution_end` 有 `result`、`isError`、
`durationMs`（pi `docs/json.md`）。历史会话里也有 `toolResult` 条目（pi `docs/session-format.md`）。

[ADR-0004](0004-domain-model.md) 特意把 `ToolCall` 推迟到事件模型出现之后。现在时机已到，
本 ADR 决定工具调用如何表示与渲染。

## Options

1. **把工具调用挂在 `Message` 上** —— 复用 `Message(role: .tool)`，再加 `toolName` / `arguments` /
   `isError` / `durationMs`。时间线单一，但让 `Message` 变成「字段联合体」，把两个概念混在一起。
2. **独立的 `ToolCall` 模型**（选中）—— 契合 `architecture.md` 的规划；`Message` 保持干净；
   视图按时间把两个数组合并成一条时间线。
3. **不持久化**（只留实时提示）—— 工作量最小，但回合结束后什么都没留下，重开会话全丢。

## Decision

选择 Option 2。新增 `ToolCall` SwiftData 模型，并让 agent 层承载其数据。

- **模型** —— `ToolCall`：`id`（UUID，唯一）、`toolCallID`（pi 的 id，用于关联事件）、`name`、
  `arguments`（紧凑文本）、`output`、`isError`、`durationMs`、`createdAt`，以及 `session`
  （级联删除，反向 `Session.toolCalls`）。
- **事件** —— `AgentEvent.toolCallStarted(id:name:arguments:)`、
  `.toolCallUpdated(id:output:)`、`.toolCallFinished(id:name:isError:durationMs:output:)`。
  `args` 解码为通用 `JSONValue` 再压成展示字符串，因为每种工具的参数结构都不同。
- **Store** —— `SessionStore` 在开始时创建 `ToolCall`，部分结果时更新 `output`，结束时定稿。
  用 `toolCallID → ToolCall` 索引支持并行工具调用；状态栏仍用实时的 `activeToolName`。
- **历史** —— `PiSessionFiles.toolCalls(in:)` 把每个 `toolResult` 条目映射为 `ToolCall`，
  重开会话时渲染同样的卡片。
- **UI** —— `ChatView` 按 `createdAt` 把消息与工具调用合并成一条时间线；`ToolCallCard` 展示
  名称、参数、状态、耗时与可折叠输出。

## Consequences

- schema 变更：新增一个实体与一个关系。属轻量迁移；应用**尚未发布**，一次性重置 store 也可接受。
  结构性变更仍需 `VersionedSchema` / `SchemaMigrationPlan`。
- 历史导入能得到工具**名称**与**输出**，但拿不到**参数**：`toolResult` 条目不携带参数，且尚未解析
  助手消息里的 `toolCall` 块。实时调用会显示参数。后续应解析这些块。
- 保留 `MessageRole.tool`，让既往导入的数据仍可解码，但新导入不再产生工具消息。
- 输出可能很大，目前整体存储、折叠展示。截断/上限列为后续工作。

## Related

- [ADR-0003](0003-pi-transport-and-sandbox.zh-CN.md) —— 传输与沙盒
- [ADR-0004](0004-domain-model.zh-CN.md) —— `Session` / `Message`
- [ADR-0005](0005-workspace-and-pi-sessions.zh-CN.md) —— 按工作目录组织会话
- [pi-agent.zh-CN.md](../pi-agent.zh-CN.md) —— 事件模型
