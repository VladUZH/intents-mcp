import CryptoKit
import Foundation

/// Read-back helpers: small wrappers that read an item back through Shortcuts, which already has
/// access to Reminders and Calendar. EventKit from the MCP server is not reliable: macOS attributes
/// the request to the app hosting the agent (VS Code, a terminal, Claude Desktop…), which may have no
/// usage string and then denies silently (M2, 2026-09-25).
///
/// Each helper takes `{"title": …}`, finds items with exactly that title (newest first, limit 1), and
/// returns the title, the due/start date, and the **creation date** as ISO 8601. The caller counts a
/// result as verified only if the title matches and the item was created during the call, so an
/// older item with the same title can never pass (bug hunt, 2026-09-26).
public enum ReadBackWrappers {
    /// v1/v2 had no creation date; the event helper also had no title filter.
    public static func version(_ kind: ReadBack) -> Int { kind == .reminder ? 3 : 2 }
    public static func takesTitle(_ kind: ReadBack) -> Bool { true }

    public static func shortcutName(_ kind: ReadBack) -> String {
        "intents-mcp verify.\(kind == .reminder ? "reminders" : "calendar")"
    }

    public static func alias(_ kind: ReadBack) -> String {
        kind == .reminder ? "verify.reminders" : "verify.calendar"
    }

    public static let aliases: Set<String> = ["verify.reminders", "verify.calendar"]

    /// The tool whose `enable` installs this helper (helpers can't be enabled by their own alias).
    public static func owner(_ kind: ReadBack) -> String {
        kind == .reminder ? "reminders.add" : "calendar.create-event"
    }

    public static func kind(forAlias alias: String) -> ReadBack? {
        alias == "verify.reminders" ? .reminder : alias == "verify.calendar" ? .event : nil
    }

    /// Field markers. Output: "<title>\n<marker>D:<date>\n<marker>C:<created ISO 8601>".
    /// Parsed from the end, so a title containing anything (even these markers) can't confuse it.
    public static let marker = "--intents-mcp--"
    static var dateField: String { "\n\(marker)D:" }
    static var createdField: String { "\n\(marker)C:" }

    public static func plist(_ kind: ReadBack) -> [String: Any] {
        let (find, props, name, dateProp) = kind == .reminder
            ? ("is.workflow.actions.filter.reminders", "is.workflow.actions.properties.reminders", "Reminders", "Due Date")
            : ("is.workflow.actions.filter.calendarevents", "is.workflow.actions.properties.calendarevents", "Calendar Events", "Start Date")
        func uid(_ label: String) -> String {
            let d = Array(SHA256.hash(data: Data("intents-mcp/\(alias(kind))/v\(version(kind))/\(label)".utf8)))
            return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], (d[6] & 0x0F) | 0x50, d[7],
                               (d[8] & 0x3F) | 0x80, d[9], d[10], d[11], d[12], d[13], d[14], d[15])).uuidString
        }
        func ref(_ label: String, _ output: String) -> [String: Any] {
            ["Type": "ActionOutput", "OutputUUID": uid(label), "OutputName": output]
        }
        func token(_ att: [String: Any]) -> [String: Any] {
            ["WFSerializationType": "WFTextTokenString", "Value": ["string": "\u{FFFC}", "attachmentsByRange": ["{0, 1}": att]]]
        }
        let text = "\u{FFFC}\(dateField)\u{FFFC}\(createdField)\u{FFFC}"
        let dateAt = 1 + dateField.utf16.count
        let createdAt = dateAt + 1 + createdField.utf16.count
        let actions: [[String: Any]] = [
            ["WFWorkflowActionIdentifier": "is.workflow.actions.detect.dictionary", "WFWorkflowActionParameters": [
                "UUID": uid("request"),
                "WFInput": ["Value": ["Type": "ExtensionInput"], "WFSerializationType": "WFTextTokenAttachment"]]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey", "WFWorkflowActionParameters": [
                "UUID": uid("key-title"), "WFDictionaryKey": "title", "WFGetDictionaryValueType": "Value",
                "WFInput": ["Value": ref("request", "Dictionary"), "WFSerializationType": "WFTextTokenAttachment"]]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.gettext", "WFWorkflowActionParameters": [
                "UUID": uid("title"), "WFTextActionText": token(ref("key-title", "Dictionary Value"))]],
            ["WFWorkflowActionIdentifier": find, "WFWorkflowActionParameters": [
                "UUID": uid("find"),
                "WFContentItemSortProperty": "Creation Date",
                "WFContentItemSortOrder": "Latest First",
                "WFContentItemLimitEnabled": true,
                "WFContentItemLimitNumber": 1,
                // Same table-template shape as Apple's own gallery workflow (ActionItems.wflow).
                "WFContentItemFilter": ["WFSerializationType": "WFContentPredicateTableTemplate", "Value": [
                    "WFActionParameterFilterPrefix": 1, "WFContentPredicateBoundedDate": false,
                    "WFActionParameterFilterTemplates": [[
                        "Property": "Title", "Operator": 4, "Removable": true,
                        "Values": ["Unit": 4, "String": token(ref("title", "Text"))],
                    ]],
                ]],
            ]],
            ["WFWorkflowActionIdentifier": props, "WFWorkflowActionParameters": [
                "UUID": uid("date"), "WFContentItemPropertyName": dateProp,
                "WFInput": ["Value": ref("find", name), "WFSerializationType": "WFTextTokenAttachment"]]],
            ["WFWorkflowActionIdentifier": props, "WFWorkflowActionParameters": [
                "UUID": uid("created"), "WFContentItemPropertyName": "Creation Date",
                "WFInput": ["Value": ref("find", name), "WFSerializationType": "WFTextTokenAttachment"]]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.format.date", "WFWorkflowActionParameters": [
                "UUID": uid("created-iso"), "WFDateFormatStyle": "ISO 8601", "WFISO8601IncludeTime": true,
                "WFDate": token(ref("created", "Creation Date"))]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.gettext", "WFWorkflowActionParameters": [
                "UUID": uid("text"),
                "WFTextActionText": ["WFSerializationType": "WFTextTokenString", "Value": [
                    "string": text,
                    "attachmentsByRange": ["{0, 1}": ref("find", name),
                                           "{\(dateAt), 1}": ref("date", dateProp),
                                           "{\(createdAt), 1}": ref("created-iso", "Formatted Date")],
                ]],
            ]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.output", "WFWorkflowActionParameters": [
                "UUID": uid("out"), "WFOutput": token(ref("text", "Text"))]],
        ]
        return [
            "WFWorkflowActions": actions,
            "WFWorkflowClientVersion": "2600",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowTypes": [String](),
            "WFWorkflowImportQuestions": [Any](),
            "WFQuickActionSurfaces": [Any](),
            "WFWorkflowHasShortcutInputVariables": true,
            "WFWorkflowHasOutputFallback": false,
            "WFWorkflowHasOutputAction": true,
            "WFWorkflowInputContentItemClasses": ["WFStringContentItem", "WFDictionaryContentItem", "WFGenericFileContentItem"],
            "WFWorkflowOutputContentItemClasses": ["WFStringContentItem"],
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 61440],
        ]
    }

    public static func data(_ kind: ReadBack) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist(kind), format: .binary, options: 0)
    }

    public struct Parsed: Sendable, Equatable {
        /// "" when nothing was found.
        public var title: String
        public var date: String
        public var created: String
    }

    /// Parses the helper's raw output (not trimmed). nil if the markers are missing.
    public static func parse(_ raw: String) -> Parsed? {
        var ns = raw as NSString
        // Drop one trailing line break the output file may end with (by UTF-16, so "\r\n" is safe).
        while ns.length > 0, [10, 13].contains(ns.character(at: ns.length - 1)) {
            ns = ns.substring(to: ns.length - 1) as NSString
        }
        // A title-less result starts with the marker line itself.
        let text = (ns as String).hasPrefix(String(dateField.dropFirst())) ? "\n" + (ns as String) : (ns as String)
        let t = text as NSString
        let c = t.range(of: createdField, options: [.backwards, .literal])
        guard c.location != NSNotFound else { return nil }
        let head = t.substring(to: c.location) as NSString
        let d = head.range(of: dateField, options: [.backwards, .literal])
        guard d.location != NSNotFound else { return nil }
        return Parsed(title: head.substring(to: d.location),
                      date: head.substring(from: d.location + d.length).trimmingCharacters(in: .whitespacesAndNewlines),
                      created: t.substring(from: c.location + c.length).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
