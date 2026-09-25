import Core
import Foundation
import IntentsIndex

/// Recipes checked on a real run. On the Mac, Shortcuts' own Reminders and Calendar actions are
/// built-ins, not App Intents (M0: a user-built reference shortcut, decoded with Spike/unwrap.sh),
/// and Notes' Create Note needs its older serialization.
public enum Catalog {
    public static let all: [Recipe] = [remindersAdd, calendarCreateEvent, notesCreate]

    public static func recipe(_ alias: String) -> Recipe? { all.first { $0.alias == alias } }

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
        verified: "M0 2026-09-25, macOS 27.0: title, notes, due as text (alert from input: checked in M2)",
        readBack: .reminder, version: 1,
        prepare: { args in
            var a = args
            let due = args["due"]?.stringValue ?? ""
            a["alert"] = .string(due.isEmpty ? "No Alert" : "Alert")
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
        verified: "M0 2026-09-25, macOS 27.0: title, start, end as text",
        readBack: .event, version: 1)

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
        verified: "M0 2026-09-25, macOS 27.0: contents via WFCreateNoteInput; output as text",
        readBack: nil, version: 1,
        prepare: { args in
            let title = args["title"]?.stringValue ?? ""
            let body = args["body"]?.stringValue ?? ""
            return ["contents": .string(body.isEmpty ? title : title + "\n" + body)]
        })

    /// A recipe generated from metadata for a simple-tier App Intent. Not checked live: parameter
    /// keys are the metadata names, which some actions ignore (M0). Read-back or the first run tells.
    public static func generated(from spec: ActionSpec) -> Recipe? {
        guard spec.tier == .simple else { return nil }
        let inputs: [RecipeInput] = spec.parameters.compactMap { p in
            let kind: InputKind
            switch p.kind {
            case .string, .attributedString, .url: kind = .text
            case .date, .dateComponents: kind = .date
            case .int, .double: kind = .number
            case .bool: kind = .bool
            case .enumeration(_, let cases): kind = .enumeration(cases)
            default: return nil
            }
            return RecipeInput(p.name, p.name, kind, required: !p.optional, description: p.description ?? p.title)
        }
        let bundle = String(spec.id.dropLast(spec.intentIdentifier.count + 1))
        return Recipe(
            alias: spec.alias, title: spec.title, summary: spec.description ?? spec.title, appName: spec.app.name,
            actionIdentifier: spec.id,
            descriptor: ["TeamIdentifier": spec.app.teamID ?? "0000000000", "BundleIdentifier": bundle,
                         "Name": spec.app.name, "AppIntentIdentifier": spec.intentIdentifier],
            inputs: inputs, risky: spec.risky, riskReasons: spec.riskReasons, verified: nil, version: 1)
    }
}
