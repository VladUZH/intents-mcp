import Foundation

/// An action as read from one metadata file, before host-app mapping and classification.
public struct RawAction: Sendable {
    public var identifier: String
    public var fullyQualifiedTypeName: String?
    public var title: String
    public var description: String?
    public var parameters: [ParamSpec]
    public var outputType: String?
    public var supportedModes: Int?
    public var openAppWhenRun: Bool?
    public var discoverable: Bool
    public var systemProtocols: [String]
    public var attributionBundleID: String?
    /// false when the metadata marks the action unavailable on macOS (obsoleted, or introduced later).
    public var availableOnMac: Bool = true
}

public enum MetadataError: Error, CustomStringConvertible {
    case notJSON(String)
    public var description: String {
        switch self {
        case .notJSON(let p): return "not a metadata JSON object: \(p)"
        }
    }
}

/// Parses `extract.actionsdata` (single-line JSON written by Xcode's App Intents tooling).
/// Field meanings and the integer codes are documented in docs/tech-notes.md §1.2; the codes are
/// undocumented by Apple and were mapped from parameter titles on a macOS 27 Mac.
public struct MetadataParser {
    public var localizer: Localizer

    public init(localizer: Localizer = Localizer()) {
        self.localizer = localizer
    }

    /// `resources` is the bundle's Resources directory, used to resolve `.loctable` titles.
    public func parse(data: Data, resources: URL?, path: String = "<data>") throws -> [RawAction] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MetadataError.notJSON(path)
        }
        var enumCases: [String: [String]] = [:]
        for e in root["enums"] as? [[String: Any]] ?? [] {
            guard let id = e["identifier"] as? String else { continue }
            enumCases[id] = (e["cases"] as? [[String: Any]] ?? []).compactMap { $0["identifier"] as? String }
        }
        let actions = root["actions"] as? [String: Any] ?? [:]
        return actions.keys.sorted().compactMap { key in
            guard let a = actions[key] as? [String: Any] else { return nil }
            return action(key: key, a, enumCases: enumCases, resources: resources)
        }
    }

    func action(key: String, _ a: [String: Any], enumCases: [String: [String]], resources: URL?) -> RawAction {
        let identifier = a["identifier"] as? String ?? key
        let title = text(a["title"], resources: resources) ?? Self.humanize(identifier)
        let descMeta = a["descriptionMetadata"] as? [String: Any]
        let description = text(descMeta?["descriptionText"], resources: resources)
        let params: [ParamSpec] = (a["parameters"] as? [[String: Any]] ?? []).map { p in
            let name = p["name"] as? String ?? "?"
            return ParamSpec(
                name: name,
                title: text(p["title"], resources: resources) ?? name,
                description: text(p["parameterDescription"], resources: resources),
                optional: p["isOptional"] as? Bool ?? false,
                kind: Self.kind(p["valueType"], enumCases: enumCases))
        }
        let output = a["outputType"].map { Self.kind($0, enumCases: enumCases).label }
        let visibility = a["visibilityMetadata"] as? [String: Any]
        let discoverable = (a["isDiscoverable"] as? Bool) ?? (visibility?["isDiscoverable"] as? Bool) ?? true
        return RawAction(
            identifier: identifier,
            fullyQualifiedTypeName: a["fullyQualifiedTypeName"] as? String,
            title: title,
            description: description,
            parameters: params,
            outputType: output,
            supportedModes: (a["supportedModes"] as? NSNumber)?.intValue,
            openAppWhenRun: a["openAppWhenRun"] as? Bool,
            discoverable: discoverable,
            systemProtocols: a["systemProtocols"] as? [String] ?? [],
            attributionBundleID: a["attributionBundleIdentifier"] as? String,
            availableOnMac: Self.availableOnMac(a["availabilityAnnotations"]))
    }

    /// `@available(macOS, unavailable)` is encoded as `"LNPlatformNameMACOS": {"obsoletedVersion": "*"}`.
    static func availableOnMac(_ v: Any?, running: [Int] = {
        let o = ProcessInfo.processInfo.operatingSystemVersion
        return [o.majorVersion, o.minorVersion, o.patchVersion]
    }()) -> Bool {
        guard let all = v as? [String: Any] else { return true }
        let mac = all.first { $0.key.lowercased() == "lnplatformnamemacos" }?.value as? [String: Any]
        guard let mac else { return true }
        func parts(_ s: String) -> [Int]? {
            let p = s.split(separator: ".").map { Int($0) }
            return p.contains(nil) || p.isEmpty ? nil : p.compactMap { $0 }
        }
        func less(_ a: [Int], _ b: [Int]) -> Bool {  // a < b, missing parts count as 0
            for i in 0..<max(a.count, b.count) {
                let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
                if x != y { return x < y }
            }
            return false
        }
        if (mac["unavailable"] as? Bool) == true { return false }
        if let obs = mac["obsoletedVersion"] as? String {
            if obs == "*" { return false }
            if let o = parts(obs), !less(running, o) { return false }  // obsoleted at or before this OS
        }
        if let intro = mac["introducedVersion"] as? String, let i = parts(intro), less(running, i) { return false }
        return true
    }

    /// A localized-string object: `{key, table?, defaultValue?, alternatives}`.
    func text(_ v: Any?, resources: URL?) -> String? {
        guard let o = v as? [String: Any], let key = o["key"] as? String, !key.isEmpty else { return nil }
        if let resources, let s = localizer.english(key: key, table: o["table"] as? String, resources: resources) {
            return s
        }
        if let d = o["defaultValue"] as? String, !d.isEmpty { return d }
        return key
    }

    /// Fallback title for actions without one: "CRLCreateBoardIntent" → "CRL Create Board".
    static func humanize(_ id: String) -> String {
        var s = id
        for suffix in ["AppIntent", "LinkAction", "Intent", "Action"] where s.hasSuffix(suffix) && s.count > suffix.count {
            s = String(s.dropLast(suffix.count))
            break
        }
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            let prev = i > 0 ? chars[i - 1] : nil
            let next = i + 1 < chars.count ? chars[i + 1] : nil
            if i > 0, c.isUppercase, prev?.isLowercase == true || (prev?.isUppercase == true && next?.isLowercase == true) {
                out.append(" ")
            }
            out.append(c)
        }
        return out
    }

    /// `valueType` is a one-key object; see tech-notes §1.2.
    static func kind(_ v: Any?, enumCases: [String: [String]]) -> ParamKind {
        guard let o = v as? [String: Any], let (k, body) = o.first else { return .other("missing") }
        let w = (body as? [String: Any])?["wrapper"] as? [String: Any] ?? [:]
        switch k {
        case "primitive":
            switch (w["typeIdentifier"] as? NSNumber)?.intValue {
            case 0: return .string
            case 1: return .bool
            case 2: return .int
            case 7: return .double
            case 8: return .date
            case 9: return .dateComponents
            case 10: return .location
            case 11: return .url
            case 12: return .attributedString
            case let n: return .other("primitive-\(n.map(String.init) ?? "?")")
            }
        case "linkEnumeration":
            let id = w["identifier"] as? String ?? "?"
            return .enumeration(id: id, cases: enumCases[id] ?? [])
        case "entity":
            return .entity(w["typeName"] as? String ?? "?")
        case "array":
            return .array(ParamKindBox(kind(w["memberValueType"], enumCases: enumCases)))
        case "intents":
            // 12 = file (MacWhisper's audio file, verified in M0); other codes are unmapped.
            let n = (w["typeIdentifier"] as? NSNumber)?.intValue
            return n == 12 ? .file : .other("intents-\(n.map(String.init) ?? "?")")
        default:
            return .other(k)
        }
    }
}
