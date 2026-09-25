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
    public static func verify(_ kind: ShortcutForge.ReadBack?, args: [String: JSONValue], since start: Date) async -> Verification {
        guard let kind else { return Verification(verified: nil, detail: "no read action for this tool") }
        let title = args["title"]?.stringValue ?? ""
        let store = EKEventStore()
        let since = start.addingTimeInterval(-5)
        switch kind {
        case .reminder:
            guard await access(store, .reminder) else { return noAccess("Reminders") }
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
            guard await access(store, .event) else { return noAccess("Calendar") }
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

    static func access(_ store: EKEventStore, _ type: EKEntityType) async -> Bool {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return true
        case .notDetermined:
            let granted = try? await (type == .reminder ? store.requestFullAccessToReminders() : store.requestFullAccessToEvents())
            return granted ?? false
        default: return false
        }
    }

    static func noAccess(_ app: String) -> Verification {
        Verification(verified: nil, detail: "not verified: no read access to \(app) (System Settings › Privacy & Security › \(app))")
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}
