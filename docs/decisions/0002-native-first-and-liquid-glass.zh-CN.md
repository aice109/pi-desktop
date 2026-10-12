# ADR-0002: 原生组件优先、采用液态玻璃、第三方/自定义需先确认

[English](0002-native-first-and-liquid-glass.md) · [简体中文](0002-native-first-and-liquid-glass.zh-CN.md)

- 状态：Accepted
- 日期：2026-10-12
- 决策者：项目初始协作者（依据用户要求）

## 背景

PiDesktop 要成为一个与 macOS 系统观感一致、轻量、长期可维护的 pi agent 客户端。若随意引入第三方依赖或自绘组件，会带来包体积膨胀、维护负担、观感割裂，以及许可风险。同时用户明确要求：使用原生组件、采用 Liquid Glass 效果、引入第三方或自定义组件前必须询问。

## 候选方案

1. **原生优先 + 系统液态玻璃 + 变更先确认**（本决策）。
2. **不设限，按需引依赖/自造组件**：短期灵活，长期失控。
3. **完全禁止第三方/自定义**：过于僵化，个别场景确实无原生解。

## 决策

采用方案 1：

- **原生优先**：优先 SwiftUI / AppKit / Foundation / SwiftData 等 Apple 原生框架，能内置解决就不自造。
- **液态玻璃**：遵循 macOS Liquid Glass，使用 `.glassEffect()`、`GlassEffectContainer`、`.buttonStyle(.glass)`、`NSGlassEffectView` 等系统 API，禁止自绘模糊模拟。
- **先问后加**：引入第三方依赖、自建组件替代原生能力、引入非 SF Symbols 资源，必须先向用户说明理由、候选方案与影响，获得明确同意（并视情况记 ADR）后方可实施。

## 影响

- 正面：观感一致、依赖可控、可维护性与可访问性更好。
- 负面：个别需求可能原生支持有限，需要更多探索或明确告知用户。
- 后续：`AGENTS.md` §2、`docs/design-system.md`、`docs/coding-conventions.md` 均已固化为强制规则。
