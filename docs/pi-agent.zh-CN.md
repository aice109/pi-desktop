# pi agent 集成

[English](pi-agent.md) · [简体中文](pi-agent.zh-CN.md)

本文件描述 PiDesktop 如何与 pi coding agent 对接。涉及 agent 逻辑时阅读。

> ⚠️ 集成细节随 pi 的实际接口演进而定；本文档记录**设计约束与目标形态**，具体协议以 pi 官方文档与源码为准。落地前请对照 pi 最新文档核实。

## 1. 角色

PiDesktop 是 pi agent 的 **GUI 前端**：

- pi 负责：模型调用、工具执行、会话编排。
- PiDesktop 负责：交互界面、事件可视化、上下文管理、持久化。

**UI 不直接调用模型/工具**，只消费 pi 产生的领域事件、发送用户意图。

## 2. 集成方式（待定，需 ADR 定稿）

候选：

| 方式 | 说明 | 取舍 |
| --- | --- | --- |
| 子进程 + 标准 IO 协议 | 由 App 启动 pi CLI，按行/JSON 通信 | 简单、复用现成 CLI；需管理进程生命周期 |
| 本地服务 / RPC | pi 以服务形式运行，App 通过 socket/HTTP 连接 | 松耦合；多一层服务管理 |
| 直接链接 SDK | 若 pi 提供 Swift/可嵌入 SDK | 最紧耦合；依赖可用性 |

> 最终方案确定后，**必须新增 ADR** 记录选择与理由，并回填本节。

## 3. 事件模型（目标）

Agent 层向上暴露领域事件（不泄漏传输格式）：

```swift
enum AgentEvent {
    case sessionStarted(id: SessionID)
    case messageDelta(id, text)          // 流式文本增量
    case messageCompleted(id, Message)
    case reasoningDelta(id, text)        // 思考过程（如暴露）
    case toolCallStarted(ToolCall)
    case toolCallOutput(ToolCallID, chunk)
    case toolCallFinished(ToolCallID, result, status)
    case turnFinished(usage)
    case error(AgentError)
}
```

规则：
- 传输格式 → 领域事件的映射集中在 `Core/Agent` 一层完成。
- 事件以 `AsyncStream`（或等价序列）向上游推送。
- 事件处理在 `@MainActor` 的 Store 中更新 UI 状态。

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

## 6. 安全与隐私

- 不在日志中记录敏感内容（密钥、完整文件内容）。
- 工作目录访问遵循用户授权范围。
- 若需沙盒/网络权限，修改 entitlements 需先征求用户同意。

## 7. 待办

- [ ] 确认 pi 通信协议 → 写 ADR
- [ ] 定义完整领域事件
- [ ] 实现 `Core/Agent` 抽象 + 一个具体实现
- [ ] 会话/消息 SwiftData 模型
- [ ] 流式渲染与工具卡片 UI
