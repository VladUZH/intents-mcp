import Core
import Foundation
import IntentsIndex

/// Recipes checked on a real run. On the Mac, Shortcuts' own Reminders and Calendar actions are
/// built-ins, not App Intents (M0: a user-built reference shortcut, decoded with Spike/unwrap.sh),
/// and Notes' Create Note needs its older serialization.
public enum Catalog {
    public static let all: [Recipe] = [remindersAdd, calendarCreateEvent, notesCreate]

    public static func recipe(_ alias: String) -> Recipe? { all.first { $0.alias == alias } }

    /// Metadata-generated actions that worked on a real run, keyed by action id (aliases can shift
    /// when an update adds or removes an action; ids can't).
    public static let checkedGenerated: [String: String] = [
        "com.apple.WritingTools.WritingToolsAppIntentsExtension.SummarizeTextIntent": "2026-09-25, macOS 27.0: returned a summary",
        "com.apple.WritingTools.WritingToolsAppIntentsExtension.ProofreadIntent": "2026-09-25, macOS 27.0: returned corrected text",
    ]

    /// Simple-tier actions that failed a real run, by action id, with what happened.
    public static let knownBroken: [String: String] = [
        "com.apple.Notes.CreateFolderLinkAction": "hangs until the timeout (2026-09-25, macOS 27.0): the action seems to ignore `name` and wait for input",
    ]

    /// Aliases a metadata action may not take: catalog tools and read-back helpers.
    public static var reservedAliases: Set<String> { Set(all.map(\.alias)).union(ReadBackWrappers.aliases) }

    /// Titles are trimmed so the item stored and the one read back match exactly.
    static func trimmed(_ v: JSONValue?) -> JSONValue? {
        guard case .string(let s)? = v else { return v }
        return .string(s.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static let remindersAdd = Recipe(
        alias: "reminders.add", title: "Add Reminder",
        summary: "Adds a reminder to the default Reminders list, with an optional due time.",
        appName: "Reminders", actionIdentifier: "is.workflow.actions.addnewreminder",
        inputs: [
            RecipeInput("title", "WFCalendarItemTitle", .text, required: true, description: "What to be reminded of."),
            RecipeInput("notes", "WFCalendarItemNotes", .text, description: "Extra text on the reminder."),
            RecipeInput("due", "WFAlertCustomTime", .date,
                        description: "When to remind, e.g. \"tomorrow at 10:00\" or \"2026-10-01 09:30\"."),
            RecipeInput("alert", "WFAlertEnabled", .enumeration(["Alert", "No Alert"]), exposed: false),
        ],
        fixed: ["WFAlertCondition": .string("At Time")],
        additive: true,
        verified: "2026-09-25, macOS 27.0: title, notes, due as text; no due → No Alert, read back as no due date",
        readBack: .reminder, version: 1,
        prepare: { args in
            var a = args
            a["title"] = trimmed(args["title"])
            let due = (args["due"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            a["alert"] = .string(due.isEmpty ? "No Alert" : "Alert")
            // Shortcuts converts the time text to a date before it looks at "No Alert", so an empty
            // value fails ("couldn't convert from Text to Date", M4 live run). With no alert the
            // time is a placeholder that the reminder does not get (checked by read-back).
            if due.isEmpty { a["due"] = "today" }
            return a
        })

    public static let calendarCreateEvent = Recipe(
        alias: "calendar.create-event", title: "Create Calendar Event",
        summary: "Creates an event in the default calendar. No invitees.",
        appName: "Calendar", actionIdentifier: "is.workflow.actions.addnewevent",
        inputs: [
            RecipeInput("title", "WFCalendarItemTitle", .text, required: true, description: "Event title."),
            RecipeInput("start", "WFCalendarItemStartDate", .date, required: true,
                        description: "Start, e.g. \"tomorrow at 12:00\" or \"2026-10-01 09:30\"."),
            RecipeInput("end", "WFCalendarItemEndDate", .date, required: true, description: "End, same format."),
            RecipeInput("location", "WFCalendarItemLocation", .text, description: "Where."),
            RecipeInput("notes", "WFCalendarItemNotes", .text, description: "Extra text on the event."),
        ],
        fixed: ["ShowWhenRun": .bool(false)],
        additive: true,
        verified: "M0 2026-09-25, macOS 27.0: title, start, end as text",
        readBack: .event, version: 1,
        prepare: { args in
            var a = args
            a["title"] = trimmed(args["title"])
            return a
        })

    public static let notesCreate = Recipe(
        alias: "notes.create", title: "Create Note",
        summary: "Creates a note in the default Notes folder. The first line is the title.",
        appName: "Notes", actionIdentifier: "com.apple.mobilenotes.SharingExtension",
        descriptor: ["TeamIdentifier": "0000000000", "BundleIdentifier": "com.apple.Notes", "Name": "Notes",
                     "AppIntentIdentifier": "CreateNoteLinkAction"],
        inputs: [
            RecipeInput("title", "", .text, required: true, description: "Note title (its first line).", exposed: true),
            RecipeInput("body", "", .text, description: "Note text under the title."),
            RecipeInput("contents", "WFCreateNoteInput", .text, exposed: false),
        ],
        fixed: ["interpretAsMarkdown": .bool(false), "OpenWhenRun": .bool(false)],
        additive: true,
        verified: "M0 2026-09-25, macOS 27.0: contents via WFCreateNoteInput; output as text",
        readBack: nil, version: 1,
        prepare: { args in
            let title = (args["title"]?.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let body = args["body"]?.stringValue ?? ""
            return ["contents": .string(body.isEmpty ? title : title + "\n" + body)]
        })

    /// Why a simple-tier action can't become a tool, or nil if it can.
    public static func refusal(for spec: ActionSpec) -> String? {
        if let why = knownBroken[spec.id] { return "known not to work: \(why)" }
        if spec.tier != .simple { return spec.tierReasons.joined(separator: "; ") }
        if reservedAliases.contains(spec.alias) { return "its alias \"\(spec.alias)\" is reserved" }
        // The descriptor needs the real Team ID; guessing Apple's makes Shortcuts refuse the import.
        if spec.app.teamID == nil { return "its code signature has no Team ID" }
        // Only required inputs can be wired; an action whose inputs are all optional would run with
        // none and may wait for input until the timeout (like Notes' Create Folder).
        if !spec.parameters.isEmpty && spec.parameters.allSatisfy(\.optional) {
            return "its inputs are all optional, which isn't supported yet"
        }
        return nil
    }

    /// A recipe generated from metadata for a simple-tier App Intent. Parameter keys are the metadata
    /// names, which some actions ignore (M0), so it counts as unverified until a real run; see
    /// `checkedGenerated`. Only required parameters are wired: the wrapper can't leave a wired
    /// parameter unset, and an omitted optional one would be sent as empty text.
    public static func generated(from spec: ActionSpec) -> Recipe? {
        guard refusal(for: spec) == nil, let teamID = spec.app.teamID else { return nil }
        let inputs: [RecipeInput] = spec.parameters.filter { !$0.optional }.compactMap { p in
            let kind: InputKind
            switch p.kind {
            case .string, .attributedString, .url: kind = .text
            case .date, .dateComponents: kind = .date
            case .int: kind = .integer
            case .double: kind = .number
            case .bool: kind = .bool
            case .enumeration(_, let cases): kind = .enumeration(cases)
            default: return nil
            }
            return RecipeInput(p.name, p.name, kind, required: true, description: p.description ?? p.title)
        }
        let bundle = String(spec.id.dropLast(spec.intentIdentifier.count + 1))
        return Recipe(
            alias: spec.alias, title: spec.title, summary: spec.description ?? spec.title, appName: spec.app.shownName,
            actionIdentifier: spec.id,
            descriptor: ["TeamIdentifier": teamID, "BundleIdentifier": bundle,
                         "Name": spec.app.name, "AppIntentIdentifier": spec.intentIdentifier],
            inputs: inputs, risky: spec.risky, riskReasons: spec.riskReasons, verified: checkedGenerated[spec.id],
            // v2: only required parameters are wired (v1 wrappers bound every optional one too).
            version: 2)
    }
}
