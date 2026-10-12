# ADR-0008：应用偏好存放于 UserDefaults

[English](0008-app-settings.md) · [简体中文](0008-app-settings.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: 项目协作者

## Context

PiDesktop 需要用户偏好（外观、启动时是否恢复上次会话、是否显示用量底栏、删除会话前是否确认）。
项目已用 SwiftData 持久化领域数据（`Session` / `Message` / `ToolCall`，见
[ADR-0004](0004-domain-model.zh-CN.md)、[ADR-0006](0006-tool-calls.zh-CN.md)），因此第一反应可能是
再加一个 `@Model`。

偏好与领域数据不同：它是全局唯一、扁平的单条配置，没有关系、没有查询、不需要历史。而且它必须在
`App.init` 阶段、`ModelContainer` 就绪之前就能读取（首个窗口构建时就要知道外观）。

## Options

1. **SwiftData `AppSettings` 模型** —— 与现有持久化一致，但为了四个布尔值引入 schema 变更/迁移，
   并把容器依赖带进启动流程；而且 SwiftData 并不提供「单行」约定，仍要自己保证。
2. **基于 `UserDefaults` 的 `@Observable` store**（选中）—— 偏好本就是 macOS 的 `NSUserDefaults`
   的用途；无 schema、无迁移、可在容器之前使用，用自定义 suite 即可轻松测试。
3. **Application Support 下的 JSON 文件** —— 自行实现持久化与序列化，只有结构化、带版本的数据才值得。

## Decision

选择 Option 2。`AppSettingsStore`（`Core/Stores/AppSettingsStore.swift`）是 `@MainActor @Observable`
类，写穿到 `UserDefaults` 的 `settings.*` 键；通过 `SettingsView`（SwiftUI `Settings` scene，⌘, 可用）
与环境注入暴露给 UI。

偏好被刻意限定为 **UI / 客户端行为**。属于 agent 的东西（模型、思考等级、会话名、工具权限）仍保存在
pi 中并经 RPC 传输访问——PiDesktop 不为它们保留第二份事实来源（见
[ADR-0005](0005-workspace-and-pi-sessions.zh-CN.md)）。

## Consequences

- 偏好位于 SwiftData schema 之外；与会话相关的迁移永远不会影响偏好。
- `lastSessionPath`（用于恢复上次打开的会话）是一项偏好而非关系；打开会话时写入，文件不存在时忽略。
- `UserDefaults` 不是事务性的，但偏好都是幂等的单值，不存在写坏一半的问题。
- 测试用 `UserDefaults(suiteName:)` 获得干净 store，无需容器。

## Related

- [ADR-0004](0004-domain-model.zh-CN.md) —— SwiftData 领域模型
- [ADR-0005](0005-workspace-and-pi-sessions.zh-CN.md) —— 会话状态归 pi 所有
