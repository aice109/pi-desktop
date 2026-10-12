//
//  CodeSyntaxHighlighterTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
import SwiftUI
@testable import PiDesktop

/// 轻量代码高亮的词法测试。
final class CodeSyntaxHighlighterTests: XCTestCase {
    /// 分类便捷断言：返回指定类别下的文本片段。
    private func texts(_ kind: CodeTokenKind, in code: String, language: String? = nil) -> [String] {
        CodeSyntaxHighlighter.tokens(code, language: language)
            .filter { $0.kind == kind }
            .map(\.text)
    }

    func test_tokens_reassembleTheSourceExactly() {
        let samples = [
            "let value = 42 // answer",
            "func greet(name: String) -> String { return \"hi \\(name)\" }",
            "/* block */ x = 0x1F + 3.14",
            "if (a && b) { console.log('x') }",
            "# a comment\nprint('hi')",
        ]
        for code in samples {
            let joined = CodeSyntaxHighlighter.tokens(code, language: nil).map(\.text).joined()
            XCTAssertEqual(joined, code, "词法单元必须无损还原源码：\(code)")
        }
    }

    func test_swiftKeywords_areDetected() {
        let code = "guard let x = foo() else { return }"
        let keywords = texts(.keyword, in: code, language: "swift")
        XCTAssertEqual(keywords, ["guard", "let", "else", "return"])
    }

    func test_unknownLanguage_stillHighlightsStringsCommentsNumbers() {
        let code = "x = \"text\" // note\nn = 42"
        XCTAssertEqual(texts(.string, in: code), ["\"text\""])
        XCTAssertEqual(texts(.comment, in: code), ["// note"])
        XCTAssertEqual(texts(.number, in: code), ["42"])
    }

    func test_blockComment_spansToTerminator() {
        let code = "a /* one\ntwo */ b"
        XCTAssertEqual(texts(.comment, in: code), ["/* one\ntwo */"])
    }

    func test_hashComment_onlyAtLineStart() {
        // 行首的 `#` 视为注释；出现在行中的 `#` 不是（避免误伤 `#available`）。
        XCTAssertEqual(texts(.comment, in: "# note", language: "python"), ["# note"])
        XCTAssertTrue(texts(.comment, in: "x = 1 # inline", language: "python").isEmpty)
    }

    func test_numberInsideIdentifier_isNotANumber() {
        XCTAssertTrue(texts(.number, in: "var a1 = b", language: "swift").isEmpty)
    }

    func test_aliasLanguage_sharesKeywords() {
        // `ts` 应等价于 javascript：`interface` 是关键字。
        XCTAssertEqual(texts(.keyword, in: "interface X {}", language: "ts"), ["interface"])
    }

    func test_unterminatedString_stopsAtLineEnd() {
        let code = "let a = \"oops\nlet b = 1"
        XCTAssertEqual(texts(.string, in: code, language: "swift"), ["\"oops"])
    }

    func test_attributed_preservesTextAndAddsColor() {
        let code = "let x = 1 // c"
        let attributed = CodeSyntaxHighlighter.attributed(code, language: "swift")
        XCTAssertEqual(String(attributed.characters), code)
        // 至少有一段被着色（关键字 / 数字 / 注释）。
        XCTAssertFalse(attributed.runs.compactMap { $0.foregroundColor }.isEmpty)
    }
}
