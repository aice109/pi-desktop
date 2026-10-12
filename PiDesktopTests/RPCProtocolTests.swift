//
//  RPCProtocolTests.swift
//  PiDesktopTests
//
//  Copyright © 2026 PiDesktop contributors. MIT License.
//

import XCTest
@testable import PiDesktop

/// 线上报文 → 领域事件 的映射测试（样本取自真实 pi RPC 输出）。
final class RPCProtocolTests: XCTestCase {
    private func event(_ json: String) -> AgentEvent? {
        guard let data = json.data(using: .utf8),
              let record = RPCProtocol.decode(data) else { return nil }
        return RPCProtocol.agentEvent(from: record)
    }

    func test_textDelta_mapsToTextDelta() {
        let json = #"{"type":"message_update","usage":{},"assistantMessageEvent":{"type":"text_delta","contentIndex":0,"delta":"ong"}}"#
        XCTAssertEqual(event(json), .textDelta("ong"))
    }

    func test_thinkingDelta_mapsToThinkingDelta() {
        let json = #"{"type":"message_update","assistantMessageEvent":{"type":"thinking_delta","contentIndex":0,"delta":"hmm"}}"#
        XCTAssertEqual(event(json), .thinkingDelta("hmm"))
    }

    func test_textStart_isIgnored() {
        let json = #"{"type":"message_update","assistantMessageEvent":{"type":"text_start","contentIndex":0}}"#
        XCTAssertNil(event(json))
    }

    func test_assistantMessageEnd_joinsTextBlocks() {
        let json = #"{"type":"message_end","message":{"role":"assistant","content":[{"type":"text","text":"pong"}],"stopReason":"stop","timestamp":1}}"#
        XCTAssertEqual(
            event(json),
            .assistantMessageCompleted(text: "pong", stopReason: "stop", errorMessage: nil)
        )
    }

    func test_userMessageEnd_isIgnored() {
        let json = #"{"type":"message_end","message":{"role":"user","content":[{"type":"text","text":"hi"}],"timestamp":1}}"#
        XCTAssertNil(event(json))
    }

    func test_systemMessageWithStringContent_decodesButIsIgnored() {
        let json = #"{"type":"message_end","message":{"role":"system","content":"","timestamp":1}}"#
        guard let data = json.data(using: .utf8) else { return XCTFail("encode") }
        XCTAssertNotNil(RPCProtocol.decode(data), "字符串内容应能解码")
        XCTAssertNil(event(json))
    }

    func test_toolExecution_mapsStartUpdateAndEnd() {
        let start = #"{"type":"tool_execution_start","toolCallId":"call_1","toolName":"bash","args":{"command":"ls"}}"#
        XCTAssertEqual(
            event(start),
            .toolCallStarted(id: "call_1", name: "bash", arguments: "command: ls")
        )

        let update = #"{"type":"tool_execution_update","toolCallId":"call_1","toolName":"bash","args":{"command":"ls"},"partialResult":{"content":[{"type":"text","text":"partial output"}],"details":{}}}"#
        XCTAssertEqual(event(update), .toolCallUpdated(id: "call_1", output: "partial output"))

        let end = #"{"type":"tool_execution_end","toolCallId":"call_1","toolName":"bash","result":{"content":[{"type":"text","text":"done"}],"details":{}},"isError":false,"durationMs":42}"#
        XCTAssertEqual(
            event(end),
            .toolCallFinished(id: "call_1", name: "bash", isError: false, durationMs: 42, output: "done")
        )
    }

    func test_toolStart_withoutArgsYieldsNilArguments() {
        let start = #"{"type":"tool_execution_start","toolCallId":"c","toolName":"read"}"#
        XCTAssertEqual(event(start), .toolCallStarted(id: "c", name: "read", arguments: nil))
    }

    func test_retryAndCompaction_mapToEvents() {
        XCTAssertEqual(
            event(#"{"type":"auto_retry_start","attempt":1,"maxAttempts":3,"delayMs":2000,"errorMessage":"529 overloaded"}"#),
            .retryStarted(attempt: 1, maxAttempts: 3)
        )
        XCTAssertEqual(
            event(#"{"type":"auto_retry_end","success":true,"attempt":2}"#),
            .retryFinished(success: true)
        )
        XCTAssertEqual(
            event(#"{"type":"auto_retry_end","success":false,"finalError":"boom"}"#),
            .retryFinished(success: false)
        )
        XCTAssertEqual(event(#"{"type":"compaction_start","reason":"threshold"}"#), .compactionStarted)
        XCTAssertEqual(
            event(#"{"type":"compaction_end","reason":"manual","aborted":false}"#),
            .compactionFinished(aborted: false, errorMessage: nil)
        )
    }

    func test_queueAndSessionStateEvents_mapToDomainEvents() {
        XCTAssertEqual(
            event(#"{"type":"queue_update","steering":["stop"],"followUp":["then test"]}"#),
            .queueUpdated(AgentQueue(steering: ["stop"], followUp: ["then test"]))
        )
        XCTAssertEqual(
            event(#"{"type":"session_info_changed","name":"my-feature"}"#),
            .sessionInfoChanged(name: "my-feature")
        )
        XCTAssertEqual(
            event(#"{"type":"session_info_changed"}"#),
            .sessionInfoChanged(name: nil)
        )
        XCTAssertEqual(
            event(#"{"type":"thinking_level_changed","level":"high"}"#),
            .thinkingLevelChanged(level: "high")
        )
        XCTAssertEqual(event(#"{"type":"entry_appended"}"#), .entryAppended)
    }

    func test_summarizationRetry_mapsToEvents() {
        XCTAssertEqual(
            event(#"{"type":"summarization_retry_scheduled","attempt":1,"maxAttempts":3}"#),
            .summarizationRetryStarted
        )
        XCTAssertEqual(
            event(#"{"type":"summarization_retry_attempt_start","source":"compaction","reason":"threshold"}"#),
            .summarizationRetryStarted
        )
        XCTAssertEqual(event(#"{"type":"summarization_retry_finished"}"#), .summarizationRetryFinished)
    }

    func test_agentSettled_mapsAbortedFlag() {
        XCTAssertEqual(event(#"{"type":"agent_settled","aborted":false}"#), .settled(aborted: false))
        XCTAssertEqual(event(#"{"type":"agent_settled","aborted":true}"#), .settled(aborted: true))
    }

    func test_getSessionStatsResponse_decodesTokensCostAndContext() {
        // 真实报文：`contextUsage.percent` 是小数，曾因按 Int 解码导致整条响应失败。
        let json = #"{"id":"r1","type":"response","command":"get_session_stats","success":true,"data":{"tokens":{"input":1,"output":2,"cacheRead":3,"cacheWrite":4,"total":10},"cost":0.147,"contextUsage":{"tokens":114525,"contextWindow":1000000,"percent":11.4525}}}"#
        guard let data = json.data(using: .utf8), let record = RPCProtocol.decode(data) else {
            return XCTFail("get_session_stats 响应应能解码")
        }
        XCTAssertEqual(record.data?.tokens?.total, 10)
        XCTAssertEqual(record.data?.cost, 0.147)
        XCTAssertEqual(record.data?.contextUsage?.percent, 11.4525)
        XCTAssertEqual(record.data?.contextUsage?.contextWindow, 1_000_000)
    }

    func test_getStateResponse_decodesModelThinkingAndLevels() {
        let state = #"{"id":"r1","type":"response","command":"get_state","success":true,"data":{"model":{"id":"deepseek-flash","name":"DeepSeek V4.1 Flash","provider":"deepseek","reasoning":true,"contextWindow":1000000},"thinkingLevel":"high","sessionFile":"/tmp/s.jsonl"}}"#
        guard let data = state.data(using: .utf8), let record = RPCProtocol.decode(data) else {
            return XCTFail("get_state 响应应能解码")
        }
        XCTAssertEqual(record.data?.model?.domain.id, "deepseek-flash")
        XCTAssertEqual(record.data?.model?.domain.reasoning, true)
        XCTAssertEqual(record.data?.thinkingLevel, "high")

        let levels = #"{"id":"r2","type":"response","command":"get_available_thinking_levels","success":true,"data":{"levels":["off","low","high","max"]}}"#
        guard let levelsData = levels.data(using: .utf8), let levelsRecord = RPCProtocol.decode(levelsData) else {
            return XCTFail("levels 响应应能解码")
        }
        XCTAssertEqual(levelsRecord.data?.levels, ["off", "low", "high", "max"])
    }

    func test_getEntriesResponse_decodesHistory() {
        // 真实形状：data.entries 是追加式树的节点，message 为 AgentMessage。
        let json = #"{"id":"r1","type":"response","command":"get_entries","success":true,"data":{"entries":[{"type":"message","id":"e1","parentId":null,"timestamp":"2024-12-03T14:00:02.000Z","message":{"role":"user","content":[{"type":"text","text":"run ls"}]}},{"type":"message","id":"e2","timestamp":"2024-12-03T14:00:03.000Z","message":{"role":"assistant","content":[{"type":"text","text":"Now listing."},{"type":"toolCall","id":"call_1","name":"bash","arguments":{"command":"ls"}}]}},{"type":"message","id":"e3","timestamp":"2024-12-03T14:00:04.000Z","message":{"role":"toolResult","toolCallId":"call_1","toolName":"bash","isError":false,"content":[{"type":"text","text":"AGENTS.md"}]}}],"leafId":"e3"}}"#
        guard let data = json.data(using: .utf8), let record = RPCProtocol.decode(data) else {
            return XCTFail("get_entries 响应应能解码")
        }
        let entries = record.data?.entries ?? []
        XCTAssertEqual(entries.count, 3)

        let history = PiHistory.make(from: entries.map(\.historyEntry))
        XCTAssertEqual(history.messages.map(\.text), ["run ls", "Now listing."])
        XCTAssertEqual(history.toolCalls.count, 1)
        XCTAssertEqual(history.toolCalls[0].arguments, "command: ls")
        XCTAssertEqual(history.toolCalls[0].output, "AGENTS.md")
        XCTAssertEqual(history.toolCalls[0].timestamp, entries[2].timestamp.flatMap(PiDate.parse))
    }

    func test_nullContent_decodesAsEmptyText() {
        // 真实报文：`get_entries` 里 `system` / `bashExecution` 消息的 content 为 null。
        let json = #"{"id":"r1","type":"response","command":"get_entries","success":true,"data":{"entries":[{"type":"message","id":"e1","message":{"role":"bashExecution","content":null,"command":"ls","output":""}},{"type":"message","id":"e2","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}],"leafId":"e2"}}"#
        guard let data = json.data(using: .utf8), let record = RPCProtocol.decode(data) else {
            return XCTFail("含 null content 的条目应能解码（否则整条响应失败）")
        }
        let entries = record.data?.entries ?? []
        XCTAssertEqual(entries.count, 2)

        let history = PiHistory.make(from: entries.map(\.historyEntry))
        XCTAssertEqual(history.messages.map(\.text), ["hi"])
    }

    func test_missingContentKey_decodesAsEmpty() {
        // 真实报文：`get_entries` 里部分消息根本没有 content 键。
        let json = #"{"id":"r1","type":"response","command":"get_entries","success":true,"data":{"entries":[{"type":"message","id":"e1","message":{"role":"system"}},{"type":"message","id":"e2","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}]}}"#
        guard let data = json.data(using: .utf8), let record = RPCProtocol.decode(data) else {
            return XCTFail("缺少 content 键的条目应能解码")
        }
        let entries = record.data?.entries ?? []
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(PiHistory.make(from: entries.map(\.historyEntry)).messages.map(\.text), ["hi"])
    }

    func test_response_decodesButIsNotAnEvent() {
        let json = #"{"id":"req-1","type":"response","command":"prompt","success":true,"data":{"disposition":"started"}}"#
        guard let data = json.data(using: .utf8), let record = RPCProtocol.decode(data) else {
            return XCTFail("response 应能解码")
        }
        XCTAssertEqual(record.success, true)
        XCTAssertNil(RPCProtocol.agentEvent(from: record))
    }

    func test_malformedLine_returnsNil() {
        let json = #"{"type":"message_update","assistantMessageEvent":"#
        XCTAssertNil(event(json))
    }
}
