import Foundation
import Core
import IntentsIndex
import Runner

enum Doctor {
    struct Check: Encodable {
        var name: String
        var status: String  // ok, warn, fail, info
        var detail: String
    }

    static func checks() -> [Check] {
        var out: [Check] = []
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let vs = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        out.append(Check(name: "macOS", status: v.majorVersion >= 26 ? "ok" : "fail",
                         detail: v.majorVersion >= 27 ? "\(vs) (tested)" : v.majorVersion >= 26 ? "\(vs) (supported, not tested yet)" : "\(vs): needs macOS 26 or later"))

        let shortcuts = "/usr/bin/shortcuts"
        if let help = Shell.run(shortcuts, ["help"]) {
            let text = help.stdout + help.stderr
            let hasSign = text.contains("sign")
            out.append(Check(name: "shortcuts CLI", status: hasSign ? "ok" : "fail",
                             detail: hasSign ? "\(shortcuts) with run, list, sign" : "\(shortcuts) has no `sign` subcommand"))
        } else {
            out.append(Check(name: "shortcuts CLI", status: "fail", detail: "\(shortcuts) not found"))
        }
        if let l = Shell.run(shortcuts, ["list"]) {
            if l.timedOut {
                out.append(Check(name: "Shortcuts library", status: "fail", detail: "`shortcuts list` timed out"))
            } else {
                let n = l.stdout.split(separator: "\n").count
                out.append(Check(name: "Shortcuts library", status: l.status == 0 ? "ok" : "fail",
                                 detail: l.status == 0 ? "\(n) shortcuts readable" : l.stderr.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        out.append(Check(name: "iCloud", status: "info",
                         detail: "signing a shortcut needs an iCloud login, and Apple receives a copy for validation; checked when you first enable a tool"))

        let files = ActionIndex.findMetadataFiles()
        out.append(Check(name: "App Intents metadata", status: files.isEmpty ? "fail" : "ok",
                         detail: "\(files.count) metadata files (run `intents-mcp census`)"))

        let store = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("intents-mcp")
        out.append(Check(name: "local store", status: "info",
                         detail: FileManager.default.fileExists(atPath: store.path) ? store.path : "\(store.path) (created on first enable)"))
        let tools = (try? Tools.store.tools()) ?? []
        if tools.isEmpty {
            out.append(Check(name: "tools enabled", status: "info", detail: "none yet (`intents-mcp enable reminders.add`)"))
        } else {
            let library = Library.entries() ?? []
            for t in tools {
                let present = t.shortcutUUID.map { u in library.contains { $0.uuid == u } } ?? false
                out.append(Check(name: "tool \(t.alias)", status: present ? "ok" : "warn",
                                 detail: present ? "\(t.shortcutName) in Shortcuts"
                                     : t.shortcutUUID == nil ? "pending: click Add Shortcut (or `intents-mcp enable \(t.alias)`)"
                                     : "its shortcut is missing from Shortcuts: run `intents-mcp enable \(t.alias)`"))
            }
        }
        return out
    }

    static func run(json: Bool) -> Int32 {
        let cs = checks()
        if json {
            printJSON(cs)
        } else {
            let width = min(48, cs.map(\.name.count).max() ?? 22)
            for c in cs {
                let mark = ["ok": "✓", "warn": "!", "fail": "✗", "info": "·"][c.status] ?? "?"
                print("\(mark) \(c.name.padding(toLength: width, withPad: " ", startingAt: 0)) \(c.detail)")
            }
        }
        return cs.contains { $0.status == "fail" } ? 1 : 0
    }
}
