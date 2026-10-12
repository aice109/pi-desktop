# 为 PiDesktop 做贡献

[English](CONTRIBUTING.md) · **简体中文**

感谢你对 PiDesktop 的关注！本指南说明如何搭建环境、如何让改动被合并。

## 开始之前

请先阅读 [`AGENTS.zh-CN.md`](AGENTS.zh-CN.md) —— 它包含项目的硬性规则与文档索引。要点：

1. **原生优先** —— 优先 Apple 原生框架（SwiftUI / AppKit / SwiftData），而非自造。
2. **液态玻璃** —— 使用系统玻璃 API，绝不自绘冒充。
3. **先问后加** —— 引入第三方依赖、自定义组件、新资源集或改动构建配置前，**先开 issue 讨论**。
4. **文档随代码** —— 同步更新对应文档；重大取舍需记 ADR。

## 开发环境

- macOS 27.0+ 与 Xcode（匹配 SDK）
- 目前无第三方依赖

```bash
git clone https://github.com/aice109/pi-desktop.git
cd PiDesktop
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build
open PiDesktop.xcodeproj   # ⌘R 运行
```

测试/调试/排障见 [`docs/workflows.zh-CN.md`](docs/workflows.zh-CN.md)。

## 贡献方式

- 🐛 **缺陷报告** —— 使用 issue 模板；附上 macOS 版本、Xcode 版本、复现步骤、期望与实际结果。
- 💡 **功能建议** —— 开 issue 描述问题与期望效果。
- 📝 **文档** —— 欢迎修正与翻译。英文为默认，中文位于 `*.zh-CN.md`。
- 💻 **代码** —— 见下方流程。

## PR 流程

1. 非琐碎的改动**先开 issue**，就方案达成一致。
2. **Fork 并建分支**：`feat/<scope>`、`fix/<scope>`、`docs/<topic>`。
3. **保持小** —— 每个 PR 只做一件逻辑上的事。
4. **风格**：见 [`docs/coding-conventions.zh-CN.md`](docs/coding-conventions.zh-CN.md) 与设计系统。
5. **注释得当** —— 解释"为什么"，不要复述代码。
6. 本地**构建与测试**，保持构建通过、无新增 warning。
7. **同步文档**（重大决策补 ADR）。
8. 用 [Conventional Commits](https://www.conventionalcommits.org/) **提交**：`feat(chat): ...`。
9. **发起 PR** 并填写模板，关联 issue。

## 提交信息格式

```
<type>(<scope>): <subject>

<body：为什么，而非改了什么>

<footer：BREAKING CHANGE / Closes #123>
```

`type` ∈ `feat` `fix` `refactor` `perf` `docs` `style` `test` `build` `chore` `ci`。

## 评审

- CI 必须通过，且分支保持最新。
- 维护者会评审正确性、原生优先原则与文档同步。
- 使用 squash 合并，保持 `main` 线性且可构建。

## 行为准则

参与即表示你同意 [行为准则](CODE_OF_CONDUCT.md)。

## 许可

提交贡献即表示你同意你的贡献按项目的 [LICENSE](LICENSE) 授权。
