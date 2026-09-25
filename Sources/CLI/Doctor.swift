import Foundation
import IntentsIndex

/// Runs a tool with stdin from /dev/null (an inherited stdin hangs `shortcuts`) and a timeout.
enum Shell {
    struct Result {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool
    }

    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 20) -> Result? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        // Read while waiting so a full pipe can't block the child.
        let outData = LockedData(), errData = LockedData()
        let g = DispatchGroup()
        for (h, box) in [(out.fileHandleForReading, outData), (err.fileHandleForReading, errData)] {
            g.enter()
            DispatchQueue.global().async { box.set(h.readDataToEndOfFile()); g.leave() }
        }
        while p.isRunning && Date() < deadline { usleep(20_000) }
        let timedOut = p.isRunning
        if timedOut { p.terminate() }
        p.waitUntilExit()
        g.wait()
        return Result(status: p.terminationStatus, stdout: String(decoding: outData.get(), as: UTF8.self),
                      stderr: String(decoding: errData.get(), as: UTF8.self), timedOut: timedOut)
    }

    final class LockedData: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}

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
        out.append(Check(name: "tools enabled", status: "info", detail: "none yet (enable arrives in M2)"))
        return out
    }

    static func run(json: Bool) -> Int32 {
        let cs = checks()
        if json {
            printJSON(cs)
        } else {
            for c in cs {
                let mark = ["ok": "✓", "warn": "!", "fail": "✗", "info": "·"][c.status] ?? "?"
                print("\(mark) \(c.name.padding(toLength: 22, withPad: " ", startingAt: 0)) \(c.detail)")
            }
        }
        return cs.contains { $0.status == "fail" } ? 1 : 0
    }
}
