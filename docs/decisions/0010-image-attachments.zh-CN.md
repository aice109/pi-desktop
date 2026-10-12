# ADR-0010: 为 prompt 附加图片

[English](0010-image-attachments.md) · [简体中文](0010-image-attachments.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-12
- 决策者：项目协作人

## 背景

pi 的 `prompt`、`steer`、`follow_up` 支持通过 `images` 传入 `ImageContent`
（`{type: "image", data: <base64>, mimeType}`，见 pi `docs/message-types.md`）。会话文件里的用户消息
也带同样的 `image` 块。PiDesktop 目前在解码时丢弃图片块、且只能发送文本，因此既看不了也发不了截图。

要渲染图片就需要本地持久化：镜像会在打开时从 pi 重建，但在两次同步之间（以及离线时）UI 仍须展示用户
附加的图片。这属于 schema 变更，按 [ADR-0004](0004-domain-model.zh-CN.md) 需要先写 ADR。

## 选项

1. **新增 `MessageImage` SwiftData 模型**（选用）—— 每张图片一行，字节存于 `@Attribute(.externalStorage)`。
   图片从属于消息、按时间线顺序渲染，也能从历史自然导入。
2. **只发送、从 pi 重新导入** —— 不改 schema，但图片在下次同步前会从本地镜像消失、输入框也无法预览；
   离线历史会丢图。
3. **落盘为文件、按路径引用** —— store 更小，但增加生命周期/清理负担，也破坏「单一 SwiftData 镜像」模型。

## 决策

选用选项 1。

- `AgentImage` 是传输层值（原始 `data` + `mimeType`）；`PiRPCClient` 将其 base64 编码进线缆的 `images`。
  `AgentTransport.prompt/steer/followUp` 接收 `images: [AgentImage]`。
- `MessageImage` 是持久化模型：`mimeType`、`data`（`.externalStorage`），并从 `Message` 级联删除。
  `Message.images` 按插入顺序排列。
- 历史解析保留 `image` 块：`MessageContentDTO` 分离文本与图片，`PiHistory` 产出 `PiDisplayImage`，
  由镜像插入 `MessageImage` 行。
- 输入框支持从剪贴板粘贴、文件选择器、拖拽三种方式添加图片，显示缩略图与移除按钮，并随下一条消息发送。
  用户消息会渲染其图片。

## 影响

- Schema 变更：新增 `MessageImage` 模型与 `Message` 关系。应用**尚未发布**，轻量迁移 / 重置 store 可接受。
- base64 是 pi 线缆格式的一部分，因此跨 RPC 边界时编码；store 保留原始 `Data`，避免二次编码。
  截图用外部存储，SQLite 文件保持较小。
- 仅支持光栅图片（png/jpeg/gif/webp/heic）；任意文件附件不在范围内。
- 不支持消息编辑（替换图片）；输入框采用「移除再添加」。
- 暂未对超大图片做缩放/限流；后续可加体积上限。

## 相关

- [ADR-0004](0004-domain-model.zh-CN.md) —— `Session` / `Message`
- [ADR-0007](0007-reasoning.zh-CN.md) —— 同类「持久化内容块」的决策
- [pi-agent.md](../pi-agent.zh-CN.md) —— 事件模型与 prompt 命令
