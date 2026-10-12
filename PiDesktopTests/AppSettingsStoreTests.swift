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
}
