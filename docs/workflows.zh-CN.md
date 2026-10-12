# 工作流（构建 / 测试 / 调试 / 提交）

[English](workflows.md) · [简体中文](workflows.zh-CN.md)

## 1. 环境

- macOS 27.0+，Xcode（含匹配 SDK）。
- 目前无第三方依赖。
- Scheme：`PiDesktop` —— 已作为共享 scheme 提交到
  `PiDesktop.xcodeproj/xcshareddata/xcschemes/PiDesktop.xcscheme`，全新 clone / CI 无需依赖 Xcode
  自动生成即可 `-scheme` 构建；其中已包含 `PiDesktopTests` 测试 target。

> **关于共享 scheme**：`xcuserdata/` 属于用户本地状态，已加入 `.gitignore`；共享 scheme 已提交，
> 使 run/test/archive 行为显式且可复现。若新增 target 或测试 bundle，请在 Xcode「Manage Schemes」
> 中更新 scheme，或直接编辑其 XML。
>
> **关于 `requires Xcode`**：若 `xcodebuild` 报此错，是 `xcode-select` 指向了 CommandLineTools。
> 用 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` 修复，或对单条命令设置
> `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`。

## 2. 构建

```bash
# Debug
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Debug build

# Release
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop -configuration Release build

# 指定 DerivedData，便于清理
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop \
  -derivedDataPath .build/DerivedData build
```

## 3. 运行与调试

```bash
open PiDesktop.xcodeproj   # 然后在 Xcode 中 Cmd+R 运行
```

- 断点 / LLDB：Xcode 内调试。
- 视图调试：Xcode「Debug View Hierarchy」。
- 预览：源码内 `#Preview`。
- 控制台：Xcode 底部 Console 面板。

## 4. 测试

```bash
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop test
```

- 新增逻辑应补单测；UI 关键路径补 UI 测试。
- 测试命名：`test_<行为>_<条件>_<预期>`。
- `PiDesktopTests` target 承载单测（如 `SessionModelTests`），基于内存中的 SwiftData 容器。
  用例必须持有 `ModelContainer` 直到结束：`ModelContext` 不持有其容器，容器被释放后再使用 context
  会触发崩溃（SIGTRAP）。
- `PiRPCClientIntegrationTests` 会启动真实 `pi` 子进程，**默认跳过**（会调用模型、产生费用）。
  设置 `PI_INTEGRATION_TESTS=1` 或创建 `/tmp/pi_integration_enabled` 以启用。

## 5. 清理与排障

```bash
xcodebuild -project PiDesktop.xcodeproj -scheme PiDesktop clean
xcodebuild -list -project PiDesktop.xcodeproj
xcodebuild -showBuildSettings -project PiDesktop.xcodeproj -scheme PiDesktop | grep -i -E "SDK|DEPLOYMENT"
```

| 现象 | 排查 |
| --- | --- |
| `requires Xcode` | `xcode-select` 指向 CommandLineTools，见 §1 |
| scheme 不存在 | 确认 target 名与 scheme 名一致；本工程 scheme 由 autocreate 生成 |
| 签名失败 | Xcode 账号 / `DEVELOPMENT_TEAM` |
| 玻璃/新 API 不可用 | 部署目标与 SDK 是否支持该 API |
| SwiftData 容器崩溃 | 模型 schema 与迁移 |

### CI

CI **已暂不启用**：`.github/workflows/ci.yml.disabled`（GitHub 只运行 `*.yml`，因此该文件不生效），
保留作为构建配方。原因是部署目标为 macOS 27.0，GitHub 托管 runner 可能尚无匹配的 Xcode/SDK。
待有合适 runner（托管或自托管）时，重命名为 `ci.yml` 即可恢复。

工作流与本地共用 [`scripts/ci.sh`](../scripts/ci.sh)：它构建并测试，并在 `xcodebuild` 找不到 Xcode 时
自动选择 `DEVELOPER_DIR`。可直接运行：

```bash
./scripts/ci.sh
```

## 6. 提交规范

采用 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>
```

- **type**：`feat` `fix` `refactor` `perf` `docs` `style` `test` `build` `chore` `ci`
- **scope**：`chat` `session` `settings` `workspace` `agent` `glass` `docs` 等
- **subject**：祈使句、无句号、≤ 50 字符
- **body**：解释「为什么」
- **footer**：`BREAKING CHANGE:` / `Closes #123`

提交前检查：
- [ ] `xcodebuild ... build` 通过
- [ ] 无新增 warning
- [ ] 未提交密钥 / 个人路径 / `xcuserdata`
- [ ] 相关文档已更新（见 [README.zh-CN.md](README.zh-CN.md) 维护规则）
- [ ] 重大取舍已补 ADR

示例：
```
fix(session): 修复切换会话时消息列表闪烁

列表 identity 使用了数组下标，切换会话后复用错位。
改用稳定 id 后消除闪烁。

Closes #42
```

## 7. 分支与合并（建议）

- 主干 `main` 保持可构建。
- 功能分支：`feat/<scope>`、`fix/<scope>`。
- 合并前确保构建 + 测试通过、文档同步。

## 8. 禁止事项

- 提交 `xcuserdata`、`.DS_Store`、构建产物。
- 提交密钥 / token / 绝对个人路径。
- 无信息量的 commit message（`update`、`wip`、`fix bug`）。
- 绕过 §6 检查直接提交。
