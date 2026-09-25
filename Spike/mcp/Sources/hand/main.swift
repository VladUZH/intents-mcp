// M0 spike: minimal hand-written MCP server (JSON-RPC 2.0, newline-delimited, stdio).
// One tool, `echo`. Every inbound line is appended to $IMCP_TRACE for inspection.
import Foundation

let supported = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
let trace = ProcessInfo.processInfo.environment["IMCP_TRACE"].flatMap { FileHandle(forWritingAtPath: $0) }
trace?.seekToEndOfFile()

func log(_ s: String) {
    trace?.write(Data((s + "\n").utf8))
    FileHandle.standardError.write(Data(("[hand] " + s + "\n").utf8))
}

func send(_ obj: [String: Any]) {
    var data = try! JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])
    log("<- " + String(decoding: data, as: UTF8.self))
    data.append(0x0A)
    FileHandle.standardOutput.write(data)
}

let echoTool: [String: Any] = [
    "name": "echo",
    "title": "Echo",
    "description": "Returns the text it is given. Handshake test tool.",
    "inputSchema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]],
    "annotations": ["readOnlyHint": true, "destructiveHint": false, "openWorldHint": false],
]

while let line = readLine(strippingNewline: true) {
    if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
    log("-> " + line)
    guard let msg = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
        send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "parse error"]])
        continue
    }
    guard let id = msg["id"] else { continue }  // notification
    let method = msg["method"] as? String ?? ""
    let params = msg["params"] as? [String: Any] ?? [:]
    switch method {
    case "initialize":
        let asked = params["protocolVersion"] as? String ?? ""
        send(["jsonrpc": "2.0", "id": id, "result": [
            "protocolVersion": supported.contains(asked) ? asked : supported[0],
            "capabilities": ["tools": ["listChanged": false]],
            "serverInfo": ["name": "imcp-spike-hand", "version": "0.0.1"],
        ]])
    case "ping":
        send(["jsonrpc": "2.0", "id": id, "result": [:]])
    case "tools/list":
        send(["jsonrpc": "2.0", "id": id, "result": ["tools": [echoTool]]])
    case "tools/call":
        let args = params["arguments"] as? [String: Any] ?? [:]
        let text = args["text"] as? String ?? ""
        send(["jsonrpc": "2.0", "id": id, "result": [
            "content": [["type": "text", "text": "echo: " + text]],
            "structuredContent": ["echo": text],
            "isError": false,
        ]])
    default:
        send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "method not found: \(method)"]])
    }
}
