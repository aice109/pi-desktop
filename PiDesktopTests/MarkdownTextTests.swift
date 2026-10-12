//
//  MarkdownTextTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
@testable import PiDesktop

/// 块级 Markdown 解析测试：验证常见块被识别为正确的 `MarkdownBlock.Kind`。
final class MarkdownTextTests: XCTestCase {
    func test_blockCache_reusesParsedBlocks() {
        let markdown = "# Title\n\nBody text"
        let first = MarkdownBlockCache.shared.blocks(for: markdown)
        let second = MarkdownBlockCache.shared.blocks(for: markdown)

        XCTAssertEqual(first.count, second.count)
        // 命中缓存时返回同一批 block（UUID 相同）；重新解析会生成新 id。
        XCTAssertEqual(first.map(\.id), second.map(\.id))
    }

    func test_heading_parsesLevelAndText() {
        let blocks = MarkdownBlock.parse("## Title\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let text) = blocks[0].kind else {
            return XCTFail("expected heading, got \(blocks[0].kind)")
        }
        XCTAssertEqual(level, 2)
        XCTAssertEqual(String(text.characters), "Title")
    }

    func test_paragraph_preservesInlineFormatting() {
        let blocks = MarkdownBlock.parse("Hello **world**")
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let text) = blocks[0].kind else {
            return XCTFail("expected paragraph, got \(blocks[0].kind)")
        }
        XCTAssertEqual(String(text.characters), "Hello world")
    }

    func test_unorderedList_itemsGetBulletMarkers() {
        let blocks = MarkdownBlock.parse("- one\n- two\n")
        XCTAssertEqual(blocks.count, 2)
        for block in blocks {
            guard case .listItem(let marker, let depth, _) = block.kind else {
                return XCTFail("expected list item, got \(block.kind)")
            }
            XCTAssertEqual(marker, "•")
            XCTAssertEqual(depth, 0)
        }
    }

    func test_orderedList_itemsGetNumberedMarkers() {
        let blocks = MarkdownBlock.parse("1. first\n2. second\n")
        XCTAssertEqual(blocks.count, 2)
        guard case .listItem(let first, _, _) = blocks[0].kind,
              case .listItem(let second, _, _) = blocks[1].kind else {
            return XCTFail("expected ordered list items")
        }
        XCTAssertEqual(first, "1.")
        XCTAssertEqual(second, "2.")
    }

    func test_codeBlock_parsesLanguageAndCode() {
        let blocks = MarkdownBlock.parse("```swift\nlet x = 1\n```\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let language, let code) = blocks[0].kind else {
            return XCTFail("expected code block, got \(blocks[0].kind)")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(code, "let x = 1\n")
    }

    func test_blockQuote_parses() {
        let blocks = MarkdownBlock.parse("> quoted\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .blockQuote(let text) = blocks[0].kind else {
            return XCTFail("expected block quote, got \(blocks[0].kind)")
        }
        XCTAssertEqual(String(text.characters), "quoted")
    }

    func test_thematicBreak_parses() {
        let blocks = MarkdownBlock.parse("---\n")
        XCTAssertEqual(blocks.count, 1)
        guard case .thematicBreak = blocks[0].kind else {
            return XCTFail("expected thematic break, got \(blocks[0].kind)")
        }
    }

    func test_table_parsesHeaderAndRows() {
        let blocks = MarkdownBlock.parse("""
        | Name | Value |
        | --- | --- |
        | alpha | 1 |
        | beta | 2 |
        """)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let header, let rows) = blocks[0].kind else {
            return XCTFail("expected table, got \(blocks[0].kind)")
        }
        XCTAssertEqual(header.map { String($0.characters) }, ["Name", "Value"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].map { String($0.characters) }, ["alpha", "1"])
        XCTAssertEqual(rows[1].map { String($0.characters) }, ["beta", "2"])
    }

    func test_emptyInput_returnsNoBlocks() {
        XCTAssertTrue(MarkdownBlock.parse("   \n").isEmpty)
    }
}
