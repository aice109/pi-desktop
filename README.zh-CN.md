# PiDesktop

[![Platform](https://img.shields.io/badge/platform-macOS%2027%2B-black)](#环境要求)
[![Swift](https://img.shields.io/badge/Swift-5.0-orange)](https://swift.org)
[![Version](https://img.shields.io/badge/version-0.1.0-blue)](#项目状态)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[English](README.md) · **简体中文**

为 [pi coding agent](https://github.com/earendil-works/pi) 打造的 **macOS 原生 GUI**：管理会话、实时查看工具调用过程、维护项目上下文——都在一个地道的 Mac 应用里完成。

> ⚠️ **状态：早期。** 先选一个项目目录，浏览该目录的 pi 会话、实时查看工具调用，并与 pi agent 对话；
> 思考持久化与设置仍在开发中。

---

## 功能

现已可用：

- 📁 **工作区会话** —— 选择项目目录，浏览存储在该目录下的 pi 会话，并可打开继续对话。
- 💬 **流式对话** —— 发送消息，增量渲染助手回复，支持 Markdown。
- 🛠 **工具调用可视化** —— 卡片展示工具名、参数、实时输出、状态与耗时。
- 🎛 **模型与思考等级** —— 选择模型与推理等级，查看上下文占用与费用。
- 🗂 **会话管理** —— 重命名、搜索、刷新，并可删除会话（移至废纸篓）。
- 🪟 **原生观感** —— 基于 Apple 框架与 macOS **液态玻璃**。

进行中：

- 🧠 **思考区** —— 持久化思考内容，便于事后回看。
- ⚙️ **设置** —— 默认模型、主题与偏好。

设计细节见 [`docs/architecture.zh-CN.md`](docs/architecture.zh-CN.md) 与 [`docs/pi-agent.zh-CN.md`](docs/pi-agent.zh-CN.md)。

---

## 环境要求

- macOS **27.0** 或更高
- 带匹配 SDK 的 Xcode（Swift 5、SwiftUI、SwiftData）

## 快速开始

```bash
git clone https://github.com/aice109/pi-desktop.git
cd PiDesktop

# 命令行构建
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build

# 或在 Xcode 中打开并 ⌘R 运行
open PiDesktop.xcodeproj
```

> 若 `xcodebuild` 报 `requires Xcode`，把工具链指向 Xcode：
> `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。

完整构建/测试/调试命令与排障见 [`docs/workflows.zh-CN.md`](docs/workflows.zh-CN.md)。

---

## 项目结构

```
PiDesktop/
├── AGENTS.md                  # AI Agent / 协作者规则与文档索引（英文）
├── AGENTS.zh-CN.md            # 同上（简体中文）
├── README.md                  # 英文说明（默认）
├── README.zh-CN.md            # 本文件
├── CONTRIBUTING.md            # 贡献指南
├── LICENSE                    # MIT
├── .github/                   # CI、Issue 与 PR 模板
├── scripts/                   # 开发脚本（图标生成器）
├── PiDesktop.xcodeproj/       # Xcode 工程
├── PiDesktop/                 # 应用源码
└── docs/                      # 文档（英文默认 + 中文）
    ├── README.md / .zh-CN.md  # 文档索引
    ├── architecture.md / .zh-CN.md
    ├── design-system.md / .zh-CN.md
    ├── coding-conventions.md / .zh-CN.md
    ├── workflows.md / .zh-CN.md
    ├── pi-agent.md / .zh-CN.md
    └── decisions/             # 架构决策记录（ADR）
```

---

## 设计原则

1. **原生优先** —— 优先使用 Apple 原生框架（SwiftUI、AppKit、SwiftData），能内置解决就不自造。
2. **液态玻璃** —— 遵循 macOS 设计语言，使用系统玻璃 API，绝不用自绘模糊冒充。
3. **先问后加** —— 引入第三方依赖或自定义组件前必须先获明确同意（见 [`AGENTS.zh-CN.md`](AGENTS.zh-CN.md)）。
4. **文档驱动** —— 规则与细节分层沉淀，改代码同步改文档。

---

## 文档

- **Agent / 协作者请先读 [`AGENTS.zh-CN.md`](AGENTS.zh-CN.md)**（英文版 [`AGENTS.md`](AGENTS.md)）。
- 文档索引：[`docs/README.zh-CN.md`](docs/README.zh-CN.md)
- 架构说明：[`docs/architecture.zh-CN.md`](docs/architecture.zh-CN.md)
- 设计系统：[`docs/design-system.zh-CN.md`](docs/design-system.zh-CN.md)
- 开发工作流：[`docs/workflows.zh-CN.md`](docs/workflows.zh-CN.md)
- English: [`README.md`](README.md)

---

## 贡献

见 [`CONTRIBUTING.zh-CN.md`](CONTRIBUTING.zh-CN.md)。简言之：先读 `AGENTS.zh-CN.md`，遵循 [Conventional Commits](https://www.conventionalcommits.org/)，保持构建通过，代码与文档同步；重大取舍需记 ADR。

## 安全

请通过私密渠道报告漏洞，见 [`SECURITY.md`](SECURITY.md)。

## 许可

基于 [MIT License](LICENSE) 发布。© 2026 PiDesktop contributors。
