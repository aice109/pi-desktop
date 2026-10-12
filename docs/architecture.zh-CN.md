# 架构

[English](architecture.md) · [简体中文](architecture.zh-CN.md)

## 目标

PiDesktop 是 pi coding agent 的 macOS 原生 GUI。核心职责：

1. 与 pi agent 建立会话（启动/连接/中断）。
2. 实时呈现 agent 的消息、思考、工具调用与结果。
3. 管理项目/文件上下文与工作目录。
4. 提供设置、偏好与历史会话。

## 技术栈

| 关注点 | 选型 | 说明 |
| --- | --- | --- |
| UI | SwiftUI | 主 UI 框架；必要时 AppKit 桥接 |
| 数据持久化 | SwiftData | 会话、消息、设置 |
| 状态 | Observation / `@Observable` | 优先于 `ObservableObject` |
| 并发 | Swift Concurrency | `async/await`、`actor`、`AsyncStream` |
| 设计 | Liquid Glass | 见 [design-system.zh-CN.md](design-system.zh-CN.md) |

## 当前目录结构

```
PiDesktop/
├── PiDesktopApp.swift      # @main，App 入口、Scene、SwiftData 容器
├── ContentView.swift       # 根视图
├── Item.swift              # 模板示例模型（SwiftData）
└── Assets.xcassets/        # 资源目录
```

> 初始化模板中的 `Item` 仅为示例，正式开发时应替换为真实领域模型（见下）。

## 规划中的模块划分

随着功能落地，源码按 **功能域（feature-first）** 组织，而非按类型堆叠：

```
PiDesktop/
├── App/            # 入口、Scene、依赖组装
├── Features/
│   ├── Chat/       # 会话与消息流 UI
│   ├── Session/    # 会话列表与生命周期
│   ├── Settings/   # 设置
│   └── Workspace/  # 项目 / 文件上下文
├── Core/
│   ├── Agent/      # 与 pi agent 的通信层（进程/协议/事件）
│   ├── Models/     # SwiftData 模型
│   └── Services/   # 通用服务（存储、日志、配置）
└── DesignSystem/   # 颜色、字体、玻璃封装、通用视图
```

规则：
- 一个 feature 目录自包含其 View / ViewModel / 局部组件。
- 跨 feature 复用的能力下沉到 `Core/` 或 `DesignSystem/`。
- 通信层（`Core/Agent`）对外只暴露领域事件，不泄漏传输细节。

## 数据流（目标形态）

```
pi agent 进程/协议
      │  事件流 (AsyncStream)
      ▼
 Core/Agent  ──► 领域事件  ──►  SessionStore (@Observable, @MainActor)
                                      │
                                      ▼
                                   SwiftUI Views
```

原则：
- **单向数据流**：View 只读状态、发送意图；状态变更集中在 Store。
- **主线程隔离**：UI 状态标记 `@MainActor`。
- **通信与 UI 解耦**：Agent 层不 import SwiftUI。

## 数据模型（规划）

- `Session`：一次会话，含标题、时间、工作目录、状态。
- `Message`：角色（user/assistant/tool）、内容、时间、关联的工具调用。
- `ToolCall`：工具名、参数、状态、结果、耗时。
- `AppSettings`：模型、主题、偏好。

> 模型变更属于重大改动 → 需新增 ADR（见 [decisions/](decisions/README.zh-CN.md)）。

## 相关文档
- UI 规范：[design-system.zh-CN.md](design-system.zh-CN.md)
- pi 集成：[pi-agent.zh-CN.md](pi-agent.zh-CN.md)
- 编码规范：[coding-conventions.zh-CN.md](coding-conventions.zh-CN.md)
