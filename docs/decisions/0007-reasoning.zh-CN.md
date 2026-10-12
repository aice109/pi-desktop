# ADR-0007：持久化助手思考内容

[English](0007-reasoning.md) · [简体中文](0007-reasoning.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: 项目协作者

## Context

推理模型会通过 `thinking_delta` 事件流式输出思考内容，`ChatView` 在回合进行中已经显示可折叠的
「Reasoning」区。但这段文本只存在于内存中，回合结束（`agent_settled`）或重开会话后就丢失了。
pi 也会把思考以 `thinking` 内容块写入会话文件（pi `docs/message-types.md`），因此历史导入时数据是
可得的。

这是一次小的 schema 变更，按 [ADR-0004](0004-domain-model.md) 需要 ADR。

## Options

1. **给 `Message` 加 `thinking`（可选）**（选中）—— 思考属于某条助手消息；在既有模型上加一个可选
   字段是改动最小的做法，导入也自然。
2. **独立的 `Reasoning` 模型** —— 与 `ToolCall` 对称，但思考与助手消息一一对应、不需要独立时间线，
   属过度设计。
3. **只保留实时展示** —— 无 schema 变更，但内容会丢失，正是要解决的问题。

## Decision

选择 Option 1。新增 `Message.thinking: String?`。

- `SessionStore` 在流式时已累积 `thinkingDelta`；在 `assistantMessageCompleted` 时把累积文本写入消息。
  现在只要助手消息**有正文或有思考**就保留（此前仅有思考的回复会因正文为空被当作占位删除）。
- 历史导入解析助手 `thinking` 块（`MessageContentDTO.joinedThinking`）写入 `Message.thinking`。
- `ChatView` 对任何带思考的助手消息渲染可折叠的「Reasoning」区，与实时指示共用同一组件。

## Consequences

- schema 变更：`Message` 增加一个可选字段。新增可选属性属轻量迁移；应用**尚未发布**，一次性重置 store
  也可接受。
- `Message` 不再严格「只有正文」；`thinking` 是推理元数据，永远不会回传给模型（会话状态由 pi 掌管，
  这里仅用于展示）。
- 刻意**不**保存 `thinkingSignature`（provider 的重放数据）：它是不透明的，展示也用不到。
- 超长思考整体存储、折叠展示；截断列为后续工作。

## Related

- [ADR-0004](0004-domain-model.zh-CN.md) —— `Session` / `Message`
- [ADR-0006](0006-tool-calls.zh-CN.md) —— 工具调用（丰富渲染的另一半）
- [pi-agent.zh-CN.md](../pi-agent.zh-CN.md) —— 事件模型
