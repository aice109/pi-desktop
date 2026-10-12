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

    func test_toolExecution_mapsStartAndEnd() {
        let start = #"{"type":"tool_execution_start","toolCallId":"call_1","toolName":"bash","args":{"command":"ls"}}"#
        XCTAssertEqual(event(start), .toolCallStarted(id: "call_1", name: "bash"))

        let end = #"{"type":"tool_execution_end","toolCallId":"call_1","toolName":"bash","result":{},"isError":false,"durationMs":42}"#
        XCTAssertEqual(
            event(end),
            .toolCallFinished(id: "call_1", name: "bash", isError: false, durationMs: 42)
        )
    }

    func test_agentSettled_mapsAbortedFlag() {
        XCTAssertEqual(event(#"{"type":"agent_settled","aborted":false}"#), .settled(aborted: false))
        XCTAssertEqual(event(#"{"type":"agent_settled","aborted":true}"#), .settled(aborted: true))
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
