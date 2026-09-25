import Foundation

/// One App Intents action as declared in an `extract.actionsdata` file.
public struct ActionSpec: Codable, Sendable, Equatable {
    /// Stable: "<declaring bundle ID>.<intentIdentifier>". `app` is the app users see.
    public var id: String
    /// Short, human-friendly name for the CLI: "notes.create-note".
    public var alias: String
    /// The key a shortcut uses (`AppIntentIdentifier`).
    public var intentIdentifier: String
    public var app: AppRef
    /// Where the metadata was found (the declaring bundle, which may be a framework).
    public var source: SourceRef
    public var title: String
    public var description: String?
    public var parameters: [ParamSpec]
    public var outputType: String?
    public var supportedModes: [String]
    public var discoverable: Bool
    public var opensApp: Bool
    public var systemProtocols: [String]
    /// Deletes, sends, purchases or shares (protocol or name heuristic). Off unless explicitly allowed.
    public var risky: Bool
    public var riskReasons: [String]
    public var tier: Tier
    /// Why the action is not in the simple tier (empty when it is).
    public var tierReasons: [String]
}

public struct AppRef: Codable, Sendable, Equatable, Hashable {
    public var name: String
    public var bundleID: String
    public var version: String?
    public var path: String
    /// "0000000000" for Apple platform binaries; nil when unsigned or unknown.
    public var teamID: String?
}

public struct SourceRef: Codable, Sendable, Equatable {
    public var bundleID: String
    public var path: String
    /// How `app` was chosen: attribution, container, framework-name, self.
    public var hostMapping: String
}

public struct ParamSpec: Codable, Sendable, Equatable {
    /// The key used in the shortcut plist (for App Intents; see STATUS: not always honoured).
    public var name: String
    public var title: String
    public var description: String?
    public var optional: Bool
    public var kind: ParamKind
}

public enum ParamKind: Codable, Sendable, Equatable {
    case string, attributedString, bool, int, double, date, dateComponents, url, location
    case enumeration(id: String, cases: [String])
    case entity(String)
    case array(ParamKindBox)
    case file
    case other(String)

    /// Primitive or enum: can be passed as a plain JSON value through a wrapper.
    public var isSimple: Bool {
        switch self {
        case .string, .attributedString, .bool, .int, .double, .date, .dateComponents, .url, .enumeration: return true
        default: return false
        }
    }

    public var needsEntity: Bool {
        switch self {
        case .entity: return true
        case .array(let box): return box.kind.needsEntity
        default: return false
        }
    }

    public var label: String {
        switch self {
        case .string: return "string"
        case .attributedString: return "text"
        case .bool: return "bool"
        case .int: return "int"
        case .double: return "number"
        case .date: return "date"
        case .dateComponents: return "date-components"
        case .url: return "url"
        case .location: return "location"
        case .enumeration(let id, _): return "enum:\(id)"
        case .entity(let t): return "entity:\(t)"
        case .array(let box): return "[\(box.kind.label)]"
        case .file: return "file"
        case .other(let k): return "other:\(k)"
        }
    }
}

/// Indirection so `ParamKind` can nest (arrays of kinds) and stay Codable.
public final class ParamKindBox: Codable, Sendable, Equatable {
    public let kind: ParamKind
    public init(_ kind: ParamKind) { self.kind = kind }
    public static func == (a: ParamKindBox, b: ParamKindBox) -> Bool { a.kind == b.kind }
}

public enum Tier: String, Codable, Sendable, CaseIterable {
    /// Discoverable, runs in the background, primitive or enum parameters only, returns output.
    case simple
    /// Takes an entity or an array of entities (a note, a reminder). Not supported in v1.
    case needsEntity = "entity"
    /// Everything else (hidden, opens the app, no output, files, locations …).
    case unsupported
}
