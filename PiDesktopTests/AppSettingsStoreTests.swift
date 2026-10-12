//
//  AppSettingsStoreTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import XCTest
@testable import PiDesktop

/// `AppSettingsStore` 的默认值、写穿与持久化测试。
@MainActor
final class AppSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "AppSettingsStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func test_defaults() {
        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertNil(settings.appearance.colorScheme)
        XCTAssertTrue(settings.restoreLastSession)
        XCTAssertTrue(settings.showUsageFooter)
        XCTAssertTrue(settings.confirmDeletion)
        XCTAssertNil(settings.lastSessionPath)
    }

    func test_changes_arePersistedAndReloaded() {
        let settings = AppSettingsStore(defaults: defaults)
        settings.appearance = .dark
        settings.restoreLastSession = false
        settings.showUsageFooter = false
        settings.confirmDeletion = false
        settings.lastSessionPath = "/tmp/session.jsonl"

        let reloaded = AppSettingsStore(defaults: defaults)
        XCTAssertEqual(reloaded.appearance, .dark)
        XCTAssertEqual(reloaded.appearance.colorScheme, .dark)
        XCTAssertFalse(reloaded.restoreLastSession)
        XCTAssertFalse(reloaded.showUsageFooter)
        XCTAssertFalse(reloaded.confirmDeletion)
        XCTAssertEqual(reloaded.lastSessionPath, "/tmp/session.jsonl")
    }

    func test_clearingLastSessionPath_removesKey() {
        let settings = AppSettingsStore(defaults: defaults)
        settings.lastSessionPath = "/tmp/session.jsonl"
        settings.lastSessionPath = nil
        XCTAssertNil(defaults.string(forKey: AppSettingsStore.Keys.lastSessionPath))
    }

    func test_emptyStoredPath_isTreatedAsNil() {
        defaults.set("", forKey: AppSettingsStore.Keys.lastSessionPath)
        XCTAssertNil(AppSettingsStore(defaults: defaults).lastSessionPath)
    }

    func test_reset_restoresDefaults() {
        let settings = AppSettingsStore(defaults: defaults)
        settings.appearance = .light
        settings.confirmDeletion = false
        settings.reset()
        XCTAssertEqual(settings.appearance, .system)
        XCTAssertTrue(settings.confirmDeletion)
        XCTAssertNil(settings.lastSessionPath)
    }

    func test_appearanceLabels_andColorSchemes() {
        XCTAssertEqual(AppAppearance.allCases.map(\.label), ["System", "Light", "Dark"])
        XCTAssertEqual(AppAppearance.light.colorScheme, .light)
        XCTAssertEqual(AppAppearance.dark.colorScheme, .dark)
    }

    func test_sessionToRestore_matchesThePreviouslyOpenedSession() {
        let settings = AppSettingsStore(defaults: defaults)
        let first = Self.summary(path: "/tmp/sessions/a.jsonl")
        let second = Self.summary(path: "/tmp/sessions/b.jsonl")
        settings.lastSessionPath = second.fileURL.path

        XCTAssertEqual(settings.sessionToRestore(among: [first, second]), second)
        // 会话已被删除（或换到别的工作区）：不恢复。
        XCTAssertNil(settings.sessionToRestore(among: [first]))
    }

    func test_sessionToRestore_isDisabledByPreference() {
        let settings = AppSettingsStore(defaults: defaults)
        let summary = Self.summary(path: "/tmp/sessions/a.jsonl")
        settings.lastSessionPath = summary.fileURL.path
        settings.restoreLastSession = false
        XCTAssertNil(settings.sessionToRestore(among: [summary]))
    }

    func test_sessionToRestore_isNilWithoutStoredPath() {
        let settings = AppSettingsStore(defaults: defaults)
        XCTAssertNil(settings.sessionToRestore(among: [Self.summary(path: "/tmp/sessions/a.jsonl")]))
    }

    private static func summary(path: String) -> PiSessionSummary {
        PiSessionSummary(
            sessionID: URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            fileURL: URL(fileURLWithPath: path),
            name: nil,
            cwd: "/tmp",
            startedAt: nil,
            updatedAt: Date(timeIntervalSince1970: 0),
            messageCount: 0,
            preview: nil
        )
    }
}
