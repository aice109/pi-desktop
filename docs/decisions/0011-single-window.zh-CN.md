# ADR-0011：单一主窗口

[English](0011-single-window.md) · [简体中文](0011-single-window.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-12
- 决策者：项目协作者

## 背景

主场景是 `WindowGroup`，其中持有在 `PiDesktopApp.init` 里创建一次的三个应用级 Store
（`SessionStore`、`WorkspaceStore`、`AppSettingsStore`）。`WindowGroup` 允许用户打开多个主窗口
（File ▸ New Window），而所有窗口共享这些 Store。

`SessionStore` 是按**单一归属**设计的：

- `transports` / `subscriptions` / `states` 以 `Session.id` 为键，两个窗口打开同一会话就会共享一个
  pi 子进程并争抢其事件流。
- `visibleSessionID` 是单值，用于判定未读与通知（本 ADR 之后引入）。两个窗口查看不同会话时它必然出错。
- 只有一个窗口的 `ContentView` 设置 `focusedSceneValue(\.sessionCommands)`；菜单命令作用于聚焦窗口，
  但它改动的 Store 是共享的。

结果是难以察觉的错误而非崩溃：未读红点错误、同一会话的流被两处驱动、命令效果难以预测。真正的多窗口
支持需要把 Store（及其 pi 子进程）按窗口隔离，并重新设计 SwiftData context 的共享方式。

## 候选方案

1. **保留 `WindowGroup`，仅记录限制** —— 最省事，但留下一个“看起来能用”的陷阱。
2. **按窗口隔离 Store** —— 多窗口正确，但改造量大：每窗口独立 Store、独立 pi 进程、每个命令都要重接
   `@FocusedValue`，还要重新验证跨 context 的模型容器。当前并不需要同时跑多个会话。
3. **主界面改为单一 `Window`**（选择）—— 只有一个主窗口，单一归属的 Store 永远正确。“New Session”
   仍是应用内开始新工作的方式。

## 决策

采用方案 3。`PiDesktopApp` 用 `Window("PiDesktop", id: "main")` 取代 `WindowGroup`。`Settings` 场景
不变，⌘, 仍可打开偏好设置。

## 影响

- 共享 Store 的不变量（`visibleSessionID`、每会话一个传输）始终成立。
- File ▸ New Window 消失；用户在同一窗口内用「New Session」（⌘N）切换工作。
- 若将来确实需要多窗口，即方案 2 —— 需新增一个取代本 ADR 的 ADR，并完成按窗口隔离 Store 的改造。
