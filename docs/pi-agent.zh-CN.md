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
- **会话。** pi 按工作目录在磁盘上分组保存会话。应用只读列出 `~/.pi/agent/sessions/--<工作区>--/`
  （`Core/Pi`），并用 `--session <path>` 续聊所选会话；新建会话交由 pi 持久化，其文件路径从 `get_state` 回读。
  见 [ADR-0005](decisions/0005-workspace-and-pi-sessions.zh-CN.md)。

线格式参考：pi 文档 `docs/rpc.md`、`docs/rpc-commands.md`、`docs/json.md`、`docs/message-types.md`。

## 3. 事件模型

已在 `Core/Agent/AgentEvent.swift` 实现；「线格式 → 领域事件」映射集中在 `RPCProtocol`，
因此 `Core/Agent` 之上不会看到传输格式：

```swift
enum AgentEvent: Sendable, Equatable {
    case agentStarted
    case textDelta(String)               // 流式助手文本
    case thinkingDelta(String)           // 思考过程（如暴露）
    case toolCallStarted(id: String, name: String, arguments: String?)
    case toolCallUpdated(id: String, output: String)
    case toolCallFinished(id: String, name: String, isError: Bool, durationMs: Int?, output: String?)
    case assistantMessageCompleted(text: String, stopReason: String?, errorMessage: String?)
    case retryStarted(attempt: Int, maxAttempts: Int)
    case retryFinished(success: Bool)
    case compactionStarted
    case compactionFinished(aborted: Bool, errorMessage: String?)
    case settled(aborted: Bool)          // agent_settled：不再有自动工作
    case failed(String)                  // 传输失败
}
```

规则：
- 「线记录 → 领域事件」的映射只在 `Core/Agent` 完成。
- 事件以 `AsyncStream` 向上推送。
- 事件在 `@MainActor` 的 Store（`SessionStore`）中更新 UI 状态。

不是事件：用量/费用通过 `sessionStats` 按需读取；工具调用持久化为 `ToolCall`
（[ADR-0006](decisions/0006-tool-calls.zh-CN.md)）；助手思考持久化在 `Message.thinking`
（[ADR-0007](decisions/0007-reasoning.zh-CN.md)）。

## 4. 会话生命周期

```
创建/恢复会话 → 启动或连接 agent → 发送用户输入
      → 接收事件流（增量渲染）→ 回合结束 → 可继续或中断
      → 持久化到 SwiftData → 结束/关闭
```

需要处理：启动失败、连接中断、用户中断、超时、并发回合、会话恢复。

`prompt` 响应带有 `disposition`：`started` 启动一次运行，`queued` 进入待处理队列，`handled` 表示
被扩展命令或输入处理器立即消费——不会启动运行，也就不会再有 `agent_settled`，客户端必须自行收尾
（`AgentTransport.prompt` 因此返回 `PromptDisposition`）。

`get_entries` 返回的是**追加式树**；历史会从响应的 `leafId` 沿 `parentId` 回溯活动分支，因此不会把被
遗弃的分支混成一条线。工具栏 Branch 菜单提供 `fork` / `clone`，二者完成后都会重读 `get_state` 取新会话
文件并全量校准。

打开时会与 pi 校准本地镜像（`get_entries`；无进程运行时回退到会话文件），因此应用外产生的回合也会
出现（[ADR-0009](decisions/0009-history-sync.zh-CN.md)）。解码必须容忍 pi 消息**缺少** `content` 或为
`null`：把这类字段当必填会让整条响应失败、静默得到空历史。

## 5. UI 映射（对应视图）

| 领域事件 | UI 呈现 |
| --- | --- |
| `textDelta` / `assistantMessageCompleted` | 流式文本追加 + Markdown 渲染 |
| `thinkingDelta` | 可折叠的思考区（实时） |
| `toolCallStarted` | 工具调用卡片（运行中） |
| `toolCallUpdated` | 卡片内实时输出 |
| `toolCallFinished` | 卡片标记成功/失败 + 耗时 |
| `retryStarted` / `compactionStarted` | 状态栏显示「Retrying (n/m)…」/「Compacting context…」|
| `failed` | 内联错误提示 |

呈现遵循 [design-system.zh-CN.md](design-system.zh-CN.md)（原生组件 + 玻璃）。工具调用会持久化并渲染为
卡片（见 [ADR-0006](decisions/0006-tool-calls.zh-CN.md)）。

事件模型（领域事件，见 `Core/Agent/AgentEvent.swift`）还包括：`queueUpdated`（待处理队列）、
`sessionInfoChanged` / `thinkingLevelChanged`（外部改动同步）、`summarizationRetry*`（摘要重试）、
`entryAppended`（会话树被外部追加，空闲时重新校准镜像）。

输入框中以 `!` 开头的命令会直接执行 pi 的 `bash`，输出作为工具消息进入时间线（并进入模型上下文）；
执行中可通过 `abort_bash` 中止。

Chat 菜单可循环切换模型（`cycle_model`）与思考等级（`cycle_thinking_level`），并复制最后一条助手回复
（`get_last_assistant_text`）。`get_messages` 与 `new_session` 未使用：前者被 `get_entries` 取代，后者
由「新进程 + 本地 Session」替代。

会话可从 File 菜单导出为独立 HTML 文件（`export_html`）；应用用保存面板选路径并作为 `outputPath` 传入。

上下文可手动压缩（`compact`，可带 `customInstructions`），自动压缩按会话开关（`set_auto_compaction`），
二者都在工具栏的 Context 菜单里；自动重试也在此开关（`set_auto_retry`），进行中的重试可从状态行中止
（`abort_retry`）。pi 不在 `get_state` 里报告自动重试开关，故应用在本地跟踪（默认开启）。

可发现的命令（扩展命令、prompt 模板、技能）用 `get_commands` 列出，通过 `prompt` 发送 `/name` 执行；
输入以 `/` 开头时输入框会给出建议。

`prompt` / `steer` / `follow_up` 接受 `images`（`ImageContent`：base64 + mimeType）；用户消息会渲染其
图片，历史也会导入 `image` 块（[ADR-0010](decisions/0010-image-attachments.zh-CN.md)）。

当前实时可用：流式助手文本（Markdown）、思考区（实时 + 持久化）、工具调用卡片、图片附件。pi 进程退出时，
传输层会释放句柄并在下一条命令时重新拉起；被打断的回合仍不会自动重试。

## 6. 安全与隐私

- 不在日志中记录敏感内容（密钥、完整文件内容）。
- 工作目录访问遵循用户授权范围。
- 若需沙盒/网络权限，修改 entitlements 需先征求用户同意。

## 7. 待办

- [x] 确认 pi 通信协议 → ADR-0003
- [x] `Core/Agent` 抽象（`AgentTransport`）+ `PiRPCClient`
- [x] 会话/消息 SwiftData 模型（ADR-0004）
- [x] 流式助手文本渲染
- [x] 按工作区列出 pi 会话并续聊（ADR-0005）
- [x] 持久化工具调用并渲染为卡片（ADR-0006）
- [x] 模型 / 思考等级选择、用量与费用展示
- [x] 解析助手 `toolCall` 块，让历史也显示工具参数
- [x] 重命名会话（删除即移至废纸篓）
- [x] 持久化助手思考内容（ADR-0007）
- [x] 用 `get_entries` 的 `since` 游标做增量历史同步
- [x] 分支感知的历史（`leafId`/`parentId`）与 `fork` / `clone`
- [x] 会话树总览（`get_tree`），可从节点 fork
- [ ] 进程退出后自动重试被打断的回合
