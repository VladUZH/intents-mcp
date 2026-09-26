import Core
@preconcurrency import EventKit
import Foundation
import ShortcutForge

/// Result of reading an action's effect back through a public API.
public struct Verification: Sendable, Equatable {
    /// true: found the item created by this call; false: it isn't there; nil: couldn't check.
    public var verified: Bool?
    /// What was found (e.g. the resolved due date), for the agent. Titles are the agent's own input.
    public var detail: String
}

/// Reads Reminders and Calendar back after a call.
public enum Verifier {
    /// Read-back through the Shortcuts helper (see ReadBackWrappers); EventKit only when the host
    /// app already has full access (asking would fail silently under most agent hosts).
    ///
    /// A result counts as verified only if the title matches exactly AND the item was created during
    /// this call (creation date ≥ run start − 1 s, the ISO seconds' rounding): an older item with the same
    /// title never passes. Same-kind calls are serialized with a gap (ReadBackGate), so the previous
    /// call's item is always older than that.
    public static func verify(_ kind: ShortcutForge.ReadBack?, args: [String: JSONValue], since start: Date,
                              helperUUID: String?, timeout: Int = 20, cancel: CancelToken? = nil) async -> Verification {
        guard let kind else { return Verification(verified: nil, detail: "no read action for this tool") }
        let title = (args["title"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let type: EKEntityType = kind == .reminder ? .reminder : .event
        if EKEventStore.authorizationStatus(for: type) == .fullAccess {
            return await verifyWithEventKit(kind, title: title, since: start)
        }
        guard let helperUUID else {
            return Verification(verified: nil, detail: "not verified: read-back helper \"\(ReadBackWrappers.shortcutName(kind))\" is not added yet (`intents-mcp enable \(ReadBackWrappers.owner(kind))` offers it)")
        }
        do {
            let dir = try TempDir.make("intents-mcp-rb-")
            defer { TempDir.remove(dir) }
            let input = dir.appendingPathComponent("input.json")
            try JSONEncoder().encode(["title": title]).write(to: input)
            let out = try await Runner.runShortcut(uuid: helperUUID, input: input, alias: ReadBackWrappers.owner(kind),
                                                   timeout: timeout, cancel: cancel)
            return judge(ReadBackWrappers.parse(out.text), kind: kind, title: title, since: start)
        } catch {
            return Verification(verified: nil, detail: "not verified: read-back failed (\(error))")
        }
    }

    /// The decision, separate so it can be tested without running shortcuts.
    public static func judge(_ parsed: ReadBackWrappers.Parsed?, kind: ShortcutForge.ReadBack, title: String,
                             since start: Date) -> Verification {
        let noun = kind == .reminder ? "reminder" : "event"
        guard let p = parsed else {
            return Verification(verified: nil, detail: "not verified: the read-back helper returned something unexpected")
        }
        let found = p.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if found.isEmpty {
            return Verification(verified: false, detail: "no \(noun) titled \"\(title)\" was found")
        }
        // Never echo another item's title: it may be personal content unrelated to this call.
        guard found == title else {
            return Verification(verified: false, detail: "the \(noun) found is not the one just created")
        }
        guard let created = parseDate(p.created) else {
            return Verification(verified: nil, detail: "not verified: found a \(noun) with this title but couldn't read when it was created")
        }
        guard created >= start.addingTimeInterval(-1) else {
            return Verification(verified: false, detail: "only an older \(noun) with this title exists; no new one was created")
        }
        let what = kind == .reminder ? (p.date.isEmpty ? "no due date" : "due \(p.date)") : "starts \(p.date)"
        return Verification(verified: true, detail: "read back through Shortcuts: \(what)")
    }

    /// ISO 8601 from the helper's Format Date step; locale text as a fallback.
    static func parseDate(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        for opts: ISO8601DateFormatter.Options in [[.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds]] {
            f.formatOptions = opts
            if let d = f.date(from: t) { return d }
        }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        return detector?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t))?.date
    }

    static func verifyWithEventKit(_ kind: ShortcutForge.ReadBack, title: String, since start: Date) async -> Verification {
        let store = EKEventStore()
        let since = start.addingTimeInterval(-1)
        switch kind {
        case .reminder:
            let predicate = store.predicateForReminders(in: nil)
            let found: [(String, String?)] = await withCheckedContinuation { cont in
                store.fetchReminders(matching: predicate) { reminders in
                    let hits = (reminders ?? []).filter { $0.title == title && ($0.creationDate ?? .distantPast) >= since }
                        .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                    cont.resume(returning: hits.map { r in
                        (r.calendar.title, r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map(format))
                    })
                }
            }
            guard let hit = found.first else {
                return Verification(verified: false, detail: "no new reminder titled \"\(title)\" found")
            }
            // No list or calendar names: they go to the agent's model provider and aren't the agent's input.
            return Verification(verified: true, detail: "read back: " + (hit.1.map { "due \($0)" } ?? "no due date"))
        case .event:
            // predicateForEvents spans at most 4 years: search 1 year back and 11 years ahead in slices.
            let now = Date()
            let year: TimeInterval = 86_400 * 365
            var hits: [EKEvent] = []
            var from = now.addingTimeInterval(-year)
            while from < now.addingTimeInterval(11 * year), hits.isEmpty {
                let to = from.addingTimeInterval(3 * year)
                hits = store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
                    .filter { $0.title == title && ($0.creationDate ?? .distantPast) >= since }
                    .sorted { ($0.creationDate ?? .distantPast) > ($1.creationDate ?? .distantPast) }
                from = to
            }
            guard let e = hits.first else {
                return Verification(verified: false, detail: "no new event titled \"\(title)\" found")
            }
            return Verification(verified: true, detail: "read back: starts \(format(e.startDate)), ends \(format(e.endDate))")
        }
    }

    static func format(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: d)
    }
}
