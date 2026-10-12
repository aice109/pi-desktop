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
| 富文本/Markdown | 优先原生 `Text` / `AttributedString`，复杂渲染需确认 |

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
- **圆角**：与系统一致；玻璃容器用 `.rect(cornerRadius:)` 显式给出。
- **图标**：SF Symbols，配套 `.symbolRenderingMode` / `.imageScale`。

> 若需新增设计 token，先扩本节，再落代码；重大设计取舍 → 记 ADR。

### 聊天界面约定

- 消息使用 plain `List` 并隐藏行分隔线；连续同一角色的消息共用一条头部（角色头像 + 名称），
  减少视觉噪音。
- 用户消息用淡色气泡（`.tint.opacity(0.12)`）；助手消息保持纯文本，便于 Markdown 阅读。
- 输入框是带聚焦描边的圆角字段，发送为 `.borderedProminent` 圆形按钮（⌘↩）；流式状态行置于
  `.thinMaterial` 的 `Capsule` 中——属于系统预期的叠加层，不是自绘模糊。
- 工具调用按工具名映射 SF Symbol，参数用等宽字体胶囊，失败时加红色描边。
- 用量用 `Gauge`（`.accessoryLinearCapacity`）加 `.monospacedDigit()` 文本，更新时数字不抖动。

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
