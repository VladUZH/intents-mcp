import Foundation

/// Local state in ~/Library/Application Support/intents-mcp:
///   tools.json   the tools the user enabled (nothing is exposed unless it is here)
///   wrappers/    the generated and signed wrapper shortcuts
///   log.jsonl    one line per tool call: tool, time, duration, ok, verified; no personal content
public struct Store: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let env = ProcessInfo.processInfo.environment["INTENTS_MCP_HOME"], !env.isEmpty {
            self.root = URL(fileURLWithPath: env)
        } else {
            self.root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("intents-mcp")
        }
    }

    public var toolsFile: URL { root.appendingPathComponent("tools.json") }
    public var logFile: URL { root.appendingPathComponent("log.jsonl") }
    public var wrappersDir: URL { root.appendingPathComponent("wrappers") }

    func ensure(_ dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
    }

    // MARK: Enabled tools

    public func tools() throws -> [EnabledTool] {
        guard FileManager.default.fileExists(atPath: toolsFile.path) else { return [] }
        return try JSONDecoder.iso.decode([EnabledTool].self, from: Data(contentsOf: toolsFile))
    }

    public func save(_ tools: [EnabledTool]) throws {
        try ensure(root)
        let data = try JSONEncoder.iso.encode(tools.sorted { $0.alias < $1.alias })
        try data.write(to: toolsFile, options: .atomic)
    }

    public func upsert(_ tool: EnabledTool) throws {
        var all = try tools().filter { $0.alias != tool.alias }
        all.append(tool)
        try save(all)
    }

    public func remove(_ alias: String) throws -> EnabledTool? {
        let all = try tools()
        guard let t = all.first(where: { $0.alias == alias }) else { return nil }
        try save(all.filter { $0.alias != alias })
        return t
    }

    /// Where a wrapper version lives. The file name becomes the shortcut's name on import.
    public func wrapperURL(alias: String, version: Int, signed: Bool) throws -> URL {
        let dir = wrappersDir.appendingPathComponent("\(alias).v\(version)")
        try ensure(dir)
        return dir.appendingPathComponent("intents-mcp \(alias)\(signed ? "" : ".unsigned").shortcut")
    }

    // MARK: Call log (append-only)

    public func append(_ entry: LogEntry) throws {
        try ensure(root)
        var line = try JSONEncoder.iso.encode(entry)
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: logFile.path) {
            FileManager.default.createFile(atPath: logFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let h = try FileHandle(forWritingTo: logFile)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: line)
    }

    public func log(last n: Int) throws -> [LogEntry] {
        guard let text = try? String(contentsOf: logFile, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n").suffix(n)
        return lines.compactMap { try? JSONDecoder.iso.decode(LogEntry.self, from: Data($0.utf8)) }
    }
}

public struct EnabledTool: Codable, Sendable, Equatable {
    public var alias: String
    /// "catalog" (checked live) or "generated" (from metadata; `actionID` names the action).
    public var source: String
    public var actionID: String?
    public var version: Int
    public var shortcutName: String
    /// Resolved after the user clicks "Add Shortcut"; nil while pending.
    public var shortcutUUID: String?
    public var enabledAt: Date
    public var allowRisky: Bool

    public init(alias: String, source: String, actionID: String?, version: Int, shortcutName: String,
                shortcutUUID: String?, enabledAt: Date, allowRisky: Bool) {
        self.alias = alias
        self.source = source
        self.actionID = actionID
        self.version = version
        self.shortcutName = shortcutName
        self.shortcutUUID = shortcutUUID
        self.enabledAt = enabledAt
        self.allowRisky = allowRisky
    }
}

public struct LogEntry: Codable, Sendable, Equatable {
    public var tool: String
    public var time: Date
    public var durationMs: Int
    public var ok: Bool
    /// true/false when a read-back ran; nil when no read action exists for this tool.
    public var verified: Bool?
    /// Error category only (e.g. "timeout", "not-added"); never tool arguments or output.
    public var error: String?
    /// Who called: "cli" or "mcp:<client name>".
    public var caller: String

    public init(tool: String, time: Date, durationMs: Int, ok: Bool, verified: Bool?, error: String?, caller: String) {
        self.tool = tool
        self.time = time
        self.durationMs = durationMs
        self.ok = ok
        self.verified = verified
        self.error = error
        self.caller = caller
    }
}

extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
