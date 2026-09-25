import Core
import Foundation
@testable import MCPServer
import ShortcutForge
import Testing

/// Records calls instead of running shortcuts.
final class FakeProvider: ToolProvider, @unchecked Sendable {
    let lock = NSLock()
    var calls: [(String, [String: JSONValue], String)] = []
    let recipes: [Recipe]
    let report: CallReport

    init(recipes: [Recipe] = [Catalog.remindersAdd, Catalog.notesCreate],
         report: CallReport = CallReport(tool: "reminders.add", ok: true, output: "Call the dentist", verified: true,
                                         detail: "read back through Shortcuts: due 26 Sep 2026 at 10:00", durationMs: 1100)) {
        self.recipes = recipes
        self.report = report
    }

    func tools() -> [Recipe] { recipes }

    func call(_ alias: String, args: [String: JSONValue], caller: String) async -> CallReport {
        lock.withLock { calls.append((alias, args, caller)) }
        return report
    }
}

final class Sink: @unchecked Sendable {
    let lock = NSLock()
    var lines: [JSONValue] = []
    func write(_ d: Data) {
        let v = try! JSONDecoder().decode(JSONValue.self, from: d)
        lock.lock(); lines.append(v); lock.unlock()
    }
}

func run(_ lines: [String], provider: FakeProvider = FakeProvider()) async -> [JSONValue] {
    let sink = Sink()
    let server = MCPServer(provider: provider) { sink.write($0) }
    for l in lines { await server.handle(line: l) }
    return sink.lines
}

func fixture(_ name: String) throws -> [String] {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "jsonl")!
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
}

@Suite struct HandshakeTests {
    @Test func claudeCodeTranscript() async throws {
        let provider = FakeProvider()
        let out = await run(try fixture("claude-code"), provider: provider)
        // server/discover → -32601 (fall back), initialize, tools/list, tools/call; no reply to the notification.
        #expect(out.count == 4)
        #expect(out[0]["id"] == "server-discover-probe-1")
        #expect(out[0]["error"]?["code"] == -32601)
        #expect(out[1]["result"]?["protocolVersion"] == "2025-11-25")
        #expect(out[1]["result"]?["serverInfo"]?["name"] == "intents-mcp")
        #expect(out[2]["result"]?["tools"]?.arrayValue?.count == 2)
        #expect(out[3]["result"]?["isError"] == false)
        #expect(provider.calls.count == 1)
        #expect(provider.calls[0].0 == "reminders.add")
        #expect(provider.calls[0].2 == "mcp:claude-code")
        #expect(provider.calls[0].1 == ["title": "Call the dentist", "due": "tomorrow at 10:00"])
    }

    @Test func codexTranscriptWithExperimentalObject() async throws {
        // swift-sdk#287: this exact initialize broke the official SDK. It must pass here.
        let provider = FakeProvider()
        let out = await run(try fixture("codex"), provider: provider)
        #expect(out.count == 3)
        #expect(out[0]["result"]?["protocolVersion"] == "2025-06-18")
        #expect(out[1]["result"]?["tools"]?.arrayValue?.count == 2)
        #expect(out[2]["result"]?["structuredContent"]?["verified"] == true)
        #expect(provider.calls.first?.2 == "mcp:codex-mcp-client")
    }

    @Test func unknownVersionGetsOurLatest() async {
        let out = await run([#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2099-01-01"}}"#])
        #expect(out[0]["result"]?["protocolVersion"] == "2025-11-25")
    }

    @Test func errors() async {
        let out = await run([
            "not json",
            #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#,
        ])
        #expect(out[0]["error"]?["code"] == -32700)
        #expect(out[1]["error"]?["code"] == -32601)
        #expect(out[2]["error"]?["code"] == -32602)
        #expect(out[3]["result"] == .object([:]))
    }
}

@Suite struct ToolSchemaTests {
    @Test func namesAreClaudeSafe() {
        #expect(MCPServer.toolName("reminders.add") == "reminders_add")
        #expect(MCPServer.toolName("writing-tools-app-intents.summarize-text") == "writing-tools-app-intents_summarize-text")
        #expect(MCPServer.toolName("ünïcode.x") == "_n_code_x")
        #expect(MCPServer.toolName(String(repeating: "a", count: 80)).count == 64)
    }

    @Test func reminderSchema() {
        let t = MCPServer.tool(Catalog.remindersAdd)
        #expect(t["name"] == "reminders_add")
        let schema = t["inputSchema"]!
        #expect(schema["type"] == "object")
        #expect(schema["additionalProperties"] == false)
        #expect(schema["required"] == ["title"])
        #expect(schema["properties"]?["alert"] == nil)  // derived, not an argument
        #expect(schema["properties"]?["due"]?["type"] == "string")
        #expect(t["annotations"]?["destructiveHint"] == false)
        #expect(t["description"]?.stringValue?.contains("read back") == true)
    }

    @Test func riskyAndGeneratedAreMarked() {
        var r = Catalog.notesCreate
        r.risky = true
        r.verified = nil
        r.inputs.append(RecipeInput("mode", "mode", .enumeration(["fast", "slow"])))
        let t = MCPServer.tool(r)
        #expect(t["annotations"]?["destructiveHint"] == true)
        #expect(t["description"]?.stringValue?.contains("not yet checked") == true)
        #expect(t["inputSchema"]?["properties"]?["mode"]?["enum"] == ["fast", "slow"])
    }
}

@Suite struct ResultTests {
    @Test func verifiedResult() {
        let r = MCPServer.result(CallReport(tool: "reminders.add", ok: true, output: "Dentist", verified: true,
                                            detail: "due 26 Sep 2026 at 10:00", durationMs: 900))
        #expect(r["isError"] == false)
        #expect(r["content"]?.arrayValue?.first?["text"] == "Dentist\nVerified: due 26 Sep 2026 at 10:00")
        #expect(r["structuredContent"]?["verified"] == true)
    }

    @Test func failureIsAToolError() {
        let r = MCPServer.result(CallReport(tool: "x", ok: false, error: "no result after 50 s", durationMs: 50_000))
        #expect(r["isError"] == true)
        #expect(r["content"]?.arrayValue?.first?["text"] == "Error: no result after 50 s")
    }

    @Test func notVerifiedIsSaid() {
        let r = MCPServer.result(CallReport(tool: "x", ok: true, output: "A", verified: false, detail: "not found"))
        #expect(r["content"]?.arrayValue?.first?["text"]?.stringValue?.hasSuffix("NOT verified: not found") == true)
    }
}
