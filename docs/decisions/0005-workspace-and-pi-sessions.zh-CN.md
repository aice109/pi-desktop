# ADR-0005：按工作目录组织 pi 会话

[English](0005-workspace-and-pi-sessions.md) · [简体中文](0005-workspace-and-pi-sessions.zh-CN.md)

- Status: Accepted
- Date: 2026-10-12
- Deciders: 项目协作者

## Context

此前应用只列出自己创建的会话，从不展示 pi 已经在磁盘上保存的会话。
pi 按**工作目录**分组保存会话
（`~/.pi/agent/sessions/--<path>--/<timestamp>_<id>.jsonl`，见 pi `docs/session-format.md`）。
用户期望**先选一个项目目录，再看到该目录的 pi 会话**，并继续其中一个。

需要回答两个问题：

1. 会话列表以谁为准？
2. 应用如何打开并继续一个 pi 会话？

ADR-0003 已定传输为子进程，ADR-0004 已定义 `Session` / `Message`。本 ADR 不推翻它们，只定义
pi 磁盘上的会话与本地模型的关系。

## Options

1. **只用应用自己的会话** —— 把 pi 的会话做成另一个只读视图。实现简单，但两套会话列表互相割裂，
   且都不权威。
2. **以 pi 磁盘上的会话为列表来源，打开时镜像到本地**（选中）。根据所选目录读取会话文件；打开时
   把历史导入本地 `Session`（以其会话文件为键），并用 `pi --session <path>` 继续。
3. **让 pi 成为唯一真源、去掉 SwiftData** —— 概念上最干净，但改动巨大，会废弃 ADR-0004，并失去
   任何本地缓存/离线展示能力。

## Decision

选择 Option 2。

- **列表**是只读的。`Core/Pi/PiSessionFiles` 定位
  `~/.pi/agent/sessions/--<path>--/`（按 pi 规则编码：去掉前导分隔符、把 `/`、`\`、`:` 替换为
  `-`、两侧包 `--`），把每个 `.jsonl` 解析为 `PiSessionSummary`（id、名称、预览、消息数、时间戳）。
- **工作区**由 `Core/Stores/WorkspaceStore` 持有，并持久化到 `UserDefaults`。未选择目录时，
  UI 显示 `WorkspaceGateView` 引导用户选择。
- **打开**会话时，把它镜像为本地 `Session`（`piSessionPath` = 文件路径），并从文件导入可展示消息
  （user / assistant / toolResult）。
- **继续**会话时以 `--session <path>` 启动 pi。新建会话**不再**使用 `--no-session`，由 pi 负责持久化；
  `AgentTransport.sessionInfo()`（`get_state`）返回 `sessionFile`，在首轮结束后回写到
  `Session.piSessionPath` 并刷新列表。

## Consequences

- `Session` 新增 `piSessionPath: String?`。这是 schema 变更；新增可选属性属于轻量迁移。应用**尚未发布**，
  因此一次性重置 store 也可接受。后续结构性变更仍需 `VersionedSchema` + `SchemaMigrationPlan`。
- 应用默认不再传 `--no-session`，pi 成为会话持久化的所有者。本地 `Message` 只是展示用的缓存/镜像，
  而非唯一副本。
- 删除会话（会删除 pi 的 `.jsonl` 文件）**刻意推迟** —— 属破坏性操作，需单独设计。
- 解析会读取整份会话文件；大历史在后台线程扫描。若日后变慢，再做有界扫描（头部/尾部）。
- 未引入第三方依赖，也未自造组件：UI 使用系统的 `ContentUnavailableView` 与 SwiftUI `.fileImporter`。

## Related

- [ADR-0003](0003-pi-transport-and-sandbox.zh-CN.md) —— 传输与沙盒
- [ADR-0004](0004-domain-model.zh-CN.md) —— `Session` / `Message`
- [pi-agent.zh-CN.md](../pi-agent.zh-CN.md) —— 集成总览
- [architecture.zh-CN.md](../architecture.zh-CN.md) —— 模块布局与数据流
