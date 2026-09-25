import Core
@preconcurrency import EventKit
import Foundation
import ShortcutForge

/// Result of reading an action's effect back through a public API.
public struct Verification: Sendable, Equatable {
    /// true: found as expected; false: not found; nil: no read access or nothing to check.
    public var verified: Bool?
    /// What was found (e.g. the resolved due date), for the agent. Titles are the agent's own input.
    public var detail: String
}

/// Reads Reminders and Calendar back with EventKit after a call. Asks the user for access the first
/// time (macOS shows the prompt); without access the result is reported as unverified.
public enum Verifier {
    /// Read-back through the Shortcuts helper (see ReadBackWrappers); EventKit only when the host
    /// app already has full access (asking would fail silently under most agent hosts).
    public static func verify(_ kind: ShortcutForge.ReadBack?, args: [String: JSONValue], since start: Date,
                              helperUUID: String?) async -> Verification {
        guard let kind else { return Verification(verified: nil, detail: "no read action for this tool") }
        let title = args["title"]?.stringValue ?? ""
        let type: EKEntityType = kind == .reminder ? .reminder : .event
        if EKEventStore.authorizationStatus(for: type) == .fullAccess {
            return await verifyWithEventKit(kind, title: title, since: start)
        }
        guard let helperUUID else {
            return Verification(verified: nil, detail: "not verified: read-back helper \"\(ReadBackWrappers.shortcutName(kind))\" is not enabled")
        }
        do {
            var input: URL?
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("intents-mcp-rb-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: dir) }
            if ReadBackWrappers.takesTitle(kind) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                input = dir.appendingPathComponent("input.json")
                try JSONEncoder().encode(["title": title]).write(to: input!)
            }
            let out = try Runner.runShortcut(uuid: helperUUID, input: input, alias: ReadBackWrappers.alias(kind), timeout: 20)
            guard let (found, date) = ReadBackWrappers.parse(out.text) else {
                return Verification(verified: false, detail: "read-back returned an unexpected shape")
            }
            // Never echo another item's title: it may be personal content unrelated to this call.
            guard found == title else {
                return Verification(verified: false, detail: "the newest \(kind == .reminder ? "reminder" : "event") is not the one just created")
            }
            let what = kind == .reminder ? (date.isEmpty ? "no due date" : "due \(date)") : "starts \(date)"
            return Verification(verified: true, detail: "read back through Shortcuts: \(what)")
        } catch {
            return Verification(verified: nil, detail: "not verified: read-back failed (\(error))")
        }
    }

    static func verifyWithEventKit(_ kind: ShortcutForge.ReadBack, title: String, since start: Date) async -> Verification {
        let store = EKEventStore()
        let since = start.addingTimeInterval(-5)
        switch kind {
        case .reminder:
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            let found: [(String, String?)] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: predicate) { reminders in
                    let hits = (reminders ?? []).filter { $0.title == title && ($0.creationDate ?? .distantPast) >= since }
                    cont.resume(returning: hits.map { r in
                        (r.calendar.title, r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map(format))
                    })
                }
            }
            guard let hit = found.first else {
                return Verification(verified: false, detail: "no new reminder titled \"\(title)\" found")
            }
            return Verification(verified: true, detail: "reminder in list \"\(hit.0)\"" + (hit.1.map { ", due \($0)" } ?? ", no due date"))
        case .event:
            let now = Date()
            let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-86_400 * 7),
                                                     end: now.addingTimeInterval(86_400 * 365 * 3), calendars: nil)
            let hits = store.events(matching: predicate).filter { $0.title == title && ($0.creationDate ?? .distantPast) >= since }
            guard let e = hits.first else {
                return Verification(verified: false, detail: "no new event titled \"\(title)\" found")
            }
            return Verification(verified: true, detail: "event in calendar \"\(e.calendar.title)\", \(format(e.startDate)) – \(format(e.endDate))")
        }
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}
