//
//  PathDisplayTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest

@testable import PiDesktop

/// `PathDisplay` 的家目录缩写测试。
final class PathDisplayTests: XCTestCase {
    func test_emptyPath_staysEmpty() {
        XCTAssertEqual(PathDisplay.abbreviated(""), "")
        XCTAssertEqual(PathDisplay.abbreviated(URL?.none), "")
    }

    func test_homeDirectory_isAbbreviated() {
        let home = NSHomeDirectory()
        XCTAssertEqual(PathDisplay.abbreviated(home), "~")
        XCTAssertEqual(PathDisplay.abbreviated("\(home)/Developer/PiDesktop"), "~/Developer/PiDesktop")
    }

    func test_outsideHome_isUnchanged() {
        XCTAssertEqual(PathDisplay.abbreviated("/tmp/some-project"), "/tmp/some-project")
    }

    func test_urlOverload_delegatesToPath() {
        let home = NSHomeDirectory()
        XCTAssertEqual(PathDisplay.abbreviated(URL(fileURLWithPath: "\(home)/Developer")), "~/Developer")
    }
}
