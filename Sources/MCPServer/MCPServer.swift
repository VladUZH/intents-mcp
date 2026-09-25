import Core
import Foundation
import ShortcutForge

/// MCP over stdio: newline-delimited JSON-RPC 2.0, hand-written (M0: swift-sdk 0.12.1 fails
/// `initialize` with current Codex, swift-sdk#287; this form passed with Claude Code and Codex).
/// Implements initialize, ping, tools/list, tools/call and notifications. Clients that probe the
/// 2026-07-28 `server/discover` get -32601 and fall back to `initialize` (as Claude Code does).
public actor MCPServer {
    public static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    public static let serverVersion = "0.1.0-dev"

    let provider: ToolProvider
    let output: @Sendable (Data) -> Void
    var clientName = "unknown"

    public init(provider: ToolProvider, output: @escaping @Sendable (Data) -> Void) {
        self.provider = provider
        self.output = output
    }

    // MARK: Tool names and schemas

    /// Tool names must match ^[a-zA-Z0-9_-]{1,64}$ for Claude's API: "reminders.add" → "reminders_add".
    public static func toolName(_ alias: String) -> String {
        let mapped = alias.map { c -> Character in (c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_")) ? c : "_" }
        return String(String(mapped).prefix(64))
    }

    public static func tool(_ r: Recipe) -> JSONValue {
        var props: [String: JSONValue] = [:]
        for i in r.exposedInputs {
            var p: [String: JSONValue] = [:]
            switch i.kind {
            case .text: p["type"] = "string"
            case .date:
                p["type"] = "string"
                if i.description.isEmpty { p["description"] = "A date and time as text, e.g. \"tomorrow at 10:00\"." }
            case .number: p["type"] = "number"
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
            "name": .string(toolName(r.alias)),
            "title": .string(r.title),
            "description": .string(description),
            "inputSchema": ["type": "object", "properties": .object(props),
                            "required": .array(r.exposedInputs.filter(\.required).map { .string($0.name) }),
                            "additionalProperties": false],
            "annotations": ["title": .string(r.title), "destructiveHint": .bool(r.risky),
                            "idempotentHint": false, "openWorldHint": false],
        ]
    }

    // MARK: JSON-RPC

    struct RPCError: Error {
        var code: Int
        var message: String
    }

    public func handle(line: String) async {
        guard let msg = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), case .object = msg else {
            send(["jsonrpc": "2.0", "id": .null, "error": ["code": -32700, "message": "parse error"]])
            return
        }
        guard let id = msg["id"], id != .null else { return }  // notifications get no response
        let method = msg["method"]?.stringValue ?? ""
        do {
            let result = try await dispatch(method, msg["params"] ?? .object([:]))
            send(["jsonrpc": "2.0", "id": id, "result": result])
        } catch let e as RPCError {
            send(["jsonrpc": "2.0", "id": id, "error": ["code": .number(Double(e.code)), "message": .string(e.message)]])
        } catch {
            send(["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": .string("\(error)")]])
        }
    }

    func dispatch(_ method: String, _ params: JSONValue) async throws -> JSONValue {
        switch method {
        case "initialize":
            clientName = params["clientInfo"]?["name"]?.stringValue ?? "unknown"
            let asked = params["protocolVersion"]?.stringValue ?? ""
            return [
                "protocolVersion": .string(Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0]),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "intents-mcp", "title": "Mac App Intents", "version": .string(Self.serverVersion)],
                "instructions": """
                    Tools run actions in Mac apps through Shortcuts on this Mac. The user chose each tool. \
                    Results say whether they were read back ("verified"). Dates are text, e.g. "tomorrow at 10:00".
                    """,
            ]
        case "ping":
            return .object([:])
        case "tools/list":
            return ["tools": .array(provider.tools().map(Self.tool))]
        case "tools/call":
            let name = params["name"]?.stringValue ?? ""
            guard let recipe = provider.tools().first(where: { Self.toolName($0.alias) == name }) else {
                throw RPCError(code: -32602, message: "unknown tool: \(name)")
            }
            let args = params["arguments"]?.objectValue ?? [:]
            let report = await provider.call(recipe.alias, args: args, caller: "mcp:\(clientName)")
            return Self.result(report)
        default:
            throw RPCError(code: -32601, message: "method not found: \(method)")
        }
    }

    /// Tool errors are results with isError (the model sees them), not JSON-RPC errors.
    static func result(_ r: CallReport) -> JSONValue {
        var text: String
        if r.ok {
            text = r.output?.isEmpty == false ? r.output! : "Done."
            switch r.verified {
            case true?: text += "\nVerified: \(r.detail ?? "read back")"
            case false?: text += "\nNOT verified: \(r.detail ?? "read-back did not find it")"
            case nil: if let d = r.detail, d != "no read action for this tool" { text += "\n\(d)" }
            }
        } else {
            text = "Error: \(r.error ?? "unknown error")"
        }
        var structured: [String: JSONValue] = ["ok": .bool(r.ok), "durationMs": .number(Double(r.durationMs))]
        if let o = r.output { structured["output"] = .string(o) }
        if let e = r.error { structured["error"] = .string(e) }
        if let v = r.verified { structured["verified"] = .bool(v) }
        if let d = r.detail { structured["detail"] = .string(d) }
        return ["content": [["type": "text", "text": .string(text)]], "structuredContent": .object(structured),
                "isError": .bool(!r.ok)]
    }

    func send(_ v: JSONValue) {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        guard var data = try? e.encode(v) else { return }
        data.append(0x0A)
        output(data)
    }

    /// Serves stdin until EOF. Requests run concurrently (a slow shortcut doesn't block ping);
    /// writes are serialized by the actor. Diagnostics go to stderr only.
    public static func serveStdio(provider: ToolProvider) async {
        let server = MCPServer(provider: provider) { data in FileHandle.standardOutput.write(data) }
        await withTaskGroup(of: Void.self) { group in
            while let line = readLine(strippingNewline: true) {
                if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                group.addTask { await server.handle(line: line) }
            }
        }
    }
}
