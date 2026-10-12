# ADR-0003: pi 通信方式与应用沙盒 / entitlements

[English](0003-pi-transport-and-sandbox.md) · [简体中文](0003-pi-transport-and-sandbox.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-12
- 决策者：项目协作者

## 背景

PiDesktop 需要连接 pi coding agent，并让它操作用户的项目目录（见 [pi-agent.zh-CN.md](../pi-agent.zh-CN.md)）。
有两个相互耦合、尚未确定的决策：

1. **通信方式** —— 应用如何与 pi 通信。
2. **沙盒 / entitlements** —— 应用在 macOS App Sandbox 下被允许做什么。

当前脚手架启用了 `com.apple.security.app-sandbox = true` 与
`com.apple.security.files.user-selected.read-only`，由
`ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readonly` 自动生成。沙盒应用
**既不能拉起任意子进程，也不能读写任意项目路径**，因此通信方式与 entitlements 必须一起决策。
修改 entitlements 受 [AGENTS.md §2.3](../../AGENTS.md) 约束（说明理由 → 给出选项 → 评估影响 → 显式批准）。

## 候选方案

### 通信方式

1. **子进程 + stdio** —— 启动 `pi` CLI，通过管道交换行/JSON。
   - 优点：复用现有 CLI；实现简单；单进程树；生命周期可控。
   - 缺点：需拉起子进程；强化运行时 / 库验证可能阻止加载未公证的辅助二进制；需谨慎处理取消与进程管理。
2. **本地服务 / RPC** —— pi 作为服务运行（socket/HTTP），应用作为客户端。
   - 优点：对沙盒友好（UI 不拉起子进程）；由服务负责文件访问；耦合松散。
   - 缺点：需安装/守护额外服务；socket 发现与鉴权；打包更复杂。
3. **直接链接 SDK** —— 若存在 pi 的 SDK 则内嵌。
   - 优点：集成最紧密。
   - 缺点：依赖是否存在 Swift/可嵌入 SDK；耦合最紧。

### 沙盒

- **A. 保持沙盒开启** —— 通过 `NSOpenPanel` + 安全作用域书签授予工作区访问；用捆绑的 helper /
  XPC 服务（`com.apple.security.inherit`）运行 pi。
  - 优点：可上架 Mac App Store；隔离性最强。
  - 缺点：工程量最大；每个工作区一个书签；需打包 helper 并处理信任边界。
- **B. 关闭 App Sandbox**（`ENABLE_APP_SANDBOX = NO`）。
  - 优点：可直接拉起 `pi`、以普通文件权限读写项目目录；路径最短；与多数终端 / 开发者工具 GUI 的做法一致（不通过 Mac App Store 分发）。
  - 缺点：无法上架 Mac App Store；隔离性较弱；分发仍需公证 + 强化运行时。
- **C. 混合** —— 沙盒 UI + 通过 `SMAppService` / 登录项拉起非沙盒 helper。
  - 优点：UI 仍可保持沙盒。
  - 缺点：最复杂；存在双进程信任边界。

## 决策

选择 **通信方式 1（子进程 + stdio）+ 沙盒 B（关闭 App Sandbox）**。

PiDesktop 是直接下载（公证）分发的开发者工具，不上架 Mac App Store。关闭 App Sandbox 后，应用可
直接拉起 `pi` CLI，并以普通文件权限读写用户项目目录——这是打通 agent 环路的最短路径。沙盒方案
（A/C）需要额外 helper/XPC 进程与按工作区的安全作用域书签；仅当未来以 Mac App Store 分发为目标时再评估。

实现方式：设置 `ENABLE_APP_SANDBOX = NO`，并移除 `ENABLE_USER_SELECTED_FILES`。依据
[AGENTS.md §2.3](../../AGENTS.md)，本次 entitlements 变更已由项目所有者显式批准。

## 影响

- `com.apple.security.app-sandbox` 与 `com.apple.security.files.user-selected.read-only` 两项
  entitlement 被移除；应用以非沙盒方式运行，分发时采用强化运行时 + 公证。
- 无法上架 Mac App Store。若未来成为硬性要求，用 helper/XPC 方案（A/C）新增 ADR 取代本决策。
- 应用将把 `pi` 作为子进程拉起并监管：需在 `Core/Agent` 实现生命周期/取消，以及「通信格式 → 领域事件」映射。
- 后续：ADR-0004 记录 SwiftData 数据模型（`Session` / `Message`）及其迁移策略。

## 相关

- [pi-agent.zh-CN.md](../pi-agent.zh-CN.md) —— 事件模型、会话生命周期、集成约束
- [architecture.zh-CN.md](../architecture.zh-CN.md) —— 规划中的模块与数据模型
- [AGENTS.md §2.3](../../AGENTS.md) —— 构建配置 / entitlements 的批准门槛
