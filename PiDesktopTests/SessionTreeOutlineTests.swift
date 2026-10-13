//
//  SessionTreeOutlineTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest

@testable import PiDesktop

/// 会话树压平（`AgentSessionTree.outlineRows`）的测试。
///
/// 重点覆盖修复「显示会话树卡住」的两个不变量：
/// 1. 线性会话（每个节点只有一个子节点）不累积缩进、只平铺成一层；
/// 2. 活动分支可被正确标出，折叠会隐藏子树。
final class SessionTreeOutlineTests: XCTestCase {
    private func node(
        _ id: String,
        parent: String? = nil,
        role: String? = "assistant",
        preview: String = "",
        label: String? = nil,
        children: [AgentTreeNode] = []
    ) -> AgentTreeNode {
        AgentTreeNode(
            id: id,
            parentId: parent,
            kind: "message",
            preview: preview,
            role: role,
            isUserMessage: role == "user",
            children: children,
            label: label
        )
    }

    /// 线性会话：一条长链全部保持 0 级缩进，不会越缩越深。
    func test_linearChain_keepsFlatIndent() {
        func chain(from start: Int, to end: Int, parent: String?) -> AgentTreeNode {
            let id = "e\(start)"
            let child = start < end ? chain(from: start + 1, to: end, parent: id) : nil
            return node(
                id,
                parent: parent,
                role: start == 1 ? "user" : "assistant",
                children: child.map { [$0] } ?? []
            )
        }
        let root = chain(from: 1, to: 50, parent: nil)
        let tree = AgentSessionTree(roots: [root], leafId: "e50")

        let rows = tree.outlineRows(collapsed: [])

        XCTAssertEqual(rows.count, 50)
        XCTAssertTrue(rows.allSatisfy { $0.indent == 0 }, "线性会话不应累积缩进")
        XCTAssertTrue(rows.allSatisfy(\.isOnActivePath), "整条链都在活动分支上")
        XCTAssertEqual(rows.last?.id, "e50")
        XCTAssertTrue(rows.last?.isActiveLeaf ?? false)
    }

    /// 分叉：分支子节点缩进一级，未选中分支不在活动路径上。
    func test_branch_indentsChildrenAndMarksActivePath() {
        let abandoned = node("b2", parent: "b1", preview: "abandoned")
        let active = node("b3", parent: "b1", preview: "active")
        let root = node("b1", role: "user", children: [abandoned, active])
        let tree = AgentSessionTree(roots: [root], leafId: "b3")

        let rows = tree.outlineRows(collapsed: [])

        XCTAssertEqual(rows.map(\.id), ["b1", "b2", "b3"])
        XCTAssertEqual(rows.map(\.indent), [0, 1, 1])
        XCTAssertTrue(rows[0].isOnActivePath)
        XCTAssertFalse(rows[1].isOnActivePath, "被遗弃分支不应在活动路径上")
        XCTAssertTrue(rows[2].isOnActivePath)
        XCTAssertTrue(rows[2].isActiveLeaf)
    }

    /// 单子节点延续父级缩进，只有真正的分叉才加深。
    func test_singleChild_doesNotDeepenIndent() {
        let grandchild = node("c3", parent: "c2")
        let child = node("c2", parent: "c1", children: [grandchild])
        let root = node("c1", children: [child])
        let tree = AgentSessionTree(roots: [root], leafId: "c3")

        let rows = tree.outlineRows(collapsed: [])

        XCTAssertEqual(rows.map(\.indent), [0, 0, 0])
    }

    /// 折叠节点后隐藏其后代。
    func test_collapsedHidesDescendants() {
        let grandchild = node("d3", parent: "d2")
        let child = node("d2", parent: "d1", children: [grandchild])
        let root = node("d1", role: "user", children: [child])
        let tree = AgentSessionTree(roots: [root], leafId: "d3")

        let expanded = tree.outlineRows(collapsed: [])
        XCTAssertEqual(expanded.map(\.id), ["d1", "d2", "d3"])
        XCTAssertTrue(expanded[0].isExpandable)

        let collapsed = tree.outlineRows(collapsed: ["d1"])
        XCTAssertEqual(collapsed.map(\.id), ["d1"])
    }

    /// 预览压成单行并截断；标签透传。
    func test_previewIsCollapsedAndLabelKept() {
        let root = node(
            "e1",
            role: "user",
            preview: "line one\nline two   with   spaces",
            label: "checkpoint-1"
        )
        let tree = AgentSessionTree(roots: [root], leafId: "e1")

        let rows = tree.outlineRows(collapsed: [])

        XCTAssertEqual(rows.first?.preview, "line one line two with spaces")
        XCTAssertEqual(rows.first?.label, "checkpoint-1")
    }
}
