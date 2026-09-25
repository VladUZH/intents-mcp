import Core
import Foundation
import IntentsIndex
import Runner
import ShortcutForge
import Store

enum ToolError: Error, CustomStringConvertible {
    case unknown(String)
    case notSimple(String, [String])
    case risky(String, [String])
    case notEnabled(String)
    case pending(String)

    var description: String {
        switch self {
        case .unknown(let a): return "no action named \"\(a)\" (see `intents-mcp list`)"
        case .notSimple(let a, let why):
            return "\(a) is not in the simple tier yet: \(why.joined(separator: "; "))"
        case .risky(let a, let why):
            return "\(a) looks risky (\(why.joined(separator: ", "))); enable it with --allow-risky if you are sure"
        case .notEnabled(let a): return "\(a) is not enabled; run `intents-mcp enable \(a)` first"
        case .pending(let a):
            return "\(a) is waiting for its shortcut: click Add Shortcut in Shortcuts, or run `intents-mcp enable \(a)` again"
        }
    }
}

enum Tools {
    static let store = Store()

    /// One scan per command (about 10 s).
    nonisolated(unsafe) static var cachedIndex: ActionIndex?
    static var index: ActionIndex {
        if let i = cachedIndex { return i }
        FileHandle.standardError.write(Data("scanning App Intents metadata…\n".utf8))
        let i = ActionIndex.scan()
        cachedIndex = i
        return i
    }

    /// Catalog recipe, or one generated from the metadata (scans the Mac: about 10 s).
    static func recipeForEnable(_ key: String) throws -> (Recipe, ActionSpec?) {
        if let r = Catalog.recipe(key) { return (r, nil) }
        guard let spec = index.lookup(key) else { throw ToolError.unknown(key) }
        guard let r = Catalog.generated(from: spec) else { throw ToolError.notSimple(spec.alias, spec.tierReasons) }
        return (r, spec)
    }

    /// The recipe for an enabled tool, without rescanning (generated specs are saved at enable time).
    static func recipe(for tool: EnabledTool) throws -> Recipe {
        if tool.source == "catalog", let r = Catalog.recipe(tool.alias) { return r }
        let url = try specURL(tool.alias, tool.version)
        let spec = try JSONDecoder().decode(ActionSpec.self, from: Data(contentsOf: url))
        guard let r = Catalog.generated(from: spec) else { throw ToolError.notSimple(tool.alias, spec.tierReasons) }
        return r
    }

    static func specURL(_ alias: String, _ version: Int) throws -> URL {
        try store.wrapperURL(alias: alias, version: version, signed: true).deletingLastPathComponent()
            .appendingPathComponent("action.json")
    }

    // MARK: enable

    /// `dryRun`: build the unsigned wrapper and stop (no signing, nothing opened, store untouched).
    static func enable(_ keys: [String], allowRisky: Bool, wait: Bool, dryRun: Bool = false) throws {
        guard !keys.isEmpty else { throw CLIError.usage("enable needs at least one action (alias or id)") }
        for key in keys {
            let (r, spec) = try recipeForEnable(key)
            if r.risky && !allowRisky { throw ToolError.risky(r.alias, r.riskReasons) }

            let unsigned = try store.wrapperURL(alias: r.alias, version: r.version, signed: false)
            let signed = try store.wrapperURL(alias: r.alias, version: r.version, signed: true)
            try WrapperBuilder.data(r).write(to: unsigned)
            if let spec { try JSONEncoder().encode(spec).write(to: specURL(r.alias, r.version)) }
            if dryRun {
                print("\(r.alias): dry run: unsigned wrapper at \(unsigned.path); not signed, not opened, not enabled")
                continue
            }
            print("\(r.alias): signing the wrapper shortcut (uses your iCloud account; Apple receives a copy for validation)…")
            try Signer.sign(unsigned: unsigned, to: signed)

            let before = Library.entries().map { Library.matching(r.shortcutName, in: $0) } ?? []
            if let existing = try store.tools().first(where: { $0.alias == r.alias }), existing.version == r.version,
               let uuid = existing.shortcutUUID, before.contains(where: { $0.uuid == uuid }) {
                print("\(r.alias): already enabled (\(r.shortcutName))")
                continue
            }
            var tool = EnabledTool(alias: r.alias, source: spec == nil ? "catalog" : "generated", actionID: spec?.id,
                                   version: r.version, shortcutName: r.shortcutName, shortcutUUID: nil,
                                   enabledAt: Date(), allowRisky: allowRisky)
            try store.upsert(tool)
            _ = Shell.run("/usr/bin/open", [signed.path], timeout: 20)
            print("\(r.alias): Shortcuts is showing \"\(r.shortcutName)\". Click Add Shortcut.")
            if r.verified == nil {
                print("\(r.alias): note: generated from metadata and not checked on a real run yet.")
            }
            guard wait else { print("\(r.alias): pending (not waiting)."); continue }
            if let uuid = waitForImport(name: r.shortcutName, known: Set(before.map(\.uuid)), seconds: 180) {
                tool.shortcutUUID = uuid
                try store.upsert(tool)
                print("\(r.alias): enabled (\(uuid)). The first call asks for permission in Shortcuts: choose Always Allow.")
                if !before.isEmpty {
                    print("\(r.alias): an older \"\(r.shortcutName)\" is still in Shortcuts; delete it there (the CLI can't delete shortcuts).")
                }
            } else {
                print("\(r.alias): no new shortcut seen after 3 minutes; it stays pending. Run `intents-mcp enable \(r.alias)` again to retry.")
            }
        }
    }

    static func waitForImport(name: String, known: Set<String>, seconds: Int) -> String? {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if let found = Library.entries().map({ Library.matching(name, in: $0) }),
               let new = found.first(where: { !known.contains($0.uuid) }) {
                return new.uuid
            }
            Thread.sleep(forTimeInterval: 1.5)
        }
        return nil
    }

    // MARK: disable

    static func disable(_ keys: [String]) throws {
        guard !keys.isEmpty else { throw CLIError.usage("disable needs at least one tool") }
        for key in keys {
            guard let t = try store.remove(key) else { print("\(key): not enabled"); continue }
            try? FileManager.default.removeItem(at: store.wrappersDir.appendingPathComponent("\(t.alias).v\(t.version)"))
            print("\(t.alias): disabled. Agents can no longer call it. Also delete \"\(t.shortcutName)\" in the Shortcuts app (the CLI can't delete shortcuts).")
        }
    }

    // MARK: call

    struct CallReport: Encodable {
        var tool: String
        var ok: Bool
        var output: String?
        var error: String?
        var verified: Bool?
        var detail: String?
        var durationMs: Int
    }

    /// Runs one enabled tool, reads the result back where possible, and logs the call.
    static func call(_ alias: String, args: [String: JSONValue], caller: String, timeout: Int = 30, verify: Bool = true) async -> CallReport {
        let started = Date()
        var report = CallReport(tool: alias, ok: false, durationMs: 0)
        var category: String?
        do {
            guard var tool = try store.tools().first(where: { $0.alias == alias }) else { throw ToolError.notEnabled(alias) }
            let r = try recipe(for: tool)
            if tool.shortcutUUID == nil {
                // Pending since enable: adopt the shortcut if exactly one with this name exists.
                let found = Library.entries().map { Library.matching(tool.shortcutName, in: $0) } ?? []
                guard found.count == 1 else { throw ToolError.pending(alias) }
                tool.shortcutUUID = found[0].uuid
                try store.upsert(tool)
            }
            let out = try Runner.call(r, uuid: tool.shortcutUUID!, args: args, timeout: timeout)
            report.ok = true
            report.output = out.text
            if verify {
                let v = await Verifier.verify(r.readBack, args: args, since: started)
                report.verified = v.verified
                report.detail = v.detail
            }
        } catch let e as CallError {
            report.error = e.description
            category = e.category
        } catch {
            report.error = "\(error)"
            category = "setup"
        }
        report.durationMs = Int(Date().timeIntervalSince(started) * 1000)
        try? store.append(LogEntry(tool: alias, time: started, durationMs: report.durationMs, ok: report.ok,
                                   verified: report.verified, error: category, caller: caller))
        return report
    }
}
