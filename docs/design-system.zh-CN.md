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

### 布局 token

侧栏尺寸集中在 `DesignTokens.Layout`：`sidebarWidth`（280pt）既是默认打开宽度，也是硬性最小宽度。
它被两处一同保证：`.frame(minWidth: sidebarWidth)` 让内容永远不被裁切；一个小型 AppKit 桥接
（`SidebarSplitItemConfigurator`）向上找到原生 `NSSplitViewController`，把侧栏项的 `minimumThickness`
钉到同一值（否则 SwiftUI 会保留约 140pt 的系统侧栏最小值，分隔条会在折叠前滑进去几个点）。
`navigationSplitViewColumnWidth(min:ideal:)` 锁定为同一值，分隔条向内拖时原生 `NavigationSplitView`
会收起侧栏，向外拖则照常变宽。

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

- 顶部工作区栏是一张**玻璃大卡片**（`.glassEffect`），同时充当项目切换器：淡色文件夹徽标 +
  项目名 + 家目录缩写路径（`~/Developer/PiDesktop`，经 `PathDisplay`）+ 带圆圈的 chevron 提示可点。
  点击弹出浮层，按最近使用列出项目（当前项打勾），并提供「选择文件夹…」与「关闭工作区」。
  去掉原先的生硬分隔线，改由分组表头分隔列表。
- 聊天界面的窗口副标题仅在会话工作目录与当前项目不一致时显示，避免与侧边栏重复展示同一条路径。
- 会话放在 `.sidebar` 的 `List` 中，归到带计数的「Sessions」分组表头下。行内为图标 + 标题 + 次要信息
  （相对时间 · 消息数），并带少量垂直留白，使每行都是独立的点击目标。
- 侧栏有一个固定的最小宽度，与默认打开宽度相同（`DesignTokens.Layout.sidebarWidth`，280pt），由侧栏
  内容的 `.frame(minWidth:)` 加上一个把原生侧栏项 `minimumThickness` 钉住的 AppKit 桥接共同保证，
  工作区卡片与会话标题永不被裁切。分隔条向内拖时原生 `NavigationSplitView` 会收起为仅详情，向外拖则
  照常变宽。
- 回合结束时若该会话不是当前可见会话，行尾显示淡色未读圆点；打开会话即清除。同一事件在应用处于
  后台时会发出系统通知（`UserNotifications`），见 `Core/Notifications/TurnNotifier.swift`。

### 聊天界面约定

- 消息使用 plain `List` 并隐藏行分隔线；连续同一角色的消息共用一条头部（角色头像 + 名称），
  减少视觉噪音。
- 时间线按**回合**分组（一条用户消息到下一个之前）。每个回合依次渲染提问、一个**过程**大折叠，
  以及该回合最后一条助手正文（「结论」）。折叠区把思考、工具调用、中间旁白统一收进一个
  `DisclosureGroup`，默认收起，并以步数 + 涉及工具作为摘要；因此结论始终排在工具调用*之后*。
- 助手输出按 pi 的每条消息拆分成独立的 `Message`：工具调用之后产生的文本会新起一条，
  而不是追加到本轮开头的占位气泡；每段在收到 `message_end` 时落盘（`SessionStore`）。
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
- 工具栏按钮切换窗口右侧的**对话锚点**面板（原生 `.inspector`，默认关闭，偏好可跨启动保留）。
  每个回合一行（序号徽标 + 提问 + 结论首行），选中即滚动到对应回合（与搜索共用滚动目标）。
  锚点由本地镜像推导，列表即时可用，无需等待 RPC。
- 工具栏提供 Context 菜单（`arrow.down.right.and.arrow.up.left`）：「Compact Now」「Compact with
  Instructions…」（小弹窗）、绑定 `get_state` 的 Auto-compaction `Toggle`，以及 Auto-retry `Toggle`。
  只要会话有进行中的工作（流式 / 压缩 / 重试 / 导出 / 克隆 / 分叉），状态区就会显示
  （`SessionStore.isBusy(_:)`），因此手动压缩也有与回合一致的 `ProgressView`；压缩进行中两个压缩入口
  会自动禁用。重试进行时状态行会显示「Abort Retry」链接。
- 工具栏提供 Branch 菜单（`arrow.triangle.branch`），包含「Clone Session」与「Fork from Message…」；
  后者打开列出可 fork 用户消息的弹窗。选中后会 fork 并把原文本回填输入框，同一流程即「编辑并重发」。
  菜单还含「Show Tree…」，渲染完整会话树（`get_tree`，包括被遗弃分支）并高亮活动叶子，pi 标签以书签
  胶囊显示；用户节点上带 Fork 操作。弹窗出现后异步加载树，点击即时反馈；树被**压平成一维行数组**
  （`SessionTreeOutline.swift`）而非递归的 `OutlineGroup`——真实会话多为线性，递归会为每个条目嵌一层
  视图，长会话下卡死。只有真正的分叉才增加缩进，线性链保持齐平而不是越缩越偏。
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
- 消息列表末尾有一个轻量结束标记（细线夹着 `arrow.down.to.line` 图标），同时充当列表底部留白，
  最后一条消息不会紧贴输入框；滚动指示器带少量边距（`.scrollIndicators`），避免两端被列表边界截断。
- 打开会话时先显示玻璃加载卡片（`ProgressView` + `.glassEffect`），直到镜像历史首次渲染；
  `activate` 期间由 `SessionStore.isLoading(_:)` 暴露加载状态。
- 耗时的用户操作（压缩、导出、克隆、分叉、复制最后回复）通过窗口顶部的玻璃提示横幅反馈结果：
  成功数秒后自动消失，失败保留到用户关闭。工作区错误（选择目录、移到废纸篓）改用系统 alert 呈现，
  不再被静默吞掉。横幅是系统 `.glassEffect` 卡片，不是自绘材质。
- 模型与思考等级工具栏菜单用绑定当前选中项的 `Toggle`，渲染系统原生勾选。模型按 `provider` +
  `id` 比较，因为 `get_state` 与 `get_available_models` 返回的元数据（`name`、`contextWindow`）可能不同。

## 6. 本地化

- 本地化使用 String Catalog（`PiDesktop/Localizable.xcstrings`）。`Text` / `Label` / `Button` 的字面量
  与非视图代码用 `String(localized:)` 产出的状态文案都是键；目前只提供 `zh-Hans`，未翻译的键回退英文。
  新增语言只需在 Xcode 工程（`knownRegions`）里添加并填充 catalog，无需改代码。

## 7. 可访问性

- 所有可交互元素必须有可读标签（`.accessibilityLabel`）。
- 支持键盘导航与 VoiceOver。
- 不依赖颜色单独传达状态；对动态类型与对比度设置保持适配。

## 8. UI 自检清单

- [ ] 使用原生组件，未自造已有能力
- [ ] 玻璃效果来自系统 API，未自绘模糊
- [ ] 使用语义颜色/字体，无硬编码魔数
- [ ] 快捷键同时可从菜单触达（`Commands` / `FocusedValue`）
- [ ] 适配深浅色与辅助功能
- [ ] 引入第三方/自定义组件前已获用户同意（或已记 ADR）
