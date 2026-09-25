import Core
import Foundation
import IntentsIndex

/// How one agent tool maps onto one Shortcuts action: what the wrapper shortcut contains and
/// which arguments the tool takes. Metadata keys can't be trusted blindly (M0: Notes' Create Note
/// ignores its `contents` key), so the catalog below holds recipes checked on a real run.
public struct Recipe: Sendable {
    public var alias: String
    public var title: String
    public var summary: String
    public var appName: String
    /// `WFWorkflowActionIdentifier`: a built-in (`is.workflow.actions.…`) or "<bundle>.<intent>".
    public var actionIdentifier: String
    /// `AppIntentDescriptor` for App Intents actions; nil for built-ins.
    public var descriptor: [String: String]?
    public var inputs: [RecipeInput]
    public var fixed: [String: FixedValue]
    /// The action's output, returned as text; nil returns "OK".
    public var returnsOutput: Bool
    public var risky: Bool
    public var riskReasons: [String]
    /// What was checked live, and where. nil = generated from metadata, not yet checked.
    public var verified: String?
    public var readBack: ReadBack?
    /// Bump when the wrapper's content changes; a new version needs a new import.
    public var version: Int
    /// Turns tool arguments into the wrapper's input JSON (derived keys, defaults).
    public var prepare: @Sendable ([String: JSONValue]) -> [String: JSONValue]

    public init(alias: String, title: String, summary: String, appName: String, actionIdentifier: String,
                descriptor: [String: String]? = nil, inputs: [RecipeInput], fixed: [String: FixedValue] = [:],
                returnsOutput: Bool = true, risky: Bool = false, riskReasons: [String] = [], verified: String?,
                readBack: ReadBack? = nil, version: Int = 1,
                prepare: @escaping @Sendable ([String: JSONValue]) -> [String: JSONValue] = { $0 }) {
        self.alias = alias
        self.title = title
        self.summary = summary
        self.appName = appName
        self.actionIdentifier = actionIdentifier
        self.descriptor = descriptor
        self.inputs = inputs
        self.fixed = fixed
        self.returnsOutput = returnsOutput
        self.risky = risky
        self.riskReasons = riskReasons
        self.verified = verified
        self.readBack = readBack
        self.version = version
        self.prepare = prepare
    }

    /// The shortcut's name in the user's library (it comes from the file name on import).
    public var shortcutName: String { "intents-mcp \(alias)" }

    public var exposedInputs: [RecipeInput] { inputs.filter(\.exposed) }
}

public struct RecipeInput: Sendable, Equatable {
    /// Argument name for the agent, and the key in the wrapper's input JSON.
    public var name: String
    /// Parameter key inside the action.
    public var plistKey: String
    public var kind: InputKind
    public var required: Bool
    public var description: String
    /// false for values the recipe derives itself (see `Recipe.prepare`).
    public var exposed: Bool

    public init(_ name: String, _ plistKey: String, _ kind: InputKind, required: Bool = false,
                description: String = "", exposed: Bool = true) {
        self.name = name
        self.plistKey = plistKey
        self.kind = kind
        self.required = required
        self.description = description
        self.exposed = exposed
    }
}

public enum InputKind: Sendable, Equatable {
    /// Text; dates are text too and Shortcuts parses them ("tomorrow at 10:00" works, M0).
    case text, date
    case number, bool
    case enumeration([String])

    /// Text-like values go through Get Text and a token string; numbers, booleans and enums are
    /// attached as-is (a token string is rejected for numbers: tech-notes §3.3).
    var tokenString: Bool {
        switch self {
        case .text, .date: return true
        default: return false
        }
    }
}

public enum FixedValue: Sendable, Equatable {
    case string(String), bool(Bool), int(Int)

    var plist: Any {
        switch self {
        case .string(let s): return s
        case .bool(let b): return b
        case .int(let i): return i
        }
    }
}

/// How to confirm an action's effect afterwards through a public read API.
public enum ReadBack: String, Sendable {
    case reminder, event
}
