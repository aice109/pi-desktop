# pi agent 集成

[English](pi-agent.md) · [简体中文](pi-agent.zh-CN.md)

本文件描述 PiDesktop 如何与 pi coding agent 对接。涉及 agent 逻辑时阅读。

> 集成遵循 pi 官方 RPC 接口（见 [ADR-0003](decisions/0003-pi-transport-and-sandbox.zh-CN.md)）。
> 具体线格式见 pi 文档（`rpc.md`、`rpc-commands.md`、`json.md`、`message-types.md`）；扩展时请对照已安装的 pi 版本核实。

## 1. 角色

PiDesktop 是 pi agent 的 **GUI 前端**：

- pi 负责：模型调用、工具执行、会话编排。
- PiDesktop 负责：交互界面、事件可视化、上下文管理、持久化。

**UI 不直接调用模型/工具**，只消费 pi 产生的领域事件、发送用户意图。

## 2. 集成方式

已在 [ADR-0003](decisions/0003-pi-transport-and-sandbox.zh-CN.md) 定稿：**子进程 + RPC**
（`pi --mode rpc`），并关闭 App Sandbox。

- PiDesktop 以子进程启动 `pi --mode rpc --no-session`；每个会话一个客户端，子进程工作目录设为该会话的 `workingDirectory`。
- stdin 写命令（按行 JSON）；stdout 读响应与会话事件（NDJSON）；stderr 仅作诊断。
- `Core/Agent/PiRPCClient` 负责进程与「记录 → 领域事件」映射；`Core/Agent/RPCRecords` 负责线格式解码。
- pi 的定位顺序为 `PI_EXECUTABLE` → `PATH` → 常见安装路径；并给子进程补充 `PATH`，使 `#!/usr/bin/env node` 启动器能找到 Node。

线格式参考：pi 文档 `docs/rpc.md`、`docs/rpc-commands.md`、`docs/json.md`、`docs/message-types.md`。

## 3. 事件模型

已在 `Core/Agent/AgentEvent.swift` 实现；「线格式 → 领域事件」映射集中在 `RPCProtocol`，
因此 `Core/Agent` 之上不会看到传输格式：

```swift
enum AgentEvent: Sendable, Equatable {
    case agentStarted
    case textDelta(String)               // 流式助手文本
    case thinkingDelta(String)           // 思考过程（如暴露）
    case toolCallStarted(id: String, name: String)
    case toolCallFinished(id: String, name: String, isError: Bool, durationMs: Int?)
    case assistantMessageCompleted(text: String, stopReason: String?, errorMessage: String?)
    case settled(aborted: Bool)          // agent_settled：不再有自动工作
    case failed(String)                  // 传输失败
}
```

规则：
- 「线记录 → 领域事件」的映射只在 `Core/Agent` 完成。
- 事件以 `AsyncStream` 向上推送。
- 事件在 `@MainActor` 的 Store（`SessionStore`）中更新 UI 状态。

尚未建模：token 用量/费用、已持久化的工具调用（见 §7）。

## 4. 会话生命周期

```
创建/恢复会话 → 启动或连接 agent → 发送用户输入
      → 接收事件流（增量渲染）→ 回合结束 → 可继续或中断
      → 持久化到 SwiftData → 结束/关闭
```

需要处理：启动失败、连接中断、用户中断、超时、并发回合、会话恢复。

## 5. UI 映射（对应视图）

| 领域事件 | UI 呈现 |
| --- | --- |
| `messageDelta` | 流式气泡/文本追加 |
| `reasoningDelta` | 可折叠的思考区 |
| `toolCallStarted` | 工具调用卡片（进行中） |
| `toolCallOutput` | 卡片内实时输出 |
| `toolCallFinished` | 卡片标记成功/失败 + 耗时 |
| `error` | 内联错误提示，可重试 |

呈现遵循 [design-system.zh-CN.md](design-system.zh-CN.md)（原生组件 + 玻璃）。

当前已实现：流式助手文本（`textDelta` / `assistantMessageCompleted`）与瞬时的「工具运行中」提示。
思考区、工具卡片、错误重试待实现。

## 6. 安全与隐私

- 不在日志中记录敏感内容（密钥、完整文件内容）。
- 工作目录访问遵循用户授权范围。
- 若需沙盒/网络权限，修改 entitlements 需先征求用户同意。

## 7. 待办

- [x] 确认 pi 通信协议 → ADR-0003
- [x] `Core/Agent` 抽象（`AgentTransport`）+ `PiRPCClient`
- [x] 会话/消息 SwiftData 模型（ADR-0004）
- [x] 流式助手文本渲染
- [ ] 持久化工具调用（`ToolCall` 模型 + 卡片）—— 需新增 ADR
- [ ] 模型 / 思考等级选择、用量与费用展示
- [ ] 会话恢复 + `get_messages` 同步、错误重试、思考区
