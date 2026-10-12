//
//  MarkdownText.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import Foundation

/// 块级 Markdown 渲染。
///
/// SwiftUI 的 `Text` 只渲染行内格式（粗体 / 斜体 / 行内代码 / 链接），不会渲染块级结构
/// （标题、列表、代码块、引用、表格）。这里用 Foundation 的 `AttributedString(markdown:)`
/// 解析出块级 `PresentationIntent`，再用 SwiftUI 原语（`Text` / `VStack` / `Grid` / `Divider`）
/// 排版；不引入第三方依赖。
struct MarkdownText: View {
    let text: String

    var body: some View {
        let blocks = MarkdownBlock.parse(text)
        if blocks.isEmpty {
            Text(text)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(blocks) { block in
                    MarkdownBlockView(block: block)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Blocks

/// 一个可独立排版的 Markdown 块。
///
/// 暴露给测试（`MarkdownTextTests`）以验证解析结果；视图层只读不改。
struct MarkdownBlock: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        case listItem(marker: String, depth: Int, text: AttributedString)
        case codeBlock(language: String?, code: String)
        case blockQuote(AttributedString)
        case thematicBreak
        case table(header: [AttributedString], rows: [[AttributedString]])
    }
}

extension MarkdownBlock {
    /// 把 Markdown 源码解析成块序列；解析失败时退化为单个纯文本段落。
    ///
    /// 算法：`AttributedString` 给每个 run 带上块级 `presentationIntent`；相邻且 intent
    /// 相同的 run 属于同一个块（行内格式不会改变块 intent），据此合并后再按 intent 分类。
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        let source = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return [] }
        guard let attributed = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
        ) else {
            return [MarkdownBlock(kind: .paragraph(AttributedString(source)))]
        }

        var grouped: [(intent: PresentationIntent?, text: AttributedString)] = []
        for run in attributed.runs {
            var slice = AttributedString()
            slice.append(attributed[run.range])
            if var last = grouped.last, last.intent == run.presentationIntent {
                last.text.append(slice)
                grouped[grouped.count - 1] = last
            } else {
                grouped.append((run.presentationIntent, slice))
            }
        }

        var blocks: [MarkdownBlock] = []
        var index = 0
        while index < grouped.count {
            let entry = grouped[index]
            guard let intent = entry.intent, let outer = intent.components.last else {
                blocks.append(MarkdownBlock(kind: .paragraph(entry.text)))
                index += 1
                continue
            }

            switch outer.kind {
            case .header(let level):
                blocks.append(MarkdownBlock(kind: .heading(level: level, text: entry.text)))
                index += 1
            case .codeBlock(let language):
                blocks.append(MarkdownBlock(kind: .codeBlock(language: language, code: String(entry.text.characters))))
                index += 1
            case .thematicBreak:
                blocks.append(MarkdownBlock(kind: .thematicBreak))
                index += 1
            case .blockQuote:
                blocks.append(MarkdownBlock(kind: .blockQuote(entry.text)))
                index += 1
            case .unorderedList, .orderedList:
                blocks.append(listItem(from: intent, text: entry.text))
                index += 1
            case .table:
                let (block, next) = table(from: grouped, start: index, tableIdentity: outer.identity)
                blocks.append(block)
                index = next
            default:
                blocks.append(MarkdownBlock(kind: .paragraph(entry.text)))
                index += 1
            }
        }
        return blocks
    }

    /// 列表项：从 intent 里取标记（`•` 或 `1.`）与嵌套深度。
    static func listItem(from intent: PresentationIntent, text: AttributedString) -> MarkdownBlock {
        var ordinal = 1
        var depth = 0
        var isOrdered = false
        var foundInnermost = false
        // components 顺序为「由内到外」：先遇到的列表 intent 即最内层。
        for component in intent.components {
            switch component.kind {
            case .orderedList:
                depth += 1
                if !foundInnermost { isOrdered = true; foundInnermost = true }
            case .unorderedList:
                depth += 1
                if !foundInnermost { isOrdered = false; foundInnermost = true }
            case .listItem(let value):
                ordinal = value
            default:
                break
            }
        }
        return MarkdownBlock(kind: .listItem(
            marker: isOrdered ? "\(ordinal)." : "•",
            depth: max(depth - 1, 0),
            text: text
        ))
    }

    /// 把一个表格的所有单元格合并成一个块。
    ///
    /// 单元格是独立 run 组：`tableCell > tableHeaderRow / tableRow > table`，用行 intent 的
    /// `identity` 区分不同行，遇到不属于同一表格的块就结束。
    static func table(
        from grouped: [(intent: PresentationIntent?, text: AttributedString)],
        start: Int,
        tableIdentity: Int
    ) -> (MarkdownBlock, Int) {
        var header: [AttributedString] = []
        var rows: [[AttributedString]] = []
        var currentRow: [AttributedString?] = []
        var currentRowKey: Int?
        var currentIsHeader = false
        var index = start

        func flush() {
            let cells = currentRow.map { $0 ?? AttributedString() }
            if !cells.isEmpty {
                if currentIsHeader { header = cells } else { rows.append(cells) }
            }
            currentRow = []
        }

        while index < grouped.count {
            guard let intent = grouped[index].intent,
                  let outer = intent.components.last,
                  case .table = outer.kind,
                  outer.identity == tableIdentity
            else { break }

            var column = 0
            var rowKey: Int?
            var isHeader = false
            for component in intent.components {
                switch component.kind {
                case .tableCell(let index): column = index
                case .tableHeaderRow: isHeader = true; rowKey = component.identity
                case .tableRow: isHeader = false; rowKey = component.identity
                default: break
                }
            }

            if rowKey != currentRowKey {
                flush()
                currentRowKey = rowKey
                currentIsHeader = isHeader
            }
            while currentRow.count <= column { currentRow.append(nil) }
            currentRow[column] = grouped[index].text
            index += 1
        }
        flush()
        return (MarkdownBlock(kind: .table(header: header, rows: rows)), index)
    }
}

// MARK: - Rendering

private struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            Text(text)
                .font(headingFont(level))
                .fontWeight(.semibold)
                .padding(.top, 2)

        case .paragraph(let text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let marker, let depth, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 18, alignment: .trailing)
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(depth) * 16)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(code)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

        case .blockQuote(let text):
            HStack(alignment: .top, spacing: 10) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .thematicBreak:
            Divider()

        case .table(let header, let rows):
            table(header: header, rows: rows)
        }
    }

    /// 标题层级映射到语义字体，避免硬编码字号。
    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    private func table(header: [AttributedString], rows: [[AttributedString]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            if !header.isEmpty {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        Text(cell).fontWeight(.semibold).gridColumnAlignment(.leading)
                    }
                }
                GridRow {
                    Divider().gridCellColumns(max(header.count, 1))
                }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        Text(cell).gridColumnAlignment(.leading)
                    }
                }
            }
        }
    }
}

#Preview("Markdown") {
    ScrollView {
        MarkdownText(text: """
        # Heading 1

        Some **bold**, *italic*, `inline code` and a [link](https://example.com).

        - first item
        - second item with `code`

        1. ordered one
        2. ordered two

        > A quoted line.

        ```swift
        let value = 42
        print(value)
        ```

        | Name | Value |
        | --- | --- |
        | alpha | 1 |
        | beta | 2 |

        ---

        Closing paragraph.
        """)
        .padding()
    }
    .frame(width: 520, height: 640)
}
