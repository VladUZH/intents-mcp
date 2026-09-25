import Core
import Foundation
import ShortcutForge

public enum CallError: Error, Equatable, CustomStringConvertible {
    case invalidArguments(String)
    case notAdded(String)
    case timeout(Int)
    case failed(String)

    /// Short category for the call log (never arguments or output).
    public var category: String {
        switch self {
        case .invalidArguments: return "invalid-arguments"
        case .notAdded: return "not-added"
        case .timeout: return "timeout"
        case .failed: return "failed"
        }
    }

    public var description: String {
        switch self {
        case .invalidArguments(let m): return "invalid arguments: \(m)"
        case .notAdded(let alias):
            return "the wrapper shortcut is not in your Shortcuts library; run `intents-mcp enable \(alias)` and click Add Shortcut"
        case .timeout(let s):
            return "no result after \(s) s. If Shortcuts is showing a permission dialog for an intents-mcp shortcut, choose Always Allow (needed once per tool, and again after an upgrade)"
        case .failed(let m): return m
        }
    }
}

public struct CallOutput: Sendable, Equatable {
    public var text: String
    public var durationMs: Int
}

public enum Runner {
    /// Checks arguments against the recipe: unknown or missing keys fail loudly, because Shortcuts
    /// silently ignores keys it doesn't know (M0).
    public static func validate(_ args: [String: JSONValue], for r: Recipe) throws {
        let exposed = Dictionary(uniqueKeysWithValues: r.exposedInputs.map { ($0.name, $0) })
        for key in args.keys where exposed[key] == nil {
            throw CallError.invalidArguments("unknown argument \"\(key)\"; expected \(exposed.keys.sorted().joined(separator: ", "))")
        }
        for input in r.exposedInputs {
            guard let v = args[input.name], v != .null else {
                if input.required { throw CallError.invalidArguments("\"\(input.name)\" is required") }
                continue
            }
            switch (input.kind, v) {
            case (.text, .string), (.date, .string), (.number, .number), (.bool, .bool): break
            case (.enumeration(let cases), .string(let s)) where cases.isEmpty || cases.contains(s): break
            case (.enumeration(let cases), _):
                throw CallError.invalidArguments("\"\(input.name)\" must be one of \(cases.joined(separator: ", "))")
            default:
                throw CallError.invalidArguments("\"\(input.name)\" has the wrong type")
            }
            if input.required, case .string(let s) = v, s.trimmingCharacters(in: .whitespaces).isEmpty {
                throw CallError.invalidArguments("\"\(input.name)\" is empty")
            }
        }
    }

    /// The wrapper's input JSON: prepared arguments restricted to the keys the wrapper reads.
    public static func wrapperInput(_ args: [String: JSONValue], for r: Recipe) -> [String: JSONValue] {
        let wired = Set(r.inputs.filter { !$0.plistKey.isEmpty }.map(\.name))
        return r.prepare(args).filter { wired.contains($0.key) && $0.value != .null }
    }

    /// Runs the wrapper by UUID with its own stdin (/dev/null) and a timeout.
    public static func call(_ r: Recipe, uuid: String, args: [String: JSONValue], timeout: Int = 30) throws -> CallOutput {
        try validate(args, for: r)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("intents-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let input = dir.appendingPathComponent("input.json")
        let output = dir.appendingPathComponent("output.txt")
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        try e.encode(JSONValue.object(wrapperInput(args, for: r))).write(to: input)

        let started = Date()
        guard let res = Shell.run("/usr/bin/shortcuts",
                                  ["run", uuid, "--input-path", input.path, "--output-path", output.path,
                                   "--output-type", "public.plain-text"], timeout: TimeInterval(timeout)) else {
            throw CallError.failed("could not start /usr/bin/shortcuts")
        }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        if res.timedOut { throw CallError.timeout(timeout) }
        let err = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if err.contains("Couldn’t find shortcut") || err.contains("Couldn't find shortcut") { throw CallError.notAdded(r.alias) }
        guard res.status == 0 else {
            throw CallError.failed(err.replacingOccurrences(of: "Error: ", with: "").isEmpty ? "shortcut failed (exit \(res.status))" : err.replacingOccurrences(of: "Error: ", with: ""))
        }
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        return CallOutput(text: text.trimmingCharacters(in: .whitespacesAndNewlines), durationMs: ms)
    }
}

/// The user's Shortcuts library, by name and UUID.
public enum Library {
    public struct Entry: Sendable, Equatable {
        public var name: String
        public var uuid: String
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

    public static func entries() -> [Entry]? {
        guard let r = Shell.run("/usr/bin/shortcuts", ["list", "--show-identifiers"], timeout: 30),
              !r.timedOut, r.status == 0 else { return nil }
        return parse(r.stdout)
    }

    /// Entries whose name is `name` or Shortcuts' de-duplicated "`name` 2", "`name` 3"…
    public static func matching(_ name: String, in entries: [Entry]) -> [Entry] {
        entries.filter { e in
            e.name == name || (e.name.hasPrefix(name + " ") && Int(e.name.dropFirst(name.count + 1)) != nil)
        }
    }
}
