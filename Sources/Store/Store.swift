import Foundation

/// Local state in ~/Library/Application Support/intents-mcp:
///   tools.json   the tools the user enabled (nothing is exposed unless it is here)
///   wrappers/    the generated wrapper shortcuts (signed copies are deleted once added)
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
        do {
            return try JSONDecoder.iso.decode([EnabledTool].self, from: Data(contentsOf: toolsFile))
        } catch {
            throw StoreError.unreadable(toolsFile.path, "\(error)")
        }
    }

    /// Deletes a signed wrapper once its shortcut is in the library: the file carries the user's
    /// Apple Account signing identity and isn't needed after import.
    public func removeSignedWrapper(alias: String, version: Int) {
        let dir = wrappersDir.appendingPathComponent("\(alias).v\(version)")
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("intents-mcp \(alias).shortcut"))
    }

    /// Removes signed wrappers of every tool whose shortcut was added (also cleans up after 0.1.x).
    public func removeSignedWrappersOfAddedTools() {
        for t in (try? tools()) ?? [] where t.shortcutUUID != nil { removeSignedWrapper(alias: t.alias, version: t.version) }
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

    /// Removes every tool whose alias or action id is `key`; returns what was removed.
    public func remove(_ key: String) throws -> [EnabledTool] {
        let all = try tools()
        let hits = all.filter { $0.alias == key || ($0.actionID != nil && $0.actionID == key) }
        guard !hits.isEmpty else { return [] }
        try save(all.filter { t in !hits.contains(t) })
        return hits
    }

    /// Re-reads tools.json and changes one tool, so a stale copy never overwrites newer state
    /// (e.g. re-enabling a tool the user just disabled). Returns false if the tool is gone.
    @discardableResult
    public func update(_ alias: String, _ change: (inout EnabledTool) -> Void) throws -> Bool {
        var all = try tools()
        guard let i = all.firstIndex(where: { $0.alias == alias }) else { return false }
        change(&all[i])
        try save(all)
        return true
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
        // One O_APPEND write per line: concurrent writers (several clients, the CLI) can't
        // overwrite each other, and creating the file never truncates an existing one.
        let fd = open(logFile.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        let n = line.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
        guard n == line.count else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }

    public func log(last n: Int) throws -> [LogEntry] {
        guard FileManager.default.fileExists(atPath: logFile.path) else { return [] }
        guard let data = FileManager.default.contents(atPath: logFile.path) else {
            throw StoreError.unreadable(logFile.path, "permission denied or not a file")
        }
        // Lossy decoding: one bad byte or line must not hide the rest of the log.
        let lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
        let entries = lines.compactMap { try? JSONDecoder.iso.decode(LogEntry.self, from: Data($0.utf8)) }
        return Array(entries.suffix(max(0, n)))
    }
}

public enum StoreError: Error, CustomStringConvertible {
    case unreadable(String, String)

    public var description: String {
        switch self {
        case .unreadable(let path, let why):
            return "\(path) can't be read (\(why)). Fix or remove it; `intents-mcp doctor` checks it"
        }
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
    /// Shortcuts with this name that existed before this version was imported (an older version's
    /// wrapper); a pending entry never adopts them.
    public var staleUUIDs: [String]?

    public init(alias: String, source: String, actionID: String?, version: Int, shortcutName: String,
                shortcutUUID: String?, enabledAt: Date, allowRisky: Bool, staleUUIDs: [String]? = nil) {
        self.alias = alias
        self.source = source
        self.actionID = actionID
        self.version = version
        self.shortcutName = shortcutName
        self.shortcutUUID = shortcutUUID
        self.enabledAt = enabledAt
        self.allowRisky = allowRisky
        self.staleUUIDs = staleUUIDs
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
    /// Pairs a "start" line with its "end" line; a start without an end means the call was
    /// interrupted (the action may still have run). nil in logs written before 0.1.3.
    public var callID: String?
    /// "start" or "end" (nil = "end", for older logs).
    public var event: String?

    public init(tool: String, time: Date, durationMs: Int, ok: Bool, verified: Bool?, error: String?, caller: String,
                callID: String? = nil, event: String? = nil) {
        self.tool = tool
        self.time = time
        self.durationMs = durationMs
        self.ok = ok
        self.verified = verified
        self.error = error
        self.caller = caller
        self.callID = callID
        self.event = event
    }
}

extension JSONEncoder {
    public static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }
}

extension JSONDecoder {
    public static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
