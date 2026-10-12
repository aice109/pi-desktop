//
//  CodeSyntaxHighlighter.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import SwiftUI
import Foundation

/// 词法单元类别。
nonisolated enum CodeTokenKind: Equatable {
    case plain
    case keyword
    case string
    case comment
    case number
}

/// 一个词法单元；`text` 按原样拼接可还原源码。
nonisolated struct CodeToken: Equatable {
    var kind: CodeTokenKind
    var text: String
}

/// 轻量代码高亮：无第三方依赖，只做注释 / 字符串 / 数字 / 关键字的词法着色。
///
/// 不做语言级语法分析——目标是可读性与零成本，而非编辑器级精度。语言未知时仍高亮注释 / 字符串 /
/// 数字，只用一套通用关键字表；识别到具体语言时叠加该语言的关键字。
nonisolated enum CodeSyntaxHighlighter {
    /// 进程级缓存：同一段代码（流式重绘时反复出现）只着色一次。
    private static let cache = TokenCache()

    /// 把源码拆成词法单元（纯函数，便于单测）。
    static func tokens(_ code: String, language: String?) -> [CodeToken] {
        let keywords = keywords(for: language)
        let chars = Array(code)
        let count = chars.count
        var tokens: [CodeToken] = []
        var plain = ""

        func flushPlain() {
            if !plain.isEmpty {
                tokens.append(CodeToken(kind: .plain, text: plain))
                plain = ""
            }
        }
        func emit(_ kind: CodeTokenKind, from start: Int, to end: Int) {
            flushPlain()
            tokens.append(CodeToken(kind: kind, text: String(chars[start..<end])))
        }
        // 行内是否只有空白前缀（用于把 `#` 当作注释而非运算符 / 预处理）。
        func isFirstNonBlankOnLine(_ index: Int) -> Bool {
            var j = index - 1
            while j >= 0, chars[j] != "\n" {
                if chars[j] != " ", chars[j] != "\t" { return false }
                j -= 1
            }
            return true
        }

        var i = 0
        while i < count {
            let c = chars[i]

            // 行注释：`//…`
            if c == "/", i + 1 < count, chars[i + 1] == "/" {
                var j = i
                while j < count, chars[j] != "\n" { j += 1 }
                emit(.comment, from: i, to: j)
                i = j
                continue
            }
            // `#` 注释（Python / Shell / Ruby）：仅在行首出现时识别，避免误伤 `#available` 等。
            if c == "#", isFirstNonBlankOnLine(i) {
                var j = i
                while j < count, chars[j] != "\n" { j += 1 }
                emit(.comment, from: i, to: j)
                i = j
                continue
            }
            // 块注释：`/*…*/`
            if c == "/", i + 1 < count, chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < count, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                j = min(j + 2, count)
                emit(.comment, from: i, to: j)
                i = j
                continue
            }
            // 字符串：`"` `'` `` ` ``；单/双引号不跨行，未闭合时到行尾为止。
            if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                var escaped = false
                while j < count {
                    let d = chars[j]
                    if escaped { escaped = false; j += 1; continue }
                    if d == "\\" { escaped = true; j += 1; continue }
                    if d == c { j += 1; break }
                    if d == "\n", c != "`" { break }
                    j += 1
                }
                emit(.string, from: i, to: j)
                i = j
                continue
            }
            // 数字：前面不是标识符字符，避免把 `abc1` 里的 1 当成数字。
            if c.isNumber, !(i > 0 && isIdentifierChar(chars[i - 1])) {
                var j = i
                while j < count, isNumberChar(chars[j]) { j += 1 }
                emit(.number, from: i, to: j)
                i = j
                continue
            }
            // 标识符 / 关键字。
            if isIdentifierStart(c) {
                var j = i
                while j < count, isIdentifierChar(chars[j]) { j += 1 }
                let word = String(chars[i..<j])
                if keywords.contains(word) {
                    emit(.keyword, from: i, to: j)
                } else {
                    plain += word
                }
                i = j
                continue
            }
            plain.append(c)
            i += 1
        }
        flushPlain()
        return tokens
    }

    /// 着色后的富文本；结果按 (语言 + 源码) 缓存。
    static func attributed(_ code: String, language: String?) -> AttributedString {
        let key = "\(language ?? "")\u{0}\(code)" as NSString
        if let cached = cache.value(for: key) { return cached }

        var result = AttributedString()
        for token in tokens(code, language: language) {
            var piece = AttributedString(token.text)
            if let color = color(for: token.kind) { piece.foregroundColor = color }
            result.append(piece)
        }
        cache.store(result, for: key, cost: code.utf8.count)
        return result
    }

    /// 语义颜色随外观自适应。
    static func color(for kind: CodeTokenKind) -> Color? {
        switch kind {
        case .plain: return nil
        case .keyword: return .purple
        case .string: return .red
        case .comment: return .secondary
        case .number: return .blue
        }
    }

    // MARK: - Character classes

    private static func isIdentifierStart(_ c: Character) -> Bool {
        c.isLetter || c == "_" || c == "$"
    }

    private static func isIdentifierChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_" || c == "$"
    }

    private static func isNumberChar(_ c: Character) -> Bool {
        c.isNumber || c == "." || c == "_"
            || c == "x" || c == "X" || c == "b" || c == "B" || c == "o" || c == "O"
            || c == "e" || c == "E"
    }

    // MARK: - Keywords

    /// 通用关键字（多数 C 系 / 脚本语言共有），语言未知时也能给出合理着色。
    private static let commonKeywords: Set<String> = [
        "if", "else", "for", "while", "return", "break", "continue", "function", "class", "struct",
        "enum", "import", "from", "export", "public", "private", "protected", "static", "const", "let",
        "var", "new", "this", "self", "super", "true", "false", "null", "nil", "none", "def", "do",
        "switch", "case", "default", "try", "catch", "finally", "throw", "throws", "async", "await",
        "yield", "in", "is", "as", "and", "or", "not", "with", "lambda", "interface", "implements",
        "extends", "type", "void", "int", "float", "double", "string", "bool", "boolean", "package",
        "use", "match", "where", "loop", "select", "go", "defer", "range", "elif", "then", "fi",
        "esac", "echo", "local", "readonly", "namespace", "sizeof", "typedef", "union", "volatile",
        "extern", "register", "goto", "template", "end",
    ]

    private static let languageKeywords: [String: Set<String>] = [
        "swift": [
            "guard", "some", "any", "actor", "protocol", "extension", "associatedtype", "inout",
            "lazy", "weak", "unowned", "deinit", "subscript", "convenience", "required", "mutating",
            "nonmutating", "indirect", "fileprivate", "open", "fallthrough", "repeat", "rethrows",
            "precedencegroup", "willSet", "didSet",
        ],
        "python": ["pass", "raise", "global", "nonlocal", "assert", "del", "except", "cls", "True", "False", "None"],
        "javascript": ["undefined", "typeof", "instanceof", "delete", "of", "module", "declare", "abstract"],
        "go": ["func", "chan", "map", "make", "len", "cap", "append", "fallthrough"],
        "rust": ["fn", "mut", "impl", "trait", "pub", "mod", "crate", "unsafe", "move", "ref", "dyn", "Some", "None", "Ok", "Err"],
        "shell": ["done", "exit", "shift", "source", "elif"],
        "java": ["final", "val", "fun", "when", "object", "data", "sealed", "companion", "suspend", "override", "internal", "lateinit"],
        "ruby": ["elsif", "unless", "until", "module", "require"],
    ]

    /// 语言别名 → 规范名（`js` / `ts` 共用一套关键字）。
    private static let languageAliases: [String: String] = [
        "py": "python", "js": "javascript", "ts": "javascript", "typescript": "javascript",
        "jsx": "javascript", "tsx": "javascript", "golang": "go", "rs": "rust",
        "sh": "shell", "bash": "shell", "zsh": "shell", "kotlin": "java", "kt": "java",
        "rb": "ruby", "objective-c": "swift", "objc": "swift",
    ]

    /// 归一化语言名并合并关键字表。
    static func keywords(for language: String?) -> Set<String> {
        guard let language else { return commonKeywords }
        let key = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let canonical = languageAliases[key] ?? key
        guard let extra = languageKeywords[canonical] else { return commonKeywords }
        return commonKeywords.union(extra)
    }
}

/// `NSCache` 的值必须为类；仅作 `AttributedString` 容器。
private final class AttributedStringBox {
    let value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

/// 高亮结果的进程级缓存（线程安全、内存紧张时自动淘汰）。
private final class TokenCache: @unchecked Sendable {
    private let cache = NSCache<NSString, AttributedStringBox>()

    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 4 * 1024 * 1024
    }

    func value(for key: NSString) -> AttributedString? {
        cache.object(forKey: key)?.value
    }

    func store(_ value: AttributedString, for key: NSString, cost: Int) {
        cache.setObject(AttributedStringBox(value), forKey: key, cost: cost)
    }
}
