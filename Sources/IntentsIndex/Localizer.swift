import Foundation

/// Resolves App Intents strings to English through a bundle's compiled `.loctable`
/// (a binary plist keyed by locale, then by key) or `en.lproj/<table>.strings`.
/// English, not the user's language: tool names and descriptions are read by agents.
public final class Localizer: @unchecked Sendable {
    private var cache: [String: [String: Any]] = [:]
    private let lock = NSLock()
    static let locales = ["en", "en_US", "en_GB", "Base"]

    public init() {}

    public func english(key: String, table: String?, resources: URL) -> String? {
        let table = table ?? "Localizable"
        guard let strings = self.table(table, resources: resources) else { return nil }
        switch strings[key] {
        case let s as String where !s.isEmpty: return s
        case let d as [String: Any]:
            // Plural/variable forms: fall back to the format key's own text.
            return d["NSStringLocalizedFormatKey"] as? String
        default: return nil
        }
    }

    func table(_ name: String, resources: URL) -> [String: Any]? {
        let cacheKey = resources.path + "#" + name
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[cacheKey] { return hit }
        var found: [String: Any] = [:]
        let loc = resources.appendingPathComponent(name + ".loctable")
        if let data = try? Data(contentsOf: loc),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            for l in Self.locales {
                if let t = plist[l] as? [String: Any] { found = t; break }
            }
        } else {
            for l in Self.locales {
                let url = resources.appendingPathComponent("\(l).lproj/\(name).strings")
                if let d = NSDictionary(contentsOf: url) as? [String: Any] { found = d; break }
            }
        }
        cache[cacheKey] = found
        return found
    }
}
