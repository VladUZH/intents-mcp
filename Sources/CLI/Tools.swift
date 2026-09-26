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
        let i = Progress.run("Scanning App Intents metadata (about 10 s)…") {
            ActionIndex.scan(reserved: Catalog.reservedAliases)
        }
        cachedIndex = i
        return i
    }

    /// Catalog recipe, or one generated from the metadata (scans the Mac: about 10 s).
    static func recipeForEnable(_ key: String) throws -> (Recipe, ActionSpec?) {
        if let r = Catalog.recipe(key) { return (r, nil) }
        guard let spec = index.lookup(key) else { throw ToolError.unknown(key) }
        if let why = Catalog.refusal(for: spec) { throw ToolError.notSimple(spec.alias, [why]) }
        guard let r = Catalog.generated(from: spec) else { throw ToolError.notSimple(spec.alias, spec.tierReasons) }
        return (r, spec)
    }

    static func specURL(_ alias: String, _ version: Int) throws -> URL { try service.specURL(alias, version) }

    /// What to pass to `enable` to (re)install this entry: helpers are installed by the tool that uses
    /// them; generated tools by action id (an alias can shift to another action after an app update).
    static func enableKey(_ alias: String, actionID: String? = nil) -> String {
        ReadBackWrappers.kind(forAlias: alias).map(ReadBackWrappers.owner) ?? actionID ?? alias
    }

    /// Whether any enabled agent tool reads back through this helper.
    static func helperInUse(_ alias: String, among tools: [EnabledTool]) -> Bool {
        tools.contains { o in o.source != "helper" && (try? service.recipe(for: o))?.readBack.map(ReadBackWrappers.alias) == alias }
    }

    // MARK: enable

    enum InstallResult { case enabled, alreadyEnabled, pending, dryRun }

    /// `dryRun`: build the unsigned wrapper and stop (no signing, nothing opened, store untouched).
    /// Returns false if something stayed pending (the caller exits non-zero).
    static func enable(_ keys: [String], allowRisky: Bool, wait: Bool, dryRun: Bool = false) async throws -> Bool {
        guard !keys.isEmpty else { throw CLIError.usage("enable needs at least one action (alias or id)") }
        await service.adoptPendingAll()
        store.removeSignedWrappersOfAddedTools()
        var allDone = true
        for key in keys {
            let (r, spec) = try recipeForEnable(key)
            if r.risky && !allowRisky { throw ToolError.risky(r.alias, r.riskReasons) }
            let specData = try spec.map { try JSONEncoder.sorted.encode($0) }
            let result = try await install(alias: r.alias, version: r.version, shortcutName: r.shortcutName,
                                           data: WrapperBuilder.data(r), source: spec == nil ? "catalog" : "generated",
                                           actionID: spec?.id, specData: specData, allowRisky: allowRisky,
                                           wait: wait, dryRun: dryRun,
                                           note: r.verified == nil ? "generated from metadata and not checked on a real run yet" : nil)
            if result == .pending { allDone = false }
            // Results are read back through a helper shortcut (one per app, shared by its tools).
            if let kind = r.readBack {
                let h = try await install(alias: ReadBackWrappers.alias(kind), version: ReadBackWrappers.version(kind),
                                          shortcutName: ReadBackWrappers.shortcutName(kind), data: ReadBackWrappers.data(kind),
                                          source: "helper", actionID: nil, specData: nil, allowRisky: false, wait: wait,
                                          dryRun: dryRun,
                                          note: "read-back helper: finds the \(kind == .reminder ? "reminder" : "event") just created to confirm results; never exposed to agents")
                if h == .pending { allDone = false }
            }
        }
        if !dryRun {
            Out.line("Claude Code picks up the change in a running session; other clients (e.g. Codex) may need a restart.")
        }
        return allDone
    }

    static func install(alias: String, version: Int, shortcutName: String, data: Data, source: String, actionID: String?,
                        specData: Data?, allowRisky: Bool, wait: Bool, dryRun: Bool, note: String?) async throws -> InstallResult {
        let unsigned = try store.wrapperURL(alias: alias, version: version, signed: false)
        let signed = try store.wrapperURL(alias: alias, version: version, signed: true)
        if dryRun {
            try data.write(to: unsigned)
            Out.line("\(alias): dry run: unsigned wrapper at \(unsigned.path); not signed, not opened, not enabled")
            return .dryRun
        }
        guard let library = await Library.entries() else {
            // Without the library we can't tell what is already added; don't guess (and don't discard UUIDs).
            throw CLIError.failure("couldn't read your Shortcuts library (`shortcuts list` failed); try again")
        }
        let before = Library.matching(shortcutName, in: library)
        if let existing = try store.tools().first(where: { $0.alias == alias }), existing.version == version,
           existing.actionID == actionID, try sameSpec(alias: alias, version: version, specData) {
            // By UUID, not name: a shortcut the user renamed is still the same wrapper.
            if let uuid = existing.shortcutUUID, library.contains(where: { $0.uuid == uuid }) {
                store.removeSignedWrapper(alias: alias, version: version)
                Out.line("\(alias): already enabled (\(shortcutName))")
                return .alreadyEnabled
            }
            // Pending, and the user has since added exactly one new copy: adopt it instead of importing another.
            let fresh = before.filter { !(existing.staleUUIDs ?? []).contains($0.uuid) }
            if existing.shortcutUUID == nil, fresh.count == 1 {
                try store.update(alias) { $0.shortcutUUID = fresh[0].uuid }
                store.removeSignedWrapper(alias: alias, version: version)
                Out.line("\(alias): enabled (\(fresh[0].uuid)).")
                return .enabled
            }
        }
        try data.write(to: unsigned)
        Out.line("\(alias): signing the wrapper shortcut (uses your iCloud account; Apple receives a copy for validation)…")
        try Signer.sign(unsigned: unsigned, to: signed)
        let previous = try store.tools().first { $0.alias == alias }
        var tool = EnabledTool(alias: alias, source: source, actionID: actionID, version: version, shortcutName: shortcutName,
                               shortcutUUID: nil, enabledAt: Date(), allowRisky: allowRisky,
                               staleUUIDs: before.isEmpty ? nil : before.map(\.uuid))
        let opened = Shell.run("/usr/bin/open", [signed.path], timeout: 20)
        if opened?.status != 0, previous?.shortcutUUID != nil, previous?.version == version, previous?.actionID == actionID {
            // Keep the working record (and its schema); the user can retry when `open` works.
            Out.line("\(alias): couldn't open the new wrapper in Shortcuts; the current one stays in use. Run `intents-mcp enable \(enableKey(alias))` again later.")
            return .pending
        }
        // Only now, with the wrapper it describes about to be imported, record the action's schema.
        if let specData { try specData.write(to: specURL(alias, version)) }
        try store.upsert(tool)
        if opened?.status != 0 {
            Out.line("\(alias): couldn't open the wrapper in Shortcuts. Open this file yourself and click Add Shortcut; intents-mcp picks it up on the next `enable`, `doctor`, `serve` or call:\n  \(signed.path)")
            return .pending
        }
        Out.line("\(alias): Shortcuts is showing \"\(shortcutName)\". Click Add Shortcut.")
        if let note { Out.line("\(alias): note: \(note).") }
        guard wait else { Out.line("\(alias): pending (not waiting). After you click Add Shortcut, run `intents-mcp enable \(enableKey(alias))` to finish."); return .pending }
        guard let uuid = await waitForImport(name: shortcutName, known: Set(before.map(\.uuid)), seconds: 180) else {
            Out.line("\(alias): no new shortcut seen after 3 minutes; it stays pending. After you click Add Shortcut, run `intents-mcp enable \(enableKey(alias))` again to finish.")
            return .pending
        }
        tool.shortcutUUID = uuid
        try store.upsert(tool)
        // The signed file carries your Apple Account's signing identity; it isn't needed after import.
        try? FileManager.default.removeItem(at: signed)
        Out.line("\(alias): enabled (\(uuid)). If Shortcuts asks for permission on the first run, choose Always Allow.")
        // Name stale copies by the names they have now (Replace renames the old one to "… 2").
        let now = await Library.entries().map { Library.matching(shortcutName, in: $0) } ?? []
        for s in now where s.uuid != uuid {
            Out.line("\(alias): another copy \"\(s.name)\" (\(s.uuid)) is in Shortcuts. Unless intents-mcp on another Mac with your iCloud account uses it, delete it there (the CLI can't delete shortcuts). Keep \"\(now.first { $0.uuid == uuid }?.name ?? shortcutName)\".")
        }
        return .enabled
    }

    /// Whether the stored action.json describes the same action as a fresh scan.
    static func sameSpec(alias: String, version: Int, _ specData: Data?) throws -> Bool {
        guard let specData else { return true }
        guard let stored = FileManager.default.contents(atPath: try specURL(alias, version).path),
              let a = try? JSONDecoder().decode(ActionSpec.self, from: stored),
              let b = try? JSONDecoder().decode(ActionSpec.self, from: specData) else { return false }
        return a.id == b.id && a.parameters == b.parameters
    }

    static func waitForImport(name: String, known: Set<String>, seconds: Int) async -> String? {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if let found = await Library.entries().map({ Library.matching(name, in: $0) }),
               let new = found.first(where: { !known.contains($0.uuid) }) {
                return new.uuid
            }
            try? await Task.sleep(for: .milliseconds(1500))
        }
        return nil
    }

    // MARK: disable

    static func disable(_ keys: [String]) async throws {
        guard !keys.isEmpty else { throw CLIError.usage("disable needs at least one tool (alias or action id)") }
        var unknown: [String] = []
        let library = await Library.entries()
        for key in keys {
            let removed = try store.remove(key)
            guard !removed.isEmpty else { unknown.append(key); continue }
            for t in removed {
                try? FileManager.default.removeItem(at: store.wrappersDir.appendingPathComponent("\(t.alias).v\(t.version)"))
                Out.line("\(t.alias): disabled. Agents can no longer call it.")
                printCopies(t.shortcutName, uuid: t.shortcutUUID, library: library)
            }
        }
        // Retire read-back helpers that no remaining tool uses.
        let remaining = try store.tools()
        let needed = Set(remaining.compactMap { t -> String? in
            guard t.source != "helper" else { return nil }
            return (try? service.recipe(for: t))?.readBack.map { ReadBackWrappers.alias($0) }
        })
        for h in remaining where h.source == "helper" && !needed.contains(h.alias) {
            _ = try store.remove(h.alias)
            try? FileManager.default.removeItem(at: store.wrappersDir.appendingPathComponent("\(h.alias).v\(h.version)"))
            Out.line("\(h.alias): no enabled tool uses this read-back helper any more; removed it too.")
            printCopies(h.shortcutName, uuid: h.shortcutUUID, library: library)
        }
        if !unknown.isEmpty {
            throw CLIError.failure("no enabled tool matches \(unknown.map { "\"\($0)\"" }.joined(separator: ", ")); see `intents-mcp tools`")
        }
    }

    static func printCopies(_ name: String, uuid: String?, library: [Library.Entry]?) {
        let caveat = "(the CLI can't delete shortcuts; keep any copy that intents-mcp on another Mac with your iCloud account still uses)"
        guard let library else {
            Out.line("  Also delete \"\(name)\" in the Shortcuts app if it is there \(caveat).")
            return
        }
        // This Mac's copy by UUID, even if the user renamed it; then other same-named copies.
        if let mine = library.first(where: { $0.uuid == uuid }) {
            Out.line("  Delete this Mac's copy \"\(mine.name)\" in the Shortcuts app \(caveat).")
        }
        let others = Library.matching(name, in: library).filter { $0.uuid != uuid }
        if !others.isEmpty {
            Out.line("  Other copies with this name: \(others.map { "\"\($0.name)\"" }.joined(separator: ", ")) \(caveat).")
        }
        if uuid.map({ u in !library.contains { $0.uuid == u } }) ?? true, others.isEmpty {
            Out.line("  No copy was found in Shortcuts.")
        }
    }

    // MARK: call

    static func call(_ key: String, args: [String: JSONValue], caller: String, timeout: Int = 30, verify: Bool = true,
                     cancel: CancelToken? = nil) async -> CallReport {
        var svc = service
        svc.timeout = timeout
        return await svc.call(key, args: args, caller: caller, verify: verify, cancel: cancel)
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }
}
