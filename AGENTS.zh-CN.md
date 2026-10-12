# AGENTS.md

[English](AGENTS.md) · **简体中文**

> 本文件是所有 AI Agent / 协作者进入本仓库的**唯一入口**。
> 请先读完本文件（最重要的规则都在这里），再根据下方「文档按需加载」表按任务需要打开对应文档，**不要一次性加载全部文档**。

---

## 1. 项目定位

PiDesktop 是一个 **macOS 桌面 GUI 应用**，为 [pi coding agent](https://github.com/earendil-works/pi) 提供可视化界面（会话、工具调用可视化、文件/项目上下文、设置等）。

- 平台：macOS（`MACOSX_DEPLOYMENT_TARGET = 27.0`）
- 语言 / UI：Swift 5 + SwiftUI（必要时 AppKit）
- 持久化：SwiftData
- 工程：`PiDesktop.xcodeproj`
- 目标：原生、轻量、与 macOS 系统观感一致的 pi agent 客户端

---

## 2. 最高优先级规则（MUST / MUST NOT）

这些是硬性约束，违反即视为实现错误，**任何情况下不得擅自绕过**。

### 2.1 原生组件优先（MUST）
- 优先使用 **Apple 原生框架与组件**：SwiftUI、AppKit、Foundation、SwiftData、Observation 等。
- 能用 SwiftUI 内置视图/修饰符解决的，**不要**自己造轮子。
- 需要 AppKit 桥接时用 `NSViewRepresentable` / `NSViewControllerRepresentable`，并集中管理桥接代码。

### 2.2 液态玻璃效果（MUST）
- UI 必须遵循 macOS **Liquid Glass** 设计语言：使用 `.glassEffect()`、`GlassEffectContainer`、`glassEffectID`、`.buttonStyle(.glass)` 等系统 API，以及 `NSGlassEffectView`（AppKit 桥接时）。
- 玻璃/材质只在系统语义位置使用，**不得**用自定义模糊、半透明色块去"模拟"玻璃质感。
- 需要自定义外观时，优先通过系统 `.tint`、`.controlSize`、`.background(.regularMaterial)` 等语义化方式调整。

### 2.3 引入第三方 / 自定义组件必须先询问（MUST ASK）
在下列任一情况发生前，**必须先向用户说明理由、给出候选方案，获得明确同意后才能动手**：
- 引入任何 **第三方依赖**（SPM / CocoaPods / 二进制包 / 复制源码）。
- 编写**自定义组件**替代系统已有能力（自定义控件、自定义绘制、自定义动画引擎等）。
- 引入设计资源/字体/图标集（非 SF Symbols）。
- 修改工程构建配置、依赖图、签名/权限（entitlements）等。

询问时请给出：**为什么原生方案不够用 → 候选方案对比 → 对包体积/维护/许可的影响**。未获同意前，先用原生方案实现最小可行版本。

### 2.4 其他强制约束
- 不提交密钥、token、个人路径（`/Users/xxx`）与 `xcuserdata`。
- 不擅自删除/重写与本任务无关的文件或历史。
- 修改行为前先阅读相关文档与现有代码，遵循既有模式。
- **注释尽可能写，但不什么都注释**：该解释的地方必须注释；自解释代码不加噪音。细则见 [`docs/coding-conventions.zh-CN.md`](docs/coding-conventions.zh-CN.md) §9。

---

## 3. 文档按需加载（Progressive Disclosure）

**主文件只保留规则，细节入 docs。** 按任务类型只加载需要的那几篇：

| 你要做的事 | 加载文档 |
| --- | --- |
| 了解模块划分、数据流、目录结构 | [`docs/architecture.zh-CN.md`](docs/architecture.zh-CN.md) |
| 写 / 改 UI、玻璃效果、配色、动效 | [`docs/design-system.zh-CN.md`](docs/design-system.zh-CN.md) |
| 写 Swift 代码、命名、并发、错误处理 | [`docs/coding-conventions.zh-CN.md`](docs/coding-conventions.zh-CN.md) |
| 构建 / 运行 / 测试 / 调试 / 提交 | [`docs/workflows.zh-CN.md`](docs/workflows.zh-CN.md) |
| 对接 pi agent、协议、会话模型 | [`docs/pi-agent.zh-CN.md`](docs/pi-agent.zh-CN.md) |
| 做技术选型、重大取舍 | [`docs/decisions/`](docs/decisions/README.zh-CN.md) |
| 找文档入口 | [`docs/README.zh-CN.md`](docs/README.zh-CN.md) |
| 阅读英文文档 | `docs/*.md` |

规则：
- **只读当前任务需要的文档**，避免无谓的上下文开销。
- 任务跨领域时，按上表逐篇加载，而不是全文搜索仓库。
- 新增知识时，先判断归属哪个文档，**更新既有文档**而不是到处新建碎片文件。

---

## 4. 常用命令

```bash
# 构建
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build

# 运行
open PiDesktop.xcodeproj   # 然后在 Xcode 中 Cmd+R
```

> 若 `xcodebuild` 报 `requires Xcode`：`sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`。
> 完整命令与排障见 [`docs/workflows.zh-CN.md`](docs/workflows.zh-CN.md)。

---

## 5. 提交规则（Commit Rules）

采用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>

<body：为什么这么改，而非改了什么>

<footer：BREAKING CHANGE / Closes #issue>
```

- **type**：`feat` `fix` `refactor` `perf` `docs` `style` `test` `build` `chore` `ci`
- **scope**：模块名，如 `chat` `session` `settings` `glass` `docs`（可选但推荐）
- **subject**：祈使句、不带句号、≤ 50 字符
- **一次提交只做一件事**；纯格式改动与逻辑改动分开提交
- 提交前必须：能编译通过、无新增 warning、文档已同步（见第 6 节）
- **禁止**：`update`、`fix bug`、`wip` 等无信息量的 message；禁止提交被注释掉的死代码

示例：
```
feat(chat): 支持流式渲染 pi 工具调用卡片

工具调用卡片此前只在完成后出现，用户看不到中间态。
改为订阅增量事件并按事件类型分层渲染。

Refs: docs/pi-agent.md#事件模型
```

---

## 6. 文档规则（Documentation Rules）

- **单一事实来源**：同一知识只在一个地方描述，其他地方用链接引用。
- **代码与文档同 PR**：改动了架构/接口/UI 规范/命令，必须同步更新对应文档。
- **文档分层**：
  - 根目录 `README.md`：面向使用者/贡献者的总览与快速开始。
  - `AGENTS.md`（本文件）：面向 Agent 的规则与索引入口，保持精简。
  - `docs/*.md`：面向具体主题的细节，按需加载。
  - `docs/decisions/*.md`：只增不改的架构决策记录（ADR）。
- **两种语言**：英文为默认；中文镜像使用 `.zh-CN.md` 后缀。修改任一份都要同步另一份，并在文档顶部互相链接。
- **ADR 触发条件**：引入第三方依赖、更换核心框架、改变数据模型/持久化方案、影响范围大的取舍 → 必须先新增 ADR（模板见 [`docs/decisions/README.zh-CN.md`](docs/decisions/README.zh-CN.md)）。
- 文档使用 Markdown，默认英文；代码块标注语言；相对链接必须可点。

---

## 7. 标准工作流

1. **澄清**：需求不清先问，不臆测。
2. **加载上下文**：按第 3 节只读相关文档 + 相关源码。
3. **方案**：涉及第 2.3 节事项或架构变更 → 先询问/先写 ADR。
4. **实现**：原生优先，小步提交，能编译。
5. **自检**：构建通过、无 warning、UI 符合设计系统。
6. **同步文档**：更新受影响文档，必要时新增 ADR。
7. **提交**：按第 5 节规范提交。

---

## 8. 关键路径速查

| 路径 | 说明 |
| --- | --- |
| `PiDesktop/PiDesktopApp.swift` | App 入口（Scene、SwiftData 容器） |
| `PiDesktop/ContentView.swift` | 根视图 |
| `PiDesktop.xcodeproj` | Xcode 工程 |
| `docs/` | 项目文档（按需加载） |
| `AGENTS.md` / `README.md` | 规则入口 / 使用总览 |
