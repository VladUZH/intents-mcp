import Foundation
import Security

/// Bundle facts for a metadata file's declaring bundle and for installed apps.
public struct BundleFacts: Sendable, Equatable {
    public var url: URL
    public var bundleID: String
    public var name: String
    public var version: String?
    public var teamID: String?

    public var appRef: AppRef {
        AppRef(name: name, bundleID: bundleID, version: version, path: url.path, teamID: teamID)
    }
}

public enum Bundles {
    static let bundleExtensions: Set<String> = ["app", "appex", "framework", "bundle", "xpc", "extensionkit"]

    /// The innermost bundle containing `file` (e.g. `Notes.app`, `CalendarLink.framework`).
    public static func containingBundle(of file: URL) -> URL? {
        var u = file.deletingLastPathComponent()
        while u.path != "/" {
            if bundleExtensions.contains(u.pathExtension) { return u }
            // Any other bundle type (e.g. `.flowtool`): a directory with Contents/Info.plist.
            if !u.pathExtension.isEmpty,
               FileManager.default.fileExists(atPath: u.appendingPathComponent("Contents/Info.plist").path) { return u }
            u = u.deletingLastPathComponent()
        }
        return nil
    }

    /// The outermost `.app` enclosing `url`, if `url` is nested in one (an appex or embedded framework).
    public static func enclosingApp(of url: URL) -> URL? {
        var u = url.deletingLastPathComponent()
        var found: URL?
        while u.path != "/" {
            if u.pathExtension == "app" { found = u }
            u = u.deletingLastPathComponent()
        }
        return found
    }

    public static func facts(_ url: URL) -> BundleFacts? {
        guard let b = Bundle(url: url), let info = b.infoDictionary, let id = info["CFBundleIdentifier"] as? String else {
            return nil
        }
        let name = (info["CFBundleDisplayName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (info["CFBundleName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? url.deletingPathExtension().lastPathComponent
        return BundleFacts(url: url, bundleID: id, name: name,
                           version: info["CFBundleShortVersionString"] as? String, teamID: teamID(url))
    }

    /// Team ID from the code signature (public Security API). Apple's own code under /System and
    /// platform binaries have no Team ID; shortcuts use "0000000000" for them (tech-notes §3.1).
    public static func teamID(_ url: URL) -> String? {
        if url.path.hasPrefix("/System/") { return "0000000000" }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        if let team = dict[kSecCodeInfoTeamIdentifier as String] as? String { return team }
        if let platform = dict[kSecCodeInfoPlatformIdentifier as String] as? NSNumber, platform.intValue != 0 {
            return "0000000000"
        }
        return nil
    }
}

/// Installed apps, for mapping framework- and extension-hosted actions to the app users know.
public struct AppDirectory: Sendable {
    public var byBundleID: [String: BundleFacts] = [:]
    public var byName: [String: BundleFacts] = [:]

    public static let defaultRoots = [
        "/Applications", "/System/Applications", "/System/Applications/Utilities",
        "/System/Library/CoreServices", "/System/Cryptexes/App/System/Applications",
        NSHomeDirectory() + "/Applications",
    ]

    public init(apps: [BundleFacts]) {
        for a in apps {
            byBundleID[a.bundleID] = byBundleID[a.bundleID] ?? a
            byName[a.name.lowercased()] = byName[a.name.lowercased()] ?? a
        }
    }

    public static func scan(roots: [String] = defaultRoots) -> AppDirectory {
        let fm = FileManager.default
        var apps: [BundleFacts] = []
        for r in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: r) else { continue }
            for i in items where i.hasSuffix(".app") {
                if let f = Bundles.facts(URL(fileURLWithPath: r).appendingPathComponent(i)) { apps.append(f) }
            }
        }
        return AppDirectory(apps: apps)
    }

    /// Framework name → app name guesses ("RemindersAppIntents" → "reminders", "CalendarLink" → "calendar").
    static let frameworkSuffixes = ["AppIntents", "Intents", "Link", "UICore", "UIPrivate", "UI", "Core", "Kit", "Support"]
    /// Frameworks whose name doesn't reveal the app (checked on macOS 27).
    static let frameworkHosts = ["ChatKit": "com.apple.MobileSMS", "PassKitUI": "com.apple.Passbook",
                                 "MobileTimerSupport": "com.apple.clock"]
    /// Attribution targets that are placeholders for the app users know (display only; `id` uses
    /// the declaring bundle).
    static let hostAliases = ["com.apple.Settings": "com.apple.systempreferences"]
    static let systemSettingsID = "com.apple.systempreferences"

    public func app(bundleID: String) -> BundleFacts? {
        byBundleID[Self.hostAliases[bundleID] ?? bundleID]
    }

    /// Settings panes and their widgets ship as ExtensionKit extensions without attribution.
    public func hostForExtension(_ source: BundleFacts) -> BundleFacts? {
        guard source.url.path.hasPrefix("/System/Library/ExtensionKit/"),
              source.url.lastPathComponent.contains("Settings") else { return nil }
        return byBundleID[Self.systemSettingsID]
    }

    public func hostForFramework(named name: String) -> BundleFacts? {
        if let id = Self.frameworkHosts[name], let f = byBundleID[id] { return f }
        var n = name
        for _ in 0..<3 {
            if let f = byName[n.lowercased()] { return f }
            guard let s = Self.frameworkSuffixes.first(where: { n.hasSuffix($0) && n.count > $0.count }) else { break }
            n = String(n.dropLast(s.count))
        }
        return byName[n.lowercased()]
    }
}
