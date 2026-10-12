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
