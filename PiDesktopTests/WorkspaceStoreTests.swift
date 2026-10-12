//
//  WorkspaceStoreTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
@testable import PiDesktop

/// `WorkspaceStore` 的选择与最近列表持久化测试。
@MainActor
final class WorkspaceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "WorkspaceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeStore() -> WorkspaceStore {
        // 指向不存在的会话根目录，扫描结果为空的列表。
        WorkspaceStore(defaults: defaults, root: URL(fileURLWithPath: "/tmp/pi-sessions-tests"))
    }

    func test_setWorkspace_recordsRecentAndPersists() {
        let store = makeStore()
        XCTAssertNil(store.workspace)
        XCTAssertTrue(store.recentWorkspaces.isEmpty)

        store.setWorkspace(URL(fileURLWithPath: "/tmp/proj-a"))
        store.setWorkspace(URL(fileURLWithPath: "/tmp/proj-b"))

        XCTAssertEqual(store.workspace?.lastPathComponent, "proj-b")
        XCTAssertEqual(store.recentWorkspaces.map(\.lastPathComponent), ["proj-b", "proj-a"])

        // 新实例应从 UserDefaults 恢复目录与最近列表。
        let reloaded = makeStore()
        XCTAssertEqual(reloaded.workspace?.lastPathComponent, "proj-b")
        XCTAssertEqual(reloaded.recentWorkspaces.map(\.lastPathComponent), ["proj-b", "proj-a"])
    }

    func test_setWorkspace_deduplicatesAndCapsRecents() {
        let store = makeStore()
        for index in 0..<9 {
            store.setWorkspace(URL(fileURLWithPath: "/tmp/proj-\(index)"))
        }
        // 重复选择已存在的目录应被提到最前，而不是重复出现。
        store.setWorkspace(URL(fileURLWithPath: "/tmp/proj-5"))

        XCTAssertEqual(store.recentWorkspaces.count, 6)
        XCTAssertEqual(store.recentWorkspaces.first?.lastPathComponent, "proj-5")
        XCTAssertEqual(Set(store.recentWorkspaces.map(\.lastPathComponent)).count, 6)
    }

    func test_clearWorkspace_keepsRecents() {
        let store = makeStore()
        store.setWorkspace(URL(fileURLWithPath: "/tmp/proj-a"))
        store.clearWorkspace()

        XCTAssertNil(store.workspace)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(store.recentWorkspaces.map(\.lastPathComponent), ["proj-a"])
        XCTAssertNil(defaults.string(forKey: WorkspaceStore.workspacePathKey))
    }
}
