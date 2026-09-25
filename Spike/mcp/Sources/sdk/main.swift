// M0 spike: the same echo server on the official Swift SDK 0.12.1.
import MCP

let server = Server(name: "imcp-spike-sdk", version: "0.0.1", capabilities: .init(tools: .init(listChanged: false)))

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [Tool(
        name: "echo", title: "Echo", description: "Returns the text it is given. Handshake test tool.",
        inputSchema: .object(["type": "object", "properties": .object(["text": .object(["type": "string"])]),
                              "required": .array(["text"])]),
        annotations: .init(readOnlyHint: true, destructiveHint: false, openWorldHint: false))])
}
await server.withMethodHandler(CallTool.self) { params in
    let text = params.arguments?["text"]?.stringValue ?? ""
    return .init(content: [.text(text: "echo: " + text, annotations: nil, _meta: nil)], isError: false)
}
try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
