//
//  SessionTreeOutline.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 扁平化后的会话树一行：只保留渲染需要的字段 + 分支缩进与活动分支标记。
///
/// `get_tree` 返回的是递归结构，直接交给 `OutlineGroup` 会按层级递归构造嵌套视图。
/// 而真实会话几乎总是**线性**的（每个条目只有一个子条目），于是树退化成一条长链：
/// 上百层嵌套视图会让布局/渲染卡死。这里先把树压平成一维行数组再交给 `List`：
/// - 视图深度恒为 1，与会话长度无关；
/// - 只有真正的分叉才增加缩进层级，线性段不累积缩进（否则文本会被顶到屏幕外）；
/// - 每行只持有标量字段，不复制整棵子树，避免 O(n²) 的内存放大。
nonisolated struct SessionTreeOutlineRow: Identifiable, Equatable, Sendable {
    /// 条目 id（`get_tree` 的 `entry.id`）。
    var id: String
    var parentId: String?
    /// 条目类型（`message` / `bashExecution` / 其他）。
    var kind: String
    /// 展示用预览文本（已压成单行并截断）。
    var preview: String
    var role: String?
    /// pi 在该条目上设置的标签 / 书签（`label`）。
    var label: String?
    /// 是否为可 fork 的用户消息。
    var isUserMessage: Bool
    /// 是否拥有子节点（决定是否显示展开箭头）。
    var isExpandable: Bool
    /// 展示缩进层级：只统计「有多个子节点」的祖先，线性会话恒为 0。
    var indent: Int
    /// 是否位于从根到活动叶子的路径上。
    var isOnActivePath: Bool
    /// 是否为当前活动叶子。
    var isActiveLeaf: Bool
}

extension AgentSessionTree {
    /// 把递归树压平成可线性渲染的行；`collapsed` 中的节点会隐藏其子树。
    ///
    /// - Parameter collapsed: 已折叠节点的 id 集合。
    func outlineRows(collapsed: Set<String>) -> [SessionTreeOutlineRow] {
        let activePath = activePathIDs()
        var rows: [SessionTreeOutlineRow] = []

        func visit(_ node: AgentTreeNode, indent: Int) {
            rows.append(
                SessionTreeOutlineRow(
                    id: node.id,
                    parentId: node.parentId,
                    kind: node.kind,
                    preview: Self.singleLinePreview(node.preview),
                    role: node.role,
                    label: node.label,
                    isUserMessage: node.isUserMessage,
                    isExpandable: !node.children.isEmpty,
                    indent: indent,
                    isOnActivePath: activePath.contains(node.id),
                    isActiveLeaf: node.id == leafId
                ))
            guard !collapsed.contains(node.id) else { return }
            // 分叉才缩进：单子节点延续当前层级，避免线性会话缩进无限增长。
            let childIndent = node.children.count > 1 ? indent + 1 : indent
            for child in node.children {
                visit(child, indent: childIndent)
            }
        }

        for root in roots { visit(root, indent: 0) }
        return rows
    }

    /// 从活动叶子沿 `parentId` 回溯出活动分支的 id 集合；无叶子信息时为空。
    private func activePathIDs() -> Set<String> {
        guard let leafId else { return [] }

        var byID: [String: AgentTreeNode] = [:]
        func collect(_ nodes: [AgentTreeNode]) {
            for node in nodes {
                byID[node.id] = node
                collect(node.children)
            }
        }
        collect(roots)
        guard byID[leafId] != nil else { return [] }

        var path: Set<String> = []
        var current: String? = leafId
        // 防御性上限：即使数据里有环也不会死循环。
        for _ in 0...byID.count {
            guard let id = current, let node = byID[id] else { break }
            path.insert(id)
            current = node.parentId
        }
        return path
    }

    /// 预览文本压成单行并截断：列表行只显示一行，避免超长内容拖慢文本测量。
    private static func singleLinePreview(_ text: String, limit: Int = 160) -> String {
        let collapsed = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        guard collapsed.count > limit else { return collapsed }
        return String(collapsed.prefix(limit)) + "…"
    }
}
