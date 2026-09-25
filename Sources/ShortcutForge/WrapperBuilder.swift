import CryptoKit
import Foundation

/// Builds the unsigned wrapper shortcut for a recipe. The design is the one proven in M0
/// (Spike/forge.py):
///   Shortcut Input (a JSON file) → Get Dictionary → per key: Get Value, and Get Text for
///   text-like values → the action → Get Text of its result → Stop and Output.
public enum WrapperBuilder {
    public static func plist(_ r: Recipe) -> [String: Any] {
        var actions: [[String: Any]] = []
        func uid(_ label: String) -> String {
            let d = Array(SHA256.hash(data: Data("intents-mcp/\(r.alias)/v\(r.version)/\(label)".utf8)))
            return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], (d[6] & 0x0F) | 0x50, d[7],
                               (d[8] & 0x3F) | 0x80, d[9], d[10], d[11], d[12], d[13], d[14], d[15])).uuidString
        }
        func add(_ identifier: String, _ label: String, _ params: [String: Any]) {
            var p = params
            p["UUID"] = uid(label)
            actions.append(["WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": p])
        }
        func output(_ label: String, _ name: String) -> [String: Any] {
            attachment(["Type": "ActionOutput", "OutputUUID": uid(label), "OutputName": name])
        }

        let wired = r.inputs.filter { !$0.plistKey.isEmpty }
        if !wired.isEmpty {
            add("is.workflow.actions.detect.dictionary", "request", ["WFInput": attachment(["Type": "ExtensionInput"])])
        }
        var actionParams: [String: Any] = r.fixed.mapValues(\.plist)
        for input in wired {
            add("is.workflow.actions.getvalueforkey", "key-\(input.name)",
                ["WFInput": output("request", "Dictionary"), "WFDictionaryKey": input.name,
                 "WFGetDictionaryValueType": "Value"])
            if input.kind.tokenString {
                // A Dictionary Value is an untyped content item; Get Text makes it text (sweetrb, M0).
                add("is.workflow.actions.gettext", "text-\(input.name)",
                    ["WFTextActionText": tokenString(output("key-\(input.name)", "Dictionary Value"))])
                actionParams[input.plistKey] = tokenString(output("text-\(input.name)", "Text"))
            } else {
                actionParams[input.plistKey] = output("key-\(input.name)", "Dictionary Value")
            }
        }
        if let d = r.descriptor { actionParams["AppIntentDescriptor"] = d }
        add(r.actionIdentifier, "action", actionParams)
        // An entity sent straight to Stop and Output gave no output in M0; Get Text first.
        add("is.workflow.actions.gettext", "result",
            ["WFTextActionText": r.returnsOutput ? tokenString(output("action", "Result")) : "OK"])
        add("is.workflow.actions.output", "output", ["WFOutput": tokenString(output("result", "Text"))])

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

    /// Binary plist: the signer sometimes rejects XML (tech-notes §3.4).
    public static func data(_ r: Recipe) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: plist(r), format: .binary, options: 0)
    }

    static func attachment(_ value: [String: Any]) -> [String: Any] {
        ["Value": value, "WFSerializationType": "WFTextTokenAttachment"]
    }

    static func tokenString(_ att: [String: Any]) -> [String: Any] {
        ["WFSerializationType": "WFTextTokenString",
         "Value": ["string": "\u{FFFC}", "attachmentsByRange": ["{0, 1}": att["Value"]!]]]
    }
}
