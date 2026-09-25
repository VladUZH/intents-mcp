import Core
import Foundation
import IntentsIndex
import MCPServer
import Runner
import ShortcutForge
import Store

enum Tools {
    static let store = Store()
    static let service = ToolService(store: store)

    /// One scan per command (about 10 s).
    nonisolated(unsafe) static var cachedIndex: ActionIndex?
    static var index: ActionIndex {
        if let i = cachedIndex { return i }
        let i = Progress.run("Scanning App Intents metadata (about 10 s)…") { ActionIndex.scan() }
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

    static func specURL(_ alias: String, _ version: Int) throws -> URL { try service.specURL(alias, version) }

    // MARK: enable

    /// `dryRun`: build the unsigned wrapper and stop (no signing, nothing opened, store untouched).
    static func enable(_ keys: [String], allowRisky: Bool, wait: Bool, dryRun: Bool = false) throws {
        guard !keys.isEmpty else { throw CLIError.usage("enable needs at least one action (alias or id)") }
        for key in keys {
            let (r, spec) = try recipeForEnable(key)
            if r.risky && !allowRisky { throw ToolError.risky(r.alias, r.riskReasons) }
            if let spec { try? FileManager.default.createDirectory(at: specURL(r.alias, r.version).deletingLastPathComponent(), withIntermediateDirectories: true)
                          try JSONEncoder().encode(spec).write(to: specURL(r.alias, r.version)) }
            try install(alias: r.alias, version: r.version, shortcutName: r.shortcutName, data: WrapperBuilder.data(r),
                        source: spec == nil ? "catalog" : "generated", actionID: spec?.id, allowRisky: allowRisky,
                        wait: wait, dryRun: dryRun, note: r.verified == nil ? "generated from metadata and not checked on a real run yet" : nil)
            // Results are read back through a helper shortcut (one per app, shared by its tools).
            if let kind = r.readBack {
                try install(alias: ReadBackWrappers.alias(kind), version: ReadBackWrappers.version(kind),
                            shortcutName: ReadBackWrappers.shortcutName(kind), data: ReadBackWrappers.data(kind),
                            source: "helper", actionID: nil, allowRisky: false, wait: wait, dryRun: dryRun,
                            note: "read-back helper: reads the newest \(kind == .reminder ? "reminder" : "event") to confirm results; never exposed to agents")
            }
        }
    }

    static func install(alias: String, version: Int, shortcutName: String, data: Data, source: String, actionID: String?,
                        allowRisky: Bool, wait: Bool, dryRun: Bool, note: String?) throws {
        let unsigned = try store.wrapperURL(alias: alias, version: version, signed: false)
        let signed = try store.wrapperURL(alias: alias, version: version, signed: true)
        try data.write(to: unsigned)
        if dryRun {
            print("\(alias): dry run: unsigned wrapper at \(unsigned.path); not signed, not opened, not enabled")
            return
        }
        let before = Library.entries().map { Library.matching(shortcutName, in: $0) } ?? []
        if let existing = try store.tools().first(where: { $0.alias == alias }), existing.version == version,
           let uuid = existing.shortcutUUID, before.contains(where: { $0.uuid == uuid }) {
            print("\(alias): already enabled (\(shortcutName))")
            return
        }
        print("\(alias): signing the wrapper shortcut (uses your iCloud account; Apple receives a copy for validation)…")
        try Signer.sign(unsigned: unsigned, to: signed)
        var tool = EnabledTool(alias: alias, source: source, actionID: actionID, version: version, shortcutName: shortcutName,
                               shortcutUUID: nil, enabledAt: Date(), allowRisky: allowRisky)
        try store.upsert(tool)
        _ = Shell.run("/usr/bin/open", [signed.path], timeout: 20)
        print("\(alias): Shortcuts is showing \"\(shortcutName)\". Click Add Shortcut.")
        if let note { print("\(alias): note: \(note).") }
        guard wait else { print("\(alias): pending (not waiting)."); return }
        if let uuid = waitForImport(name: shortcutName, known: Set(before.map(\.uuid)), seconds: 180) {
            tool.shortcutUUID = uuid
            try store.upsert(tool)
            print("\(alias): enabled (\(uuid)). The first run asks for permission in Shortcuts: choose Always Allow.")
            if !before.isEmpty {
                print("\(alias): an older \"\(shortcutName)\" is still in Shortcuts; delete it there (the CLI can't delete shortcuts).")
            }
        } else {
            print("\(alias): no new shortcut seen after 3 minutes; it stays pending. Run `intents-mcp enable` again to retry.")
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

    static func call(_ alias: String, args: [String: JSONValue], caller: String, timeout: Int = 30, verify: Bool = true) async -> CallReport {
        var svc = service
        svc.timeout = timeout
        return await svc.call(alias, args: args, caller: caller, verify: verify)
    }
}
