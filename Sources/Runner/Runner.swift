import Core
import Foundation
import ShortcutForge

public enum CallError: Error, Equatable, CustomStringConvertible {
    case invalidArguments(String)
    case notAdded(String)
    case timeout(Int)
    /// The run ended without a result: the action may or may not have happened.
    case noResult
    case cancelled
    /// Known not to have run (cancelled or out of time before it started).
    case notStarted(String)
    case failed(String)

    /// Short category for the call log (never arguments or output).
    public var category: String {
        switch self {
        case .invalidArguments: return "invalid-arguments"
        case .notAdded: return "not-added"
        case .timeout: return "timeout"
        case .noResult: return "no-result"
        case .cancelled: return "cancelled"
        case .notStarted: return "not-started"
        case .failed: return "failed"
        }
    }

    /// true when the action may still have run (don't retry blindly).
    public var outcomeUnknown: Bool {
        switch self {
        case .timeout, .noResult, .cancelled: return true
        default: return false
        }
    }

    public var description: String {
        switch self {
        case .invalidArguments(let m): return "invalid arguments: \(m)"
        case .notAdded(let alias):
            return "the wrapper shortcut is not in your Shortcuts library; run `intents-mcp enable \(alias)` and click Add Shortcut"
        case .timeout(let s):
            return "no result after \(s) s. The action may still run if a Shortcuts permission dialog is answered later, so ask the user whether it happened before retrying (retrying may create a duplicate). If Shortcuts shows a dialog for an intents-mcp shortcut, choose Always Allow"
        case .noResult:
            return "the shortcut finished without a result, so the action may not have run (or may still run once a Shortcuts permission dialog is answered). Ask the user whether it happened before retrying; if Shortcuts shows a dialog, choose Always Allow"
        case .cancelled: return "cancelled; the action may already have started"
        case .notStarted(let why): return "not started (\(why)); nothing was done, so it is safe to try again"
        case .failed(let m): return m
        }
    }
}

public struct CallOutput: Sendable, Equatable {
    /// Raw output text (not trimmed).
    public var text: String
    public var durationMs: Int
}

public enum Runner {
    /// Checks arguments against the recipe: unknown or missing keys fail loudly, because Shortcuts
    /// silently ignores keys it doesn't know (M0).
    public static func validate(_ args: [String: JSONValue], for r: Recipe) throws {
        let exposed = Dictionary(uniqueKeysWithValues: r.exposedInputs.map { ($0.name, $0) })
        for key in args.keys.sorted() where exposed[key] == nil {
            throw CallError.invalidArguments("unknown argument \"\(key)\"; expected \(exposed.keys.sorted().joined(separator: ", "))")
        }
        for input in r.exposedInputs {
            guard let v = args[input.name], v != .null else {
                if input.required { throw CallError.invalidArguments("\"\(input.name)\" is required") }
                continue
            }
            switch (input.kind, v) {
            case (.text, .string), (.date, .string), (.number, .number), (.bool, .bool): break
            case (.integer, .number(let n)) where n.rounded() == n && abs(n) < 9.0e15: break
            case (.integer, .number):
                throw CallError.invalidArguments("\"\(input.name)\" must be a whole number")
            case (.enumeration(let cases), .string(let s)) where cases.isEmpty || cases.contains(s): break
            case (.enumeration(let cases), _):
                throw CallError.invalidArguments("\"\(input.name)\" must be one of \(cases.joined(separator: ", "))")
            default:
                throw CallError.invalidArguments("\"\(input.name)\" has the wrong type")
            }
            if case .string(let s) = v {
                if input.required, s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw CallError.invalidArguments("\"\(input.name)\" is empty")
                }
                if input.kind == .date { _ = try normalizedDate(s, name: input.name) }
            }
        }
    }

    /// Date text for Shortcuts. Shortcuts' parser drops the time from ISO 8601 / RFC 3339 values with a
    /// negative UTC offset ("2026-10-01T09:30:00-07:00" becomes 12:00), so timestamps with an offset
    /// are converted to local wall-clock time, which it reads correctly. Other text passes unchanged.
    public static func normalizedDate(_ s: String, name: String = "date") throws -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.range(of: #"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?\s*(Z|z|[+-]\d{2}:?\d{2})$"#,
                      options: .regularExpression) != nil else {
            if t.range(of: #"\d{2}:\d{2}.*\s(UTC|GMT)?[+-]\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                throw CallError.invalidArguments("\"\(name)\" has a UTC offset in a form that can't be read; use local time like \"2026-10-01 09:30\" or ISO 8601 like \"2026-10-01T09:30:00-07:00\"")
            }
            return t
        }
        // Normalise to the strict ISO 8601 form the formatter accepts: "T", seconds, "±HH:MM".
        var iso = t.replacingOccurrences(of: #"\s+(?=[+-]\d{2}:?\d{2}$|[Zz]$)"#, with: "", options: .regularExpression)
        iso = iso.replacingOccurrences(of: " ", with: "T")
        iso = iso.replacingOccurrences(of: #"T(\d{2}:\d{2})(?=[-+Zz])"#, with: "T$1:00", options: .regularExpression)
        iso = iso.replacingOccurrences(of: #"([+-]\d{2})(\d{2})$"#, with: "$1:$2", options: .regularExpression)
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        let ff = ISO8601DateFormatter()
        ff.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = f.date(from: iso) ?? ff.date(from: iso) else {
            throw CallError.invalidArguments("\"\(name)\" is not a valid date and time: \(t)")
        }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.timeZone = .current
        out.dateFormat = "yyyy-MM-dd HH:mm"
        return out.string(from: date)
    }

    /// The wrapper's input JSON: prepared arguments restricted to the keys the wrapper reads.
    public static func wrapperInput(_ args: [String: JSONValue], for r: Recipe) -> [String: JSONValue] {
        var normalized = args
        for input in r.inputs where input.kind == .date {
            if case .string(let s)? = args[input.name], let d = try? normalizedDate(s, name: input.name) {
                normalized[input.name] = .string(d)
            }
        }
        let wired = Set(r.inputs.filter { !$0.plistKey.isEmpty }.map(\.name))
        return r.prepare(normalized).filter { wired.contains($0.key) && $0.value != .null }
    }

    /// Runs the wrapper by UUID with its own stdin (/dev/null) and a timeout.
    public static func call(_ r: Recipe, uuid: String, args: [String: JSONValue], timeout: Int = 30,
                            cancel: CancelToken? = nil) async throws -> CallOutput {
        try validate(args, for: r)
        let dir = try TempDir.make("intents-mcp-")
        defer { TempDir.remove(dir) }
        let input = dir.appendingPathComponent("input.json")
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        try e.encode(JSONValue.object(wrapperInput(args, for: r))).write(to: input)
        return try await runShortcut(uuid: uuid, input: input, alias: r.alias, timeout: timeout, cancel: cancel)
    }

    /// `shortcuts run <UUID>` with an optional input file, stdin from /dev/null, and a timeout.
    public static func runShortcut(uuid: String, input: URL?, alias: String, timeout: Int,
                                   cancel: CancelToken? = nil) async throws -> CallOutput {
        let dir = try TempDir.make("intents-mcp-out-")
        defer { TempDir.remove(dir) }
        let output = dir.appendingPathComponent("output.txt")
        var args = ["run", uuid]
        if let input { args += ["--input-path", input.path] }
        args += ["--output-path", output.path, "--output-type", "public.plain-text"]
        let started = Date()
        guard let res = await Shell.runAsync("/usr/bin/shortcuts", args, timeout: TimeInterval(max(1, timeout)), cancel: cancel) else {
            throw CallError.failed("could not start /usr/bin/shortcuts")
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if res.cancelled { throw CallError.cancelled }
        if res.timedOut { throw CallError.timeout(timeout) }
        guard res.status == 0 else {
            // Decide "not added" from the library, not from the (localized) error text.
            if let entries = await Library.entries(timeout: 5), !entries.contains(where: { $0.uuid == uuid }) {
                throw CallError.notAdded(alias)
            }
            let msg = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Error: ", with: "")
            throw CallError.failed(msg.isEmpty ? "shortcut failed (exit \(res.status))" : msg)
        }
        // Every wrapper ends with Stop and Output: no output file means it did not finish.
        guard let data = FileManager.default.contents(atPath: output.path) else { throw CallError.noResult }
        return CallOutput(text: String(decoding: data, as: UTF8.self), durationMs: ms)
    }
}

/// Private temporary folders (0700) for inputs and outputs, removed after use and on shutdown.
public enum TempDir {
    private static let live = Live()

    public static func make(_ prefix: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(prefix + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        live.insert(dir)
        return dir
    }

    public static func remove(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
        live.remove(dir)
    }

    /// For signal handlers: tool arguments and outputs must not stay in $TMPDIR.
    public static func removeAll() {
        for d in live.all() { try? FileManager.default.removeItem(at: d) }
    }

    final class Live: @unchecked Sendable {
        private var dirs = Set<URL>()
        private let lock = NSLock()
        func insert(_ u: URL) { _ = lock.withLock { dirs.insert(u) } }
        func remove(_ u: URL) { _ = lock.withLock { dirs.remove(u) } }
        func all() -> [URL] { lock.withLock { Array(dirs) } }
    }
}

/// The user's Shortcuts library, by name and UUID.
public enum Library {
    public struct Entry: Sendable, Equatable {
        public var name: String
        public var uuid: String

        public init(name: String, uuid: String) {
            self.name = name
            self.uuid = uuid
        }
    }

    public static func parse(_ listing: String) -> [Entry] {
        listing.split(separator: "\n").compactMap { line in
            // "<name> (<UUID>)"; names may contain parentheses, so take the last group.
            guard line.hasSuffix(")"), let open = line.range(of: " (", options: .backwards) else { return nil }
            let uuid = String(line[open.upperBound..<line.index(before: line.endIndex)])
            guard UUID(uuidString: uuid) != nil else { return nil }
            return Entry(name: String(line[..<open.lowerBound]), uuid: uuid)
        }
    }

    /// nil when the library can't be read (then callers must not assume anything is missing).
    public static func entries(timeout: TimeInterval = 30) async -> [Entry]? {
        guard let r = await Shell.runAsync("/usr/bin/shortcuts", ["list", "--show-identifiers"], timeout: timeout),
              !r.timedOut, !r.incomplete, r.status == 0 else { return nil }
        return parse(r.stdout)
    }

    /// Entries whose name is `name` or Shortcuts' de-duplicated "`name` 2", "`name` 3"…
    public static func matching(_ name: String, in entries: [Entry]) -> [Entry] {
        entries.filter { e in
            e.name == name || (e.name.hasPrefix(name + " ") && Int(e.name.dropFirst(name.count + 1)) != nil)
        }
    }
}
