# 架构决策记录（ADR）

[English](README.md) · [简体中文](README.zh-CN.md)

本目录用 **ADR（Architecture Decision Record）** 记录影响较大的技术与设计取舍。

## 何时写 ADR

出现以下任一情况，**必须先写 ADR 再实施**：

- 引入任何**第三方依赖**（SPM / CocoaPods / 二进制 / 复制源码）。
- 编写**自定义组件**替代系统已有能力。
- 更换核心框架 / 通信方式 / 数据模型 / 持久化方案。
- 影响面大、可逆成本高的设计取舍。

## 规则

- **只增不改**：已决定的 ADR 不修改内容；如需推翻，新增一条 ADR 并在其中标注 `Supersedes ADR-XXXX`，同时在被取代的 ADR 顶部加一行 `Superseded by ADR-XXXX`。
- **编号递增**：`0001-xxx.md`、`0002-xxx.md`……
- **命名**：`NNNN-短横线-小写标题.md`（英文）。
- 新增 ADR 后，在下方「决策列表」登记。

## 模板

```markdown
# ADR-NNNN: <决策标题>

- 状态：Proposed | Accepted | Superseded by ADR-XXXX
- 日期：YYYY-MM-DD
- 决策者：<姓名/Agent>

## 背景
当前面临的问题、约束与目标。

## 候选方案
1. 方案 A：描述 + 优劣
2. 方案 B：描述 + 优劣

## 决策
选择哪个方案，以及为什么。

## 影响
正面影响、负面影响、代价、后续需要做的事。
```

## 决策列表

| 编号 | 标题 | 状态 |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | 使用 ADR 记录架构决策 | Accepted |
| [0002](0002-native-first-and-liquid-glass.md) | 原生组件优先、采用液态玻璃、第三方/自定义需先确认 | Accepted |
| [0003](0003-pi-transport-and-sandbox.md) | pi 通信方式与应用沙盒 / entitlements | Accepted |
| [0004](0004-domain-model.md) | SwiftData 领域模型（Session / Message） | Accepted |
| [0005](0005-workspace-and-pi-sessions.zh-CN.md) | 按工作目录组织 pi 会话 | Accepted |
| [0006](0006-tool-calls.zh-CN.md) | 持久化工具调用并渲染为卡片 | Accepted |
| [0007](0007-reasoning.zh-CN.md) | 持久化助手思考内容 | Accepted |
