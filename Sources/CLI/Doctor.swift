import Foundation
import Core
import IntentsIndex
import Runner
import ShortcutForge
import Store

enum Doctor {
    struct Check: Encodable {
        var name: String
        var status: String  // ok, warn, fail, info
        var detail: String
    }

    /// `report` sees each check as soon as it is done, so the terminal shows progress line by line.
    static func checks(_ report: (Check) -> Void = { _ in }) async -> [Check] {
        var out: [Check] = []
        func add(_ c: Check) {
            out.append(c)
            report(c)
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let vs = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        add(Check(name: "macOS", status: v.majorVersion >= 26 ? "ok" : "fail",
                         detail: v.majorVersion >= 27 ? "\(vs) (tested)" : v.majorVersion >= 26 ? "\(vs) (supported, not tested yet)" : "\(vs): needs macOS 26 or later"))

        let shortcuts = "/usr/bin/shortcuts"
        if let help = Shell.run(shortcuts, ["help"]) {
            let text = help.stdout + help.stderr
            let hasSign = text.contains("sign")
            add(Check(name: "shortcuts CLI", status: hasSign ? "ok" : "fail",
                             detail: hasSign ? "\(shortcuts) with run, list, sign" : "\(shortcuts) has no `sign` subcommand"))
        } else {
            add(Check(name: "shortcuts CLI", status: "fail", detail: "\(shortcuts) not found"))
        }
        if let l = Shell.run(shortcuts, ["list"]) {
            if l.timedOut {
                add(Check(name: "Shortcuts library", status: "fail", detail: "`shortcuts list` timed out"))
            } else {
                let n = l.stdout.split(separator: "\n").count
                add(Check(name: "Shortcuts library", status: l.status == 0 ? "ok" : "fail",
                                 detail: l.status == 0 ? "\(n) shortcuts readable" : l.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        add(Check(name: "iCloud", status: "info",
                         detail: "signing a shortcut needs an iCloud login, and Apple receives a copy for validation; checked when you first enable a tool"))

        let files = Progress.run("Looking for App Intents metadata (about 10 s)…") { ActionIndex.findMetadataFiles() }
        add(Check(name: "App Intents metadata", status: files.isEmpty ? "fail" : "ok",
                         detail: "\(files.count) metadata files (run `intents-mcp census`)"))

        let store = Tools.store.root  // honours INTENTS_MCP_HOME
        add(Check(name: "local store", status: "info",
                         detail: FileManager.default.fileExists(atPath: store.path) ? store.path : "\(store.path) (created on first enable)"))
        // The call log must be writable, or calls would run unlogged.
        let logDir = Tools.store.root.path
        if FileManager.default.fileExists(atPath: Tools.store.logFile.path) {
            let ok = FileManager.default.isWritableFile(atPath: Tools.store.logFile.path)
            add(Check(name: "call log", status: ok ? "ok" : "fail",
                             detail: ok ? Tools.store.logFile.path : "\(Tools.store.logFile.path) is not writable: calls can't be logged"))
        } else if FileManager.default.fileExists(atPath: logDir), !FileManager.default.isWritableFile(atPath: logDir) {
            add(Check(name: "call log", status: "fail", detail: "\(logDir) is not writable: calls can't be logged"))
        }
        await Tools.service.adoptPendingAll()
        Tools.store.removeSignedWrappersOfAddedTools()
        let tools: [EnabledTool]
        do {
            tools = try Tools.store.tools()
        } catch {
            add(Check(name: "tools.json", status: "fail",
                             detail: "can't be read (\(error)); `serve` exposes no tools until it is fixed or removed"))
            return out
        }
        if tools.isEmpty {
            add(Check(name: "tools enabled", status: "info", detail: "none yet (`intents-mcp enable reminders.add`)"))
            return out
        }
        guard let library = await Library.entries() else {
            add(Check(name: "tools enabled", status: "warn",
                             detail: "\(tools.count) enabled, but the Shortcuts library couldn't be read to check them"))
            return out
        }
        for t in tools {
            let copies = Library.matching(t.shortcutName, in: library)
            // Helpers are installed by the tool that uses them, not by their own alias.
            let enableKey = Tools.enableKey(t.alias, actionID: t.actionID)
            let present = t.shortcutUUID.map { u in library.contains { $0.uuid == u } } ?? false
            var status = present ? "ok" : "warn"
            var detail = present ? "\(t.shortcutName) in Shortcuts"
                : t.shortcutUUID == nil ? "pending: click Add Shortcut, then run `intents-mcp enable \(enableKey)`"
                : "its shortcut is missing from Shortcuts: run `intents-mcp enable \(enableKey)`"
            if t.source == "generated" || t.source == "catalog" {
                do {
                    let r = try Tools.service.recipe(for: t)
                    if r.version != t.version {
                        status = "warn"
                        detail = "its wrapper is from an older intents-mcp: run `intents-mcp enable \(enableKey)` to update it"
                    }
                } catch {
                    status = "warn"
                    detail = "not offered to agents any more: \(error)"
                }
            }
            let usedBy = tools.contains { o in
                o.source != "helper" && (try? Tools.service.recipe(for: o))?.readBack.map(ReadBackWrappers.alias) == t.alias
            }
            if ReadBackWrappers.kind(forAlias: t.alias) != nil, !usedBy {
                status = "warn"
                detail = "no enabled tool uses this read-back helper: run `intents-mcp disable \(t.alias)` and delete its shortcut"
            } else if let k = ReadBackWrappers.kind(forAlias: t.alias), t.version != ReadBackWrappers.version(k) {
                status = "warn"
                detail = "this read-back helper is from an older intents-mcp, so results aren't verified: run `intents-mcp enable \(enableKey)`"
            }
            let extra = copies.filter { $0.uuid != t.shortcutUUID }
            if present, !extra.isEmpty {
                status = "warn"
                detail += "; other copies: " + extra.map { "\"\($0.name)\"" }.joined(separator: ", ")
                    + " (delete them unless intents-mcp on another Mac with your iCloud account uses them)"
            }
            add(Check(name: "tool \(t.alias)", status: status, detail: detail))
        }
        return out
    }

    static func run(json: Bool) async -> Int32 {
        let cs: [Check]
        if json {
            cs = await checks()
            printJSON(cs)
        } else {
            // Each line prints as its check finishes; the name column is sized up front.
            let names = ((try? Tools.store.tools()) ?? []).map { "tool \($0.alias)" } + ["App Intents metadata"]
            let width = names.map(\.count).max()!
            cs = await checks { c in
                let mark: String = switch c.status {
                case "ok": Style.green("✓")
                case "warn": Style.yellow("!")
                case "fail": Style.red("✗")
                case "info": Style.dim("·")
                default: "?"
                }
                let detail = c.status == "info" ? Style.dim(c.detail) : Style.commands(c.detail)
                Out.line("\(mark) \(c.name.padding(toLength: width, withPad: " ", startingAt: 0)) \(detail)")
            }
        }
        return cs.contains { $0.status == "fail" } ? 1 : 0
    }
}
