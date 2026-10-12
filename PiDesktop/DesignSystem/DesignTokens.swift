//
//  DesignTokens.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import CoreGraphics

/// 全局视觉常量。
///
/// 设计系统约定「圆角与系统一致、间距用 4/8 的倍数」（见 `docs/design-system.md` §5）。
/// 把散落在各视图里的圆角收敛到这里，改动时只维护一处，也便于整体保持一致。
enum DesignTokens {
    /// 圆角半径。整体刻意偏小，贴近 macOS 原生控件的克制观感。
    enum Radius {
        /// 行内小胶囊：工具参数、标签。
        static let chip: CGFloat = 4
        /// 内嵌小块：代码块、工具输出。
        static let small: CGFloat = 6
        /// 卡片与消息气泡。
        static let card: CGFloat = 8
        /// 较大的控件：输入框。
        static let control: CGFloat = 10
    }
}
