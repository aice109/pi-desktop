//
//  JSONValue.swift
//  PiDesktop
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import Foundation

/// 任意 JSON 值。
///
/// 用于解码结构不固定的字段（如工具调用的 `args`）：工具种类很多，参数 schema 各不相同，
/// 与其为每种工具建类型，不如保留为通用值再压成字符串展示。
nonisolated enum JSONValue: Decodable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// 压成单行文本，供工具卡片标题展示；对象按 key 排序以保证稳定。
    var compactDescription: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.formatted(.number.grouping(.never))
        case .bool(let value):
            return value ? "true" : "false"
        case .null:
            return "null"
        case .array(let values):
            return "[" + values.map(\.compactDescription).joined(separator: ", ") + "]"
        case .object(let pairs):
            return pairs.keys.sorted()
                .map { "\($0): \(pairs[$0]?.compactDescription ?? "")" }
                .joined(separator: ", ")
        }
    }
}
