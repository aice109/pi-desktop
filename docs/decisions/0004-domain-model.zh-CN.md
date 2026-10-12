# ADR-0004: SwiftData 领域模型（Session / Message）

[English](0004-domain-model.md) · [简体中文](0004-domain-model.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-12
- 决策者：项目协作者

## 背景

脚手架此前只有 Xcode 模板的 `Item` 模型。要构建会话列表与消息流，必须有真实领域模型。
[architecture.zh-CN.md](../architecture.zh-CN.md) 规划了 `Session`、`Message`、`ToolCall`、
`AppSettings`，并规定模型变更属重大改动、需先写 ADR。

[ADR-0003](0003-pi-transport-and-sandbox.zh-CN.md) 已选定子进程通信；后续的「通信格式 → 事件」
映射会写入这些模型。首个迭代只需要支撑「列出会话 → 打开会话 → 查看并追加消息」的最小集合。

## 候选方案

1. **保留单一扁平模型** —— 最省事，但无法清晰表达顺序与角色，是死路。
2. **`Session` + `Message` + 级联关系**（采用）—— 贴合领域，身份稳定，且支持后续增量追加。
3. **现在就加入 `ToolCall` + `AppSettings`** —— 目标模型完整，但过于超前：`ToolCall` 的形态
   依赖尚不存在的事件模型。

## 决策

采用方案 2。引入两个 SwiftData 模型：

- **`Session`** —— `id`（UUID，唯一）、`title`、`createdAt`、`updatedAt`、`workingDirectory?`、
  `status`（`active` / `archived`）、`messages`（级联删除，反向关系 `Message.session`）。
- **`Message`** —— `id`（UUID，唯一）、`role`（`user` / `assistant` / `tool`）、`content`、
  `createdAt`、`session`（反向关系）。

枚举以 `String` 原始值持久化（Codable），使新增枚值可对旧数据解码。
`Session.append(_:)` 追加消息并同步 `updatedAt`。`ToolCall` 与 `AppSettings` 待 ADR-0003 的事件
模型落地后由后续 ADR 补充。

## 影响

- 取代模板 `Item`；磁盘存储结构发生变化。应用**尚未发布**，一次性重置存储可接受，本期不提供迁移。
  未来 schema 变更必须使用 `VersionedSchema` + `SchemaMigrationPlan` 并新增 ADR。
- 模型为 nonisolated：已在 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` 下验证（`@Model` 类不会被
  强制到主 actor），因此后续可在后台 `ModelActor` 中使用而无需改动。
- 删除 `Session` 会级联删除其 `Message`。
- 领域 `id: UUID` 为 agent 层（ADR-0003 事件里的 `SessionID` / `MessageID`）提供独立于
  SwiftData `persistentModelID` 的稳定标识。

## 相关

- [architecture.zh-CN.md](../architecture.zh-CN.md) —— 模块布局与数据模型
- [pi-agent.zh-CN.md](../pi-agent.zh-CN.md) —— 将写入这些模型的事件模型
- [ADR-0003](0003-pi-transport-and-sandbox.zh-CN.md) —— 通信方式与沙盒
