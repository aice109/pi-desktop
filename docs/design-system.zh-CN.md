# 设计系统 / Liquid Glass

[English](design-system.md) · [简体中文](design-system.zh-CN.md)

本文件规定 PiDesktop 的视觉与交互规范。**写或评审任何 UI 前必须阅读。**

## 1. 核心原则

1. **原生优先**：能由 Apple 原生组件实现，就不自造。
2. **系统玻璃**：使用系统 Liquid Glass API，禁止用自绘模糊/半透明色块"模拟"玻璃。
3. **语义化外观**：优先用 `.tint`、`.controlSize`、`.background(.regularMaterial)` 等语义 API。
4. **尊重系统**：自动适配浅色/深色、增强对比度、降低透明度等辅助功能设置。

## 2. Liquid Glass 使用规范

macOS Liquid Glass 提供系统级玻璃材质。优先使用以下 API（按可用性）：

| 场景 | API |
| --- | --- |
| 给视图加玻璃背景 | `.glassEffect(_:in:)` |
| 多个玻璃元素组合/形变 | `GlassEffectContainer` + `glassEffectID` |
| 玻璃按钮 | `.buttonStyle(.glass)` / `.glassProminent` |
| AppKit 桥接 | `NSGlassEffectView` |

用法示例：

```swift
// 玻璃卡片
content
    .padding()
    .glassEffect(.regular, in: .rect(cornerRadius: 16))

// 玻璃容器内多个元素联动
GlassEffectContainer(spacing: 16) {
    HStack {
        Button("新建会话") { }.buttonStyle(.glass)
        Button("设置") { }.buttonStyle(.glass)
    }
}
```

约束：
- 玻璃用于**系统语义位置**（工具栏、浮层、卡片、控件背景），不要满屏堆叠。
- 不要给玻璃再叠加自定义 `Material`/`blur`/半透明渐变。
- 动效遵循系统默认；自定义动画前先确认原生动画不够用，并按 §4 询问。
- API 可用性随 SDK 变化：以当前部署目标（macOS 27.0）为准，使用前查证真实签名，不要臆造。

## 3. 组件选型

| 需求 | 首选 |
| --- | --- |
| 列表/表格 | `List`、`Table` |
| 侧边栏导航 | `NavigationSplitView` |
| 工具栏 | `.toolbar` + `ToolbarItem` |
| 设置 | `Settings` Scene / `Form` |
| 菜单 | `Menu`、`.contextMenu` |
| 弹窗 | `.sheet`、`.popover`、`.alert`、`.confirmationDialog` |
| 图标 | SF Symbols |
| 富文本/Markdown | 优先原生 `Text` / `AttributedString`；块级渲染用 `MarkdownText`（Foundation intent + SwiftUI 原语） |

## 4. 引入第三方或自定义组件：先询问

在引入以下内容前，**必须先向用户说明并获同意**（见 [AGENTS.zh-CN.md §2.3](../AGENTS.zh-CN.md)）：

- 第三方依赖（SPM 等）
- 自绘控件 / 自定义绘制 / 自定义动画引擎
- 非 SF Symbols 的图标集、第三方字体、设计资源
- 对原生组件进行可行但侵入性的替换

询问模板：
1. **为什么原生方案不够**：具体缺失的能力。
2. **候选方案**：原生近似实现 vs 第三方/自定义，各自优劣。
3. **影响**：包体积、维护成本、许可证、与玻璃/可访问性的一致性。

## 5. 视觉 Token（约定）

- **颜色**：优先语义色（`.primary`、`.secondary`、`Color.accentColor`、`.tint`）。品牌色走 Asset Catalog 的 `AccentColor`。
- **字体**：系统字体 + 语义样式（`.body`、`.headline`、`.caption`），通过 `.font(...)` 使用，避免硬编码字号。
- **间距**：使用 4/8 的倍数；跨元素使用一致的 `spacing` 常量，避免魔数散落。
- **圆角**：与系统一致；玻璃容器用 `.rect(cornerRadius:)` 显式给出。应用内部圆角统一取自
  `DesignTokens.Radius`（`chip` 4、`small` 6、`card` 8、`control` 10），刻意偏小，贴近原生控件。
- **图标**：SF Symbols，配套 `.symbolRenderingMode` / `.imageScale`。

> 若需新增设计 token，先扩本节，再落代码；重大设计取舍 → 记 ADR。

### 侧边栏

- 顶部工作区栏 = 淡色文件夹徽标 + 目录名/路径 + 工作区菜单；去掉原先的生硬分隔线，改由分组表头分隔列表。
- 会话放在 `.sidebar` 的 `List` 中，归到带计数的「Sessions」分组表头下。行内为图标 + 标题 + 次要信息
  （相对时间 · 消息数），并带少量垂直留白，使每行都是独立的点击目标。
- 回合结束时若该会话不是当前可见会话，行尾显示淡色未读圆点；打开会话即清除。同一事件在应用处于
  后台时会发出系统通知（`UserNotifications`），见 `Core/Notifications/TurnNotifier.swift`。

### 聊天界面约定

- 消息使用 plain `List` 并隐藏行分隔线；连续同一角色的消息共用一条头部（角色头像 + 名称），
  减少视觉噪音。
- 时间线按**回合**分组（一条用户消息到下一个之前）。只有每个回合最后一条助手正文（「结论」）
  常显；思考、工具调用和中间旁白都折叠在 `DisclosureGroup` 里。
- 折叠行统一用共享的 `DisclosureGroupStyle`（`RowDisclosureGroupStyle`）：整行标题都是带
  `contentShape(Rectangle())` 的按钮，点击轻松，箭头保持系统观感，展开内容左侧缩进、不贴边。
- 消息列表、输入框、状态胶囊与用量脚注共用 16pt 水平边距，左右对齐。
- 助手正文按块级 Markdown 渲染（`MarkdownText`）：标题、段落、有序/无序列表、围栏代码块、引用、
  分隔线、表格（`Grid`）。基于 Foundation 的 `AttributedString(markdown:)` + `PresentationIntent`
  与 SwiftUI 原语实现，无第三方依赖；行内格式（粗体、行内代码、链接）保留。
- 围栏代码块由一个小型原生词法器（`CodeSyntaxHighlighter`）着色：注释、字符串、数字与关键字用语义颜色
  （随明暗外观自适应），并按代码内容缓存。它是词法级而非语法级——语言未知时仍会着色注释/字符串/数字。
- 用户消息用淡色气泡（`.tint.opacity(0.12)`）；助手消息保持纯文本，便于 Markdown 阅读。
- 输入框是带聚焦描边的圆角字段，发送为 `.borderedProminent` 圆形按钮（⌘↩）；流式状态行置于
  `.thinMaterial` 的 `Capsule` 中——属于系统预期的叠加层，不是自绘模糊。
- 运行中输入框保持可用：回车排队一条 **steering** 消息（发送控件变为 `Menu`，点击即 steer，
  菜单里可选「Send as Follow-up」）。已排队消息显示在状态行下方，「Clear Queued」会将其文本
  还原到输入框（pi 的 Esc 语义）。
- 工具栏的放大镜会在会话上方打开搜索浮层；结果匹配消息正文与工具参数/输出，选中后消息列表滚动到该行。
- 工具栏提供 Context 菜单（`arrow.down.right.and.arrow.up.left`）：「Compact Now」「Compact with
  Instructions…」（小弹窗）、绑定 `get_state` 的 Auto-compaction `Toggle`，以及 Auto-retry `Toggle`。
  重试进行时状态行会显示「Abort Retry」链接。
- 工具栏提供 Branch 菜单（`arrow.triangle.branch`），包含「Clone Session」与「Fork from Message…」；
  后者打开列出可 fork 用户消息的弹窗。选中后会 fork 并把原文本回填输入框，同一流程即「编辑并重发」。
  菜单还含「Show Tree…」，渲染完整会话树（`get_tree`，包括被遗弃分支）并高亮活动叶子；用户节点上带
  Fork 操作。
- 以 `!` 开头的草稿会直接执行 shell 命令（不发送给模型）；执行期间显示「Running shell command…」
  与 Abort 链接。
- 在输入框键入 `/` 会显示 pi 命令（扩展 / prompt / 技能）的内联建议列表，带描述与来源标签；
  选中后填入 `/name `（不直接发送）。工具栏的命令菜单提供同一列表，便于发现。
- 图片可通过剪贴板、拖拽到输入框，或回形针的文件选择器添加。待发送图片显示为 56pt 可移除缩略图；
  已发送图片在用户气泡中以最大 200pt 渲染（[ADR-0010](decisions/0010-image-attachments.zh-CN.md)）。
- 工具调用折叠成一行摘要（SF Symbol、工具名、参数胶囊、状态），展开后显示 `Arguments` / `Output`；
  失败时保留红色描边。
- 用量用 `Gauge`（`.accessoryLinearCapacity`）加 `.monospacedDigit()` 文本，更新时数字不抖动。
- 消息列表在助手流式输出时跟随底部。用户一旦上滑就暂停跟随，并出现玻璃「回到底部」按钮
  （`.buttonStyle(.glass)`）；点击后恢复跟随。跟随基于**意图**（`isFollowingBottom`，由
  `onScrollGeometryChange` + `onScrollPhaseChange` 更新）而非单纯的底部距离判断，因此流式内容变高
  不会误停跟随。
- 打开会话时先显示玻璃加载卡片（`ProgressView` + `.glassEffect`），直到镜像历史首次渲染；
  `activate` 期间由 `SessionStore.isLoading(_:)` 暴露加载状态。
- 模型与思考等级工具栏菜单用绑定当前选中项的 `Toggle`，渲染系统原生勾选。模型按 `provider` +
  `id` 比较，因为 `get_state` 与 `get_available_models` 返回的元数据（`name`、`contextWindow`）可能不同。

## 6. 可访问性

- 所有可交互元素必须有可读标签（`.accessibilityLabel`）。
- 支持键盘导航与 VoiceOver。
- 不依赖颜色单独传达状态；对动态类型与对比度设置保持适配。

## 7. UI 自检清单

- [ ] 使用原生组件，未自造已有能力
- [ ] 玻璃效果来自系统 API，未自绘模糊
- [ ] 使用语义颜色/字体，无硬编码魔数
- [ ] 快捷键同时可从菜单触达（`Commands` / `FocusedValue`）
- [ ] 适配深浅色与辅助功能
- [ ] 引入第三方/自定义组件前已获用户同意（或已记 ADR）
