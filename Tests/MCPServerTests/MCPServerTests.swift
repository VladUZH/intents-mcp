import Core
import Foundation
@testable import MCPServer
import ShortcutForge
import Runner
import Store
import Testing

/// Records calls instead of running shortcuts; optionally runs a real child process per call.
final class FakeProvider: ToolProvider, @unchecked Sendable {
    let lock = NSLock()
    var calls: [(String, [String: JSONValue], String)] = []
    var rejected = 0
    var recipes: [Recipe]
    let report: CallReport
    let sleep: String?

    init(recipes: [Recipe] = [Catalog.remindersAdd, Catalog.notesCreate],
         report: CallReport = CallReport(tool: "reminders.add", ok: true, output: "Call the dentist", verified: true,
                                         detail: "read back through Shortcuts: due 26 Sep 2026 at 10:00", durationMs: 1100),
         sleep: String? = nil) {
        self.recipes = recipes
        self.report = report
        self.sleep = sleep
    }

    func tools() -> [Recipe] { lock.withLock { recipes } }

    func call(_ alias: String, args: [String: JSONValue], caller: String, cancel: CancelToken?) async -> CallReport {
        lock.withLock { calls.append((alias, args, caller)) }
        if let sleep { _ = await Shell.runAsync("/bin/sleep", [sleep], timeout: 30, cancel: cancel) }
        return report
    }

    func logRejected(caller: String) { lock.withLock { rejected += 1 } }
}

final class Sink: @unchecked Sendable {
    let lock = NSLock()
    var lines: [JSONValue] = []
    func write(_ d: Data) {
        let v = try! JSONDecoder().decode(JSONValue.self, from: d)
        lock.withLock { lines.append(v) }
    }
    var all: [JSONValue] { lock.withLock { lines } }
}

func run(_ lines: [String], provider: FakeProvider = FakeProvider()) async -> [JSONValue] {
    let sink = Sink()
    let server = MCPServer(provider: provider) { sink.write($0) }
    for l in lines { await server.handle(line: l) }
    return sink.all
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
        #expect(out[1]["result"]?["capabilities"]?["tools"]?["listChanged"] == true)
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
        let provider = FakeProvider()
        let out = await run([
            "not json",
            #"{"jsonrpc":"2.0","id":5,"method":"resources/list"}"#,
            #"{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"nope","arguments":{}}}"#,
            #"{"jsonrpc":"2.0","id":7,"method":"ping"}"#,
        ], provider: provider)
        #expect(out[0]["error"]?["code"] == -32700)
        #expect(out[1]["error"]?["code"] == -32601)
        #expect(out[2]["error"]?["code"] == -32602)
        #expect(out[3]["result"] == .object([:]))
        #expect(provider.rejected == 1)  // logged, without the client-supplied name
    }

    @Test func invalidRequestsAreRejected() async {
        let out = await run([
            #"{"jsonrpc":"2.0","id":{"a":1},"method":"ping"}"#,  // object id
            #"{"id":8,"method":"ping"}"#,                          // no "jsonrpc"
            #"{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"reminders_add","arguments":"x"}}"#,
            #"[]"#,
            #"{"jsonrpc":"2.0","id":10,"method":"ping","params":{"n":1e999}}"#,  // out of range: both parsers reject it
        ])
        #expect(out[0]["error"]?["code"] == -32600)
        #expect(out[0]["id"] == .null)
        #expect(out[1]["error"]?["code"] == -32600)
        #expect(out[1]["id"] == 8)
        #expect(out[2]["error"]?["code"] == -32602)  // arguments must be an object
        #expect(out[3]["error"]?["code"] == -32600)  // empty batch
        #expect(out[4]["error"]?["code"] == -32700)
    }

    @Test func batchesGetOneArrayOfReplies() async {
        let out = await run([#"[{"jsonrpc":"2.0","id":1,"method":"ping"},{"jsonrpc":"2.0","method":"notifications/initialized"},{"jsonrpc":"2.0","id":2,"method":"ping"}]"#])
        #expect(out.count == 1)
        #expect(out[0].arrayValue?.map { $0["id"] } == [1, 2])
    }

    @Test func deepNestingIsRefusedNotCrashed() async {
        let deep = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
        let out = await run([#"{"jsonrpc":"2.0","id":1,"method":"ping","params":{"x":"# + deep + "}}"])
        #expect(out[0]["error"]?["code"] == -32700)
    }

    @Test func hugeNumbersDontTrap() async {
        let out = await run([#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"reminders_add","arguments":{"title":1e300}}}"#])
        #expect(out.count == 1)  // answered (the fake provider accepts anything); no crash in stringValue
        #expect(JSONValue.number(1e300).stringValue != nil)
    }
}

@Suite struct ConcurrencyTests {
    /// Regression for the bug-hunt deadlock: more concurrent tool calls than CPUs, each running a real
    /// child process, plus a ping. Before the fix, 13 calls on a 14-CPU Mac never returned.
    @Test(.timeLimit(.minutes(1))) func burstOfCallsAndPingAllAnswered() async {
        let n = ProcessInfo.processInfo.activeProcessorCount + 4
        let provider = FakeProvider(sleep: "0.3")
        let sink = Sink()
        let server = MCPServer(provider: provider) { sink.write($0) }
        await withTaskGroup(of: Void.self) { g in
            for i in 0..<n {
                g.addTask {
                    await server.handle(line: #"{"jsonrpc":"2.0","id":\#(i),"method":"tools/call","params":{"name":"reminders_add","arguments":{"title":"t"}}}"#)
                }
            }
            g.addTask { await server.handle(line: #"{"jsonrpc":"2.0","id":"p","method":"ping"}"#) }
        }
        #expect(sink.all.count == n + 1)
        #expect(provider.calls.count == n)
    }

    @Test func cancelledRequestGetsNoResponse() async {
        let provider = FakeProvider(sleep: "5")
        let sink = Sink()
        let server = MCPServer(provider: provider) { sink.write($0) }
        let started = Date()
        async let call: Void = server.handle(line: #"{"jsonrpc":"2.0","id":42,"method":"tools/call","params":{"name":"reminders_add","arguments":{"title":"t"}}}"#)
        try? await Task.sleep(for: .milliseconds(300))
        await server.handle(line: #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":42}}"#)
        await call
        #expect(Date().timeIntervalSince(started) < 4)  // the child was stopped
        #expect(sink.all.isEmpty)
    }

    @Test func shellTimesOutAndCancels() async {
        let t0 = Date()
        let r = await Shell.runAsync("/bin/sleep", ["10"], timeout: 0.5)
        #expect(r?.timedOut == true)
        #expect(Date().timeIntervalSince(t0) < 5)
        let token = CancelToken()
        Task { try? await Task.sleep(for: .milliseconds(200)); token.cancel() }
        let c = await Shell.runAsync("/bin/sleep", ["10"], timeout: 30, cancel: token)
        #expect(c?.cancelled == true)
    }

    @Test func toolListChangeIsNotified() async {
        let provider = FakeProvider()
        let sink = Sink()
        let server = MCPServer(provider: provider) { sink.write($0) }
        await server.handle(line: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        await server.checkToolListChanged()
        #expect(sink.all.count == 1)  // unchanged: nothing sent
        provider.lock.withLock { provider.recipes = [Catalog.remindersAdd] }
        await server.checkToolListChanged()
        #expect(sink.all.last?["method"] == "notifications/tools/list_changed")
    }
}

@Suite struct ToolSchemaTests {
    @Test func namesAreClaudeSafeUniqueAndShort() {
        #expect(MCPServer.toolName("reminders.add") == "reminders_add")
        #expect(MCPServer.toolName("writing-tools-app-intents.summarize-text") == "writing-tools-app-intents_summarize-text")
        #expect(MCPServer.toolName("ünïcode.x").hasPrefix("_n_code_x_h"))
        #expect(MCPServer.toolName(String(repeating: "a", count: 80)).count <= MCPServer.maxToolName)
        // Names depend only on the alias: a swap (disable A, enable B) never reuses A's name for B.
        #expect(MCPServer.toolName("备忘录.新建笔记") != MCPServer.toolName("备忘录.删除笔记"))
        #expect(MCPServer.toolName("a.b") != MCPServer.toolName("a_b"))
        func r(_ a: String) -> Recipe { Recipe(alias: a, title: a, summary: "", appName: "", actionIdentifier: "", inputs: [], verified: nil) }
        let names = MCPServer.toolNames([r("a.b"), r("a_b"), r(String(repeating: "x", count: 70) + "1"), r(String(repeating: "x", count: 70) + "2")]).map(\.name)
        #expect(Set(names).count == 4)
        let alone = MCPServer.toolNames([r("备忘录.新建笔记")])[0].name
        let both = MCPServer.toolNames([r("备忘录.删除笔记"), r("备忘录.新建笔记")])
        #expect(both.first { $0.recipe.alias == "备忘录.新建笔记" }?.name == alone)
        #expect(Set(both.map(\.name)).count == 2)
        #expect(names.allSatisfy { $0.count <= MCPServer.maxToolName && $0.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil })
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
        #expect(t["annotations"]?["destructiveHint"] == false)  // additive catalog tool
        #expect(t["annotations"]?["openWorldHint"] == nil)
        var g = Catalog.notesCreate
        g.additive = false
        #expect(MCPServer.tool(g)["annotations"]?["destructiveHint"] == nil)  // unknown: MCP default applies
        #expect(t["description"]?.stringValue?.contains("read back") == true)
    }

    @Test func riskyGeneratedAndIntegerAreMarked() {
        var r = Catalog.notesCreate
        r.risky = true
        r.verified = nil
        r.inputs.append(RecipeInput("mode", "mode", .enumeration(["fast", "slow"])))
        r.inputs.append(RecipeInput("count", "count", .integer))
        let t = MCPServer.tool(r)
        #expect(t["annotations"]?["destructiveHint"] == true)
        #expect(t["description"]?.stringValue?.contains("not yet checked") == true)
        #expect(t["inputSchema"]?["properties"]?["mode"]?["enum"] == ["fast", "slow"])
        #expect(t["inputSchema"]?["properties"]?["count"]?["type"] == "integer")
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

    @Test func failureIsAToolErrorAndSaysOutcomeUnknown() {
        let r = MCPServer.result(CallReport(tool: "x", ok: false, error: "no result after 50 s", outcomeUnknown: true,
                                            durationMs: 50_000))
        #expect(r["isError"] == true)
        #expect(r["content"]?.arrayValue?.first?["text"] == "Error: no result after 50 s")
        #expect(r["structuredContent"]?["outcomeUnknown"] == true)
    }

    @Test func notVerifiedAndEmptyOutputAreSaid() {
        let r = MCPServer.result(CallReport(tool: "x", ok: true, output: "A", verified: false, detail: "not found"))
        #expect(r["content"]?.arrayValue?.first?["text"]?.stringValue?.hasSuffix("NOT verified: not found") == true)
        let e = MCPServer.result(CallReport(tool: "x", ok: true, output: ""))
        #expect(e["content"]?.arrayValue?.first?["text"]?.stringValue?.contains("no output") == true)
    }
}

@Suite struct AdoptionTests {
    @Test func pendingToolAdoptsOnlyANewCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("imcp-adopt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = ToolService(store: Store(root: root))
        let old = "10B4B703-45D5-4B51-9984-AC4B156D55E7", new = "F6E3EE8E-5E47-4A86-957B-AA7320753648"
        let t = EnabledTool(alias: "reminders.add", source: "catalog", actionID: nil, version: 2,
                            shortcutName: "intents-mcp reminders.add", shortcutUUID: nil, enabledAt: Date(),
                            allowRisky: false, staleUUIDs: [old])
        try svc.store.upsert(t)
        // Only the old version's copy is there: don't adopt it.
        #expect(try svc.adopt(t, library: [Library.Entry(name: "intents-mcp reminders.add", uuid: old)]) == nil)
        // The user added the new one (Shortcuts named it "… 2"): adopt that.
        let lib = [Library.Entry(name: "intents-mcp reminders.add", uuid: old),
                   Library.Entry(name: "intents-mcp reminders.add 2", uuid: new)]
        #expect(try svc.adopt(t, library: lib) == new)
        #expect(try svc.store.tools().first?.shortcutUUID == new)
        // An unreadable library adopts nothing.
        #expect(try svc.adopt(t, library: nil) == nil)
    }

    @Test func unknownToolIsLoggedWithoutItsName() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("imcp-log-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let svc = ToolService(store: Store(root: root))
        let r = await svc.call("secret text from the agent", args: [:], caller: "cli", verify: false)
        #expect(!r.ok)
        let log = try String(contentsOf: svc.store.logFile, encoding: .utf8)
        #expect(!log.contains("secret"))
        #expect(log.contains("<unknown>"))
    }
}

@Suite struct GateTests {
    @Test(.timeLimit(.minutes(1))) func waitersGiveUpAtDeadlineOrCancel() async {
        let g = AsyncGate(limit: 1)
        #expect(await g.acquire(until: Date().addingTimeInterval(10), cancel: nil))
        // Second caller: deadline passes while the first holds the gate.
        let t0 = Date()
        #expect(await g.acquire(until: Date().addingTimeInterval(0.5), cancel: nil) == false)
        #expect(Date().timeIntervalSince(t0) < 3)
        // Third caller: cancelled while waiting.
        let token = CancelToken()
        Task { try? await Task.sleep(for: .milliseconds(300)); token.cancel() }
        #expect(await g.acquire(until: Date().addingTimeInterval(30), cancel: token) == false)
        // Release hands the gate to the next live waiter.
        async let next = g.acquire(until: Date().addingTimeInterval(10), cancel: nil)
        try? await Task.sleep(for: .milliseconds(100))
        await g.release()
        #expect(await next)
    }
}
