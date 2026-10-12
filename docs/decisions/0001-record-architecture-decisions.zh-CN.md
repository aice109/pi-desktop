# ADR-0001: 使用 ADR 记录架构决策

[English](0001-record-architecture-decisions.md) · [简体中文](0001-record-architecture-decisions.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-12
- 决策者：项目初始协作者

## 背景

项目处于初始化阶段，后续会不断引入模块、通信方式与 UI 组合。若不记录取舍，后续协作者（含 AI Agent）会重复讨论已决问题，或无意中推翻既有约束。

## 候选方案

1. **ADR（架构决策记录）**：轻量 Markdown 文档，只增不改，按编号归档。
2. **Wiki / 外部文档**：与代码分离，易失同步、检索成本高。
3. **仅在提交信息里说明**：碎片化，难以全局检索。

## 决策

采用 ADR，存放于 `docs/decisions/`，规则与模板见该目录 README。重大取舍必须先写 ADR 再实施。

## 影响

- 正面：决策可追溯、约束清晰、便于协作与 Agent 上下文化。
- 负面：维护文档需要纪律；需在提交前检查是否触发 ADR。
- 后续：`AGENTS.md` 与 `docs/README.md` 已登记 ADR 触发规则。
