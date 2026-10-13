//
//  PathDisplay.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 界面上的路径展示工具。
///
/// 侧栏与窗口标题只需让用户认出项目，完整绝对路径（`/Users/...`）既冗长又暴露用户名，
/// 因此统一把家目录缩写为 `~`（如 `/Users/me/Developer` → `~/Developer`）。
/// 会话元数据等底层逻辑仍使用绝对路径，这里只服务显示层。
enum PathDisplay {
    /// 把绝对路径缩写为便于阅读的形式；家目录替换为 `~`，其余原样保留。
    static func abbreviated(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return (path as NSString).abbreviatingWithTildeInPath
    }

    /// `URL` 便捷重载；`nil` 返回空串，便于直接绑定到 `Text`。
    static func abbreviated(_ url: URL?) -> String {
        guard let url else { return "" }
        return abbreviated(url.path)
    }
}
