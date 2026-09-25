import CryptoKit
import Foundation

/// Read-back helpers: small wrappers that read the newest reminder or event through Shortcuts,
/// which already has access to them. EventKit from the MCP server is not reliable: macOS attributes
/// the request to the app hosting the agent (VS Code, a terminal, Claude Desktop…), which may have no
/// usage string and then denies silently (M2, 2026-09-25).
///
/// No filter is used: Find filters silently degraded in M0. The helper returns the single newest
/// item (by creation date); the caller compares its title exactly, so a wrong item can only produce
/// "not verified", never a false "verified".
public enum ReadBackWrappers {
    /// v2 (reminders): sort-only returned an unrelated reminder on macOS 27, so it filters by the
    /// title passed in. Events keep v1 (sort-only worked).
    public static func version(_ kind: ReadBack) -> Int { kind == .reminder ? 2 : 1 }
    public static func takesTitle(_ kind: ReadBack) -> Bool { kind == .reminder }

    public static func shortcutName(_ kind: ReadBack) -> String {
        "intents-mcp verify.\(kind == .reminder ? "reminders" : "calendar")"
    }

    public static func alias(_ kind: ReadBack) -> String {
        kind == .reminder ? "verify.reminders" : "verify.calendar"
    }

    /// Output: "<title>\n<separator>\n<date>" (due date, or start date for events).
    public static let separator = "--intents-mcp--"

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
        var findParams: [String: Any] = [
            "UUID": uid("find"),
            "WFContentItemSortProperty": "Creation Date",
            "WFContentItemSortOrder": "Latest First",
            "WFContentItemLimitEnabled": true,
            "WFContentItemLimitNumber": 1,
        ]
        var head: [[String: Any]] = []
        if takesTitle(kind) {
            head = [
                ["WFWorkflowActionIdentifier": "is.workflow.actions.detect.dictionary", "WFWorkflowActionParameters": [
                    "UUID": uid("request"),
                    "WFInput": ["Value": ["Type": "ExtensionInput"], "WFSerializationType": "WFTextTokenAttachment"]]],
                ["WFWorkflowActionIdentifier": "is.workflow.actions.getvalueforkey", "WFWorkflowActionParameters": [
                    "UUID": uid("key-title"), "WFDictionaryKey": "title", "WFGetDictionaryValueType": "Value",
                    "WFInput": ["Value": ref("request", "Dictionary"), "WFSerializationType": "WFTextTokenAttachment"]]],
                ["WFWorkflowActionIdentifier": "is.workflow.actions.gettext", "WFWorkflowActionParameters": [
                    "UUID": uid("title"),
                    "WFTextActionText": ["WFSerializationType": "WFTextTokenString", "Value": [
                        "string": "\u{FFFC}", "attachmentsByRange": ["{0, 1}": ref("key-title", "Dictionary Value")]]]]],
            ]
            // Same table-template shape as Apple's own gallery workflow (ActionItems.wflow).
            findParams["WFContentItemFilter"] = ["WFSerializationType": "WFContentPredicateTableTemplate", "Value": [
                "WFActionParameterFilterPrefix": 1, "WFContentPredicateBoundedDate": false,
                "WFActionParameterFilterTemplates": [[
                    "Property": "Title", "Operator": 4, "Removable": true,
                    "Values": ["Unit": 4, "String": ["WFSerializationType": "WFTextTokenString", "Value": [
                        "string": "\u{FFFC}", "attachmentsByRange": ["{0, 1}": ref("title", "Text")]]]],
                ]],
            ]]
        }
        let actions: [[String: Any]] = head + [
            ["WFWorkflowActionIdentifier": find, "WFWorkflowActionParameters": findParams],
            ["WFWorkflowActionIdentifier": props, "WFWorkflowActionParameters": [
                "UUID": uid("date"),
                "WFContentItemPropertyName": dateProp,
                "WFInput": ["Value": ref("find", name), "WFSerializationType": "WFTextTokenAttachment"],
            ]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.gettext", "WFWorkflowActionParameters": [
                "UUID": uid("text"),
                "WFTextActionText": ["WFSerializationType": "WFTextTokenString", "Value": [
                    "string": "\u{FFFC}\n\(separator)\n\u{FFFC}",
                    "attachmentsByRange": ["{0, 1}": ref("find", name),
                                           "{\(2 + separator.utf16.count + 1), 1}": ref("date", dateProp)],
                ]],
            ]],
            ["WFWorkflowActionIdentifier": "is.workflow.actions.output", "WFWorkflowActionParameters": [
                "UUID": uid("out"),
                "WFOutput": ["WFSerializationType": "WFTextTokenString", "Value": [
                    "string": "\u{FFFC}", "attachmentsByRange": ["{0, 1}": ref("text", "Text")]]],
            ]],
        ]
        return [
            "WFWorkflowActions": actions,
            "WFWorkflowClientVersion": "2600",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowTypes": [String](),
            "WFWorkflowImportQuestions": [Any](),
            "WFQuickActionSurfaces": [Any](),
            "WFWorkflowHasShortcutInputVariables": takesTitle(kind),
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

    /// Parses the helper's output. nil if it isn't in the expected shape.
    public static func parse(_ text: String) -> (title: String, date: String)? {
        let parts = text.components(separatedBy: "\n\(separator)\n")
        guard parts.count == 2 else {
            // A missing date leaves the separator last.
            if text.hasSuffix("\n\(separator)") { return (String(text.dropLast(separator.count + 1)), "") }
            return nil
        }
        return (parts[0], parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
