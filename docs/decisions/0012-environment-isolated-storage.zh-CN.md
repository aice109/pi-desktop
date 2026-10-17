# ADR-0012：按环境隔离 SwiftData 存储路径

[English](0012-environment-isolated-storage.md) · [简体中文](0012-environment-isolated-storage.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-17
- 决策者：项目协作者

## 背景

PiDesktop **未开启 App Sandbox**（`ENABLE_APP_SANDBOX = NO`），因此 SwiftData 存储不在按 bundle
分配的容器里。SwiftData 默认的 `ModelConfiguration` 会写入
`~/Library/Application Support/default.store` —— 一个全局共享路径。只把 Debug 的 bundle id 改成
`io.github.aice109.PiDesktop.dev` 能隔离 `UserDefaults` 与 Launch Services 身份，但**无法隔离
SwiftData 本地镜像**：从 Xcode 运行 Debug 构建仍会读写已安装 Release 版本使用的同一个 store。

本地镜像不是事实来源。pi 把会话保存为 `~/.pi/agent/sessions/...` 下的 JSONL 文件
（ADR-0005 / ADR-0009），打开会话时应用会从这些文件重建镜像。因此镜像丢失或迁移是可恢复的；
把测试写入与生产写入混进同一个 store 则不可接受。

## 候选方案

1. **保留默认 store，仅靠 bundle id 隔离** —— 最省事，但对非沙盒应用已被证实无效：SwiftData
   文件路径是共享的，Debug 运行会覆盖生产数据。
2. **两种配置都迁到以 bundle id 命名的目录，并迁移旧 store** —— 目录干净，但需要一次性迁移；
   而且已有的通用 `default.store` 可能也被机器上其他 SwiftData 应用使用，不能安全地直接接管。
3. **按配置使用两个应用专属目录**（选择）—— Release 写入
   `Application Support/PiDesktop/default.store`；Debug 写入
   `Application Support/PiDesktop-Dev/default.store`。不做迁移：本地镜像可从 pi 的 JSONL 文件重建。
4. **只给 Debug 自定义路径，Release 继续用 `default.store`** —— 保留现有 Release 数据，但通用
   文件名冲突仍在，生产数据仍放在其他应用也可能使用的路径上。

## 决策

采用方案 3。`PiDesktopApp.modelStoreURL()` 取 `URL.applicationSupportDirectory`，在 `#if DEBUG`
下追加 `PiDesktop-Dev`，否则追加 `PiDesktop`，创建目录后返回其中的 `default.store`，并传给
`ModelConfiguration(schema:url:)`。

Bundle id 仍按配置区分（Debug 为 `.dev`），因此 `UserDefaults`、Launch Services 身份、通知以及将来
的钥匙串条目都由系统隔离。

## 影响

- Debug 与 Release 不再共享 SwiftData 本地镜像；Xcode 运行不会破坏已安装版本的数据。
- pi 在 `~/.pi/agent/sessions/` 下的 JSONL 会话文件仍按工作区共享。本决策隔离的是应用本地镜像、
  偏好与系统身份，不是 pi 的源数据。
- 旧的 `~/Library/Application Support/default.store` 不再被打开，可手动删除；pi 的会话文件不受影响，
  镜像会在需要时重建。
- 若将来开启 App Sandbox，`URL.applicationSupportDirectory` 会解析到容器内，同一套代码无需再次改路径。
- 持久化相关单测仍使用内存容器；本决策只影响应用的正式容器。
