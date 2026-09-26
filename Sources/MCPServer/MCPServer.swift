import Core
import CryptoKit
import Foundation
import ShortcutForge

/// MCP over stdio: newline-delimited JSON-RPC 2.0, hand-written (M0: swift-sdk 0.12.1 fails
/// `initialize` with current Codex, swift-sdk#287; this form passed with Claude Code and Codex).
/// Implements initialize, ping, tools/list, tools/call, notifications/cancelled and
/// notifications/tools/list_changed. Clients that probe the 2026-07-28 `server/discover` get -32601
/// and fall back to `initialize` (as Claude Code does).
public actor MCPServer {
    public static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverVersion = IntentsMCPVersion.current
    /// Room for the client's "mcp__<server>__" prefix within Claude's 64-character tool-name limit.
    public static let maxToolName = 48
    /// JSON nesting deeper than this is refused before decoding (deep nesting overflowed the stack).
    public static let maxDepth = 64

    let provider: ToolProvider
    let output: @Sendable (Data) -> Void
    var clientName = "unknown"
    var inFlight: [String: CancelToken] = [:]
    var listedTools: [JSONValue]?

    public init(provider: ToolProvider, output: @escaping @Sendable (Data) -> Void) {
        self.provider = provider
        self.output = output
    }

    // MARK: Tool names and schemas

    /// Claude-safe names (^[a-zA-Z0-9_-]{1,64}$ including the client's prefix) that depend only on
    /// the alias, so a name never moves to a different tool as tools are enabled or disabled:
    /// - aliases of ASCII letters, digits, "-" and "." (no "_"), up to 48 characters, map
    ///   one-to-one by turning "." into "_" ("reminders.add" → "reminders_add");
    /// - any other alias (non-ASCII, "_", too long) gets a readable prefix plus a hash of itself.
    public static func toolNames(_ recipes: [Recipe]) -> [(name: String, recipe: Recipe)] {
        recipes.map { (name(for: $0.alias), $0) }.sorted { $0.name < $1.name }
    }

    static func name(for alias: String) -> String {
        let clean = alias.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == ".") }
        if clean, !alias.isEmpty, alias.count <= maxToolName {
            return alias.replacingOccurrences(of: ".", with: "_")
        }
        let prefix = String(alias.map { c -> Character in
            (c.isASCII && (c.isLetter || c.isNumber || c == "-")) ? c : "_"
        }.prefix(maxToolName - 10))
        let hash = SHA256.hash(data: Data(alias.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
        return prefix + "_h" + hash
    }

    public static func toolName(_ alias: String) -> String {
        toolNames([Recipe(alias: alias, title: "", summary: "", appName: "", actionIdentifier: "", inputs: [], verified: nil)])[0].name
    }

    public static func tool(_ r: Recipe, name: String? = nil) -> JSONValue {
        var props: [String: JSONValue] = [:]
        for i in r.exposedInputs {
            var p: [String: JSONValue] = [:]
            switch i.kind {
            case .text: p["type"] = "string"
            case .date:
                p["type"] = "string"
                if i.description.isEmpty { p["description"] = "A date and time as text, e.g. \"tomorrow at 10:00\"." }
            case .number: p["type"] = "number"
            case .integer: p["type"] = "integer"
            case .bool: p["type"] = "boolean"
            case .enumeration(let cases):
                p["type"] = "string"
                if !cases.isEmpty { p["enum"] = .array(cases.map { .string($0) }) }
            }
            if !i.description.isEmpty { p["description"] = .string(i.description) }
            props[i.name] = .object(p)
        }
        var description = "\(r.summary) (\(r.appName), via a Shortcuts wrapper on this Mac.)"
        if r.readBack != nil { description += " The result is read back to check it." }
        if r.verified == nil { description += " Generated from the app's metadata; not yet checked on a real run." }
        return [
            "name": .string(name ?? toolName(r.alias)),
            "title": .string(r.title),
            "description": .string(description),
            "inputSchema": ["type": "object", "properties": .object(props),
                            "required": .array(r.exposedInputs.filter(\.required).map { .string($0.name) }),
                            "additionalProperties": false],
            // No readOnly/openWorld claims: an app's own action may do either. destructiveHint is
            // false only for tools known to be additive (MCP: omitted means "may be destructive").
            "annotations": r.risky ? ["title": .string(r.title), "destructiveHint": true, "idempotentHint": false]
                : r.additive ? ["title": .string(r.title), "destructiveHint": false, "idempotentHint": false]
                : ["title": .string(r.title), "idempotentHint": false],
        ]
    }

    // MARK: JSON-RPC

    struct RPCError: Error {
        var code: Int
        var message: String
    }

    /// Handles one line: a request, a notification, or a batch (JSON array).
    public func handle(line: String) async {
        guard Self.depth(line) <= Self.maxDepth else {
            return send(Self.error(.null, -32700, "parse error: nesting too deep"))
        }
        guard let msg = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)) else {
            // Valid JSON we can't represent (e.g. a number beyond Double) is an invalid request, not a parse error.
            let isJSON = (try? JSONSerialization.jsonObject(with: Data(line.utf8), options: [.fragmentsAllowed])) != nil
            return send(Self.error(.null, isJSON ? -32600 : -32700, isJSON ? "invalid request" : "parse error"))
        }
        if case .array(let items) = msg {
            guard !items.isEmpty else { return send(Self.error(.null, -32600, "invalid request: empty batch")) }
            var replies: [JSONValue] = []
            for item in items { if let r = await respond(item) { replies.append(r) } }
            if !replies.isEmpty { send(.array(replies)) }
            return
        }
        if let r = await respond(msg) { send(r) }
    }

    /// The response for one message, or nil for notifications and cancelled requests.
    func respond(_ msg: JSONValue) async -> JSONValue? {
        guard case .object = msg else { return Self.error(.null, -32600, "invalid request") }
        let method = msg["method"]?.stringValue ?? ""
        let params = msg["params"] ?? .object([:])
        guard let id = msg["id"] else {
            // Notification.
            if method == "notifications/cancelled", let target = params["requestId"] {
                inFlight[Self.key(target)]?.cancel()
            }
            return nil
        }
        switch id {
        case .string, .number: break
        default: return Self.error(.null, -32600, "invalid request: id must be a string or a number")
        }
        guard msg["jsonrpc"]?.stringValue == "2.0", !method.isEmpty else {
            return Self.error(id, -32600, "invalid request")
        }
        let token = CancelToken()
        let key = Self.key(id)
        inFlight[key] = token
        defer { inFlight[key] = nil }
        do {
            let result = try await dispatch(method, params, cancel: token)
            // MCP: a cancelled request gets no response.
            return token.isCancelled ? nil : ["jsonrpc": "2.0", "id": id, "result": result]
        } catch let e as RPCError {
            return Self.error(id, e.code, e.message)
        } catch {
            return Self.error(id, -32603, "\(error)")
        }
    }

    func dispatch(_ method: String, _ params: JSONValue, cancel: CancelToken) async throws -> JSONValue {
        switch method {
        case "initialize":
            clientName = params["clientInfo"]?["name"]?.stringValue ?? "unknown"
            let asked = params["protocolVersion"]?.stringValue ?? ""
            return [
                "protocolVersion": .string(Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0]),
                "capabilities": ["tools": ["listChanged": true]],
                "serverInfo": ["name": "intents-mcp", "title": "Mac App Intents", "version": .string(Self.serverVersion)],
                "instructions": """
                    Tools run actions in Mac apps through Shortcuts on this Mac. The user chose each tool. \
                    Results say whether they were read back ("verified"). Dates are text, e.g. "tomorrow at 10:00" \
                    or ISO 8601. If a result says the outcome is unknown, ask the user before retrying.
                    """,
            ]
        case "ping":
            return .object([:])
        case "tools/list":
            let tools = Self.toolNames(provider.tools()).map { Self.tool($0.recipe, name: $0.name) }
            listedTools = tools
            return ["tools": .array(tools)]
        case "tools/call":
            let name = params["name"]?.stringValue ?? ""
            guard let recipe = Self.toolNames(provider.tools()).first(where: { $0.name == name })?.recipe else {
                provider.logRejected(caller: "mcp:\(clientName)")
                throw RPCError(code: -32602, message: "unknown tool: \(name). It may have been disabled; list the tools again")
            }
            let args: [String: JSONValue]
            switch params["arguments"] {
            case nil, .null?: args = [:]
            case .object(let o)?: args = o
            default: throw RPCError(code: -32602, message: "arguments must be an object")
            }
            let report = await provider.call(recipe.alias, args: args, caller: "mcp:\(clientName)", cancel: cancel)
            return Self.result(report)
        default:
            throw RPCError(code: -32601, message: "method not found: \(method)")
        }
    }

    /// Sends notifications/tools/list_changed when the enabled tools differ from what the client listed.
    func checkToolListChanged() {
        guard let listed = listedTools else { return }
        // Full definitions, not just names: a re-enabled tool may have a new schema.
        let now = Self.toolNames(provider.tools()).map { Self.tool($0.recipe, name: $0.name) }
        guard now != listed else { return }
        listedTools = now
        send(["jsonrpc": "2.0", "method": "notifications/tools/list_changed"])
    }

    /// Tool errors are results with isError (the model sees them), not JSON-RPC errors.
    static func result(_ r: CallReport) -> JSONValue {
        var text: String
        if r.ok {
            text = r.output?.isEmpty == false ? r.output! : "Done, but the shortcut returned no output."
            switch r.verified {
            case true?: text += "\nVerified: \(r.detail ?? "read back")"
            case false?: text += "\nNOT verified: \(r.detail ?? "read-back did not find it")"
            case nil: if let d = r.detail, d != "no read action for this tool" { text += "\n\(d)" }
            }
        } else {
            text = "Error: \(r.error ?? "unknown error")"
            if let d = r.detail { text += "\nRead-back: \(d)" }
        }
        if let w = r.logWarning { text += "\nWarning: \(w)" }
        var structured: [String: JSONValue] = ["ok": .bool(r.ok), "durationMs": .number(Double(r.durationMs))]
        if let o = r.output { structured["output"] = .string(o) }
        if let e = r.error { structured["error"] = .string(e) }
        if r.outcomeUnknown == true { structured["outcomeUnknown"] = true }
        if let v = r.verified { structured["verified"] = .bool(v) }
        if let d = r.detail { structured["detail"] = .string(d) }
        if let w = r.logWarning { structured["logWarning"] = .string(w) }
        return ["content": [["type": "text", "text": .string(text)]], "structuredContent": .object(structured),
                "isError": .bool(!r.ok)]
    }

    static func error(_ id: JSONValue, _ code: Int, _ message: String) -> JSONValue {
        ["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(code)), "message": .string(message)]]
    }

    static func key(_ id: JSONValue) -> String {
        switch id {
        case .string(let s): return "s:" + s
        default: return "n:" + (id.stringValue ?? "")
        }
    }

    /// Maximum [ / { nesting outside strings, without decoding.
    static func depth(_ line: String) -> Int {
        var depth = 0, maxDepth = 0, inString = false, escaped = false
        for b in line.utf8 {
            if inString {
                if escaped { escaped = false } else if b == UInt8(ascii: "\\") { escaped = true } else if b == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch b {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "["), UInt8(ascii: "{"): depth += 1; maxDepth = max(maxDepth, depth)
            case UInt8(ascii: "]"), UInt8(ascii: "}"): depth -= 1
            default: break
            }
        }
        return maxDepth
    }

    func send(_ v: JSONValue) {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        guard var data = try? e.encode(v) else { return }
        data.append(0x0A)
        output(data)
    }

    /// Serves stdin until EOF. stdin is read on a dedicated thread and every request runs in its own
    /// task, so a slow shortcut never blocks `ping` and no blocking call holds a cooperative-pool
    /// thread. Diagnostics go to stderr only; stdout carries JSON-RPC and nothing else.
    public static func serveStdio(provider: ToolProvider) async {
        signal(SIGPIPE, SIG_IGN)  // a client that went away must not kill the server mid-call
        let server = MCPServer(provider: provider) { data in
            try? FileHandle.standardOutput.write(contentsOf: data)
        }
        let lines = AsyncStream<String> { continuation in
            Thread.detachNewThread {
                while let line = readLine(strippingNewline: true) { continuation.yield(line) }
                continuation.finish()
            }
        }
        let watcher = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                await server.checkToolListChanged()
            }
        }
        await withDiscardingTaskGroup { group in
            for await line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
                group.addTask { await server.handle(line: line) }
            }
        }
        watcher.cancel()
    }
}
