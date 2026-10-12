# 文档索引

[English](README.md) · [简体中文](README.zh-CN.md)

本目录是 PiDesktop 的文档中心。**按需加载**：只打开当前任务相关的那一篇，不要通读全部。

> Agent 的强制规则与入口在仓库根目录 [`../AGENTS.zh-CN.md`](../AGENTS.zh-CN.md)。

| 文档 | 内容 | 何时读 |
| --- | --- | --- |
| [architecture.zh-CN.md](architecture.zh-CN.md) | 目录结构、模块划分、数据流、状态管理 | 新增模块 / 理清调用关系 |
| [design-system.zh-CN.md](design-system.zh-CN.md) | Liquid Glass、原生组件、颜色、字体、动效 | 写或评审 UI |
| [coding-conventions.zh-CN.md](coding-conventions.zh-CN.md) | Swift 命名、并发、错误处理、文件组织 | 写代码前 |
| [workflows.zh-CN.md](workflows.zh-CN.md) | 构建、运行、测试、调试、提交、排障 | 动手构建 / 提交前 |
| [pi-agent.zh-CN.md](pi-agent.zh-CN.md) | pi agent 集成方式、事件模型、会话/工具调用 | 对接 agent 逻辑 |
| [decisions/](decisions/README.zh-CN.md) | 架构决策记录（ADR） | 做重大取舍 / 查历史原因 |

英文为默认文档（同名 `.md`），中文镜像使用 `.zh-CN.md` 后缀。修改任一份都要同步另一份。

## 文档维护规则

- **单一事实来源**：同一知识只写一处，别处链接引用。
- **同 PR 更新**：代码改动影响到的文档必须在同一提交内更新。
- **分层**：根 `README.md` 面向使用者；`AGENTS.md` 面向 Agent 规则；`docs/` 承载细节；`docs/decisions/` 记录决策。
- **触发 ADR**：引入第三方依赖、更换核心框架、改变数据模型/持久化、影响面大的取舍。
- 新增主题时优先扩充既有文档；确需新文件时在此表登记。
