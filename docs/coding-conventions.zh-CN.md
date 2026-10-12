# 编码规范

[English](coding-conventions.md) · [简体中文](coding-conventions.zh-CN.md)

面向 Swift / SwiftUI 代码。写代码前阅读。

## 1. 通用原则

- 遵循 Swift API Design Guidelines 与既有代码风格。
- 小步提交，每次改动尽可能小且可编译。
- 不做与当前任务无关的重构，除非它直接服务于该任务。
- 优先清晰 > 简短 > 炫技。

## 2. 命名

- 类型 `UpperCamelCase`，方法/属性/变量 `lowerCamelCase`。
- 布尔用 `is/has/should/can` 前缀（`isLoading`）。
- 避免缩写（`vc`、`mgr`），领域术语除外。
- View 一律 `XxxView`，Model 用领域名。

## 3. 文件组织

- **一个文件一个主类型**，文件名与类型一致。
- 按功能域组织目录（见 [architecture.zh-CN.md](architecture.zh-CN.md)）。
- 相关小类型（如 View 的私有子视图）可与主类型同文件，但保持可读。

## 4. SwiftUI

- 视图保持**声明式、无副作用**；副作用放 ViewModel/Store。
- 拆小视图，避免巨大 `body`；用 `#Preview` 提供预览。
- 状态优先级：`@State` → `@Observable` 模型 → `@Environment`；谨慎使用 `@StateObject`/`@ObservedObject`（优先 Observation）。
- 用 `@MainActor` 标注 UI 状态类型。
- 修饰符顺序保持可读；复杂样式抽成 `ViewModifier` 或 `View` 扩展（在 `DesignSystem/`）。

## 5. 并发

- 使用 Swift Concurrency（`async/await`、`Task`、`actor`、`AsyncStream`）。
- UI 更新必须在主 actor；跨 actor 传值需 `Sendable`。
- 长生命周期任务需可取消，避免任务泄漏。
- 不要在 `body` 中启动未受控的 `Task`。

## 6. 数据与持久化

- SwiftData：`@Model` 类型保持纯数据 + 轻逻辑。
- 查询用 `@Query` / `FetchDescriptor`；避免在 View 中做重计算。
- 模型结构变更需考虑迁移，并记 ADR。

## 7. 错误处理

- 用 `throws` / `Result` 表达可恢复错误，避免静默失败。
- 面向用户展示可理解的错误，不暴露堆栈。
- 致命初始化失败可用 `fatalError`，其余走错误路径。

## 8. 依赖与封装

- 通信、存储等外部能力通过协议抽象，便于替换与测试。
- **引入任何第三方依赖前必须先询问**（见 [AGENTS.zh-CN.md §2.3](../AGENTS.zh-CN.md)）。

## 9. 注释规则

**总原则：尽可能注释，但不什么都注释。** 拿不准时，优先问「这条注释能不能让下一个读代码的人少花五分钟？」能就写，不能就删。

### 9.1 必须注释的情况

- **公共 API / 类型**：用 `///` 文档注释，说明用途、参数、返回值、副作用。
- **不明显的"为什么"**：某个看似多余的判断、特殊分支、兼容性分支背后一定有原因，必须写。
- **约束与坑**：并发/线程要求、生命周期、调用顺序、系统 API 的隐藏行为。
- **魔法数字 / 魔字符串**：解释取值来源或含义。
- **Workaround / 临时绕行**：注明原因与移除条件，例如 `// TODO(#123): 待系统修复 X 后移除。`
- **复杂算法 / 非直观逻辑**：先写思路/不变量，再给实现。
- **文件/类型职责**：每个类型顶部一句说明它负责什么（尤其是 Store / Service / ViewModel）。

### 9.2 不要注释的情况

- **自解释的代码**：`title = "设置"` 不需要 `// 设置标题`。
- **复述签名**：`/// 获取用户` 之于 `func fetchUser()` 是噪音。
- **注释掉的死代码**：直接删，需要时用 git 历史回溯。
- **过度分段**：给每一行都加标题式注释，反而淹没关键信息。
- **与代码不同步的注释**：比没有注释更危险，改代码时必须同步改注释。

### 9.3 风格

- 文件头用 Xcode 默认的创建信息，不额外堆砌。
- 行内注释用 `//`，放在被解释代码的上一行（而非行尾对齐），除非极短。
- 默认英文；公共/开源 API 可双语。

## 10. 质量门

- 构建通过，无新增 warning。
- 无强制解包 `!`（除非确有保证并注释说明）。
- 无残留 `print`（改用日志）。
- 无硬编码密钥、绝对路径。
