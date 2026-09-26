import Foundation

/// Finds every App Intents metadata file and builds the action list.
public struct ActionIndex: Sendable {
    public var actions: [ActionSpec]
    public var files: [String]
    /// Actions declared across all files, before de-duplication.
    public var declaredCount: Int
    public var errors: [String]

    /// Scan order is priority order: when the same action is declared twice (e.g. a Catalyst copy
    /// under /System/iOSSupport), the first one wins.
    public static let defaultRoots = [
        "/Applications", NSHomeDirectory() + "/Applications", "/System/Applications",
        "/System/Cryptexes/App", "/System/Library", "/Library/Apple", "/System/iOSSupport",
    ]

    static let bundleExtensions: Set<String> = ["app", "appex", "framework", "bundle", "xpc", "extensionkit", "flowtool"]

    /// `extract.actionsdata` (all current apps) and the legacy `Link.data` location (Weather).
    /// Metadata sits in a bundle's `Resources` (or, in iOS-layout bundles, at the bundle's top level),
    /// so the walk checks those paths and never descends into `Resources`.
    /// Symlinked roots and symlinked bundles inside a root (e.g. SafariSwift.framework, which points
    /// into the OS cryptex) are followed once each.
    public static func findMetadataFiles(roots: [String] = defaultRoots) -> [URL] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [URL] = []
        var walked = Set<String>()
        var queue = roots
        let skip: Set<String> = ["_CodeSignature", "Headers", "PrivateHeaders", "Modules", "MacOS", "Caches",
                                 "Assets", "AssetsV2", "Fonts", "Updates"]
        func check(_ path: String) {
            guard fm.fileExists(atPath: path) else { return }
            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            if seen.insert(url.path).inserted { out.append(url) }
        }
        while !queue.isEmpty {
            let root = queue.removeFirst()
            let real = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
            guard fm.fileExists(atPath: root), walked.insert(real).inserted else { continue }
            // fts(3), as find(1) uses: physical walk, one device per root; a symlinked root is followed.
            root.withCString { cRoot in
                var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cRoot), nil]
                defer { free(paths[0]) }
                guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_COMFOLLOW | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
                defer { fts_close(fts) }
                while let ent = fts_read(fts) {
                    // fts_name is a flexible array member (unsafe to read through a copy); use the path.
                    let dir = String(cString: ent.pointee.fts_path)
                    let name = (dir as NSString).lastPathComponent
                    let ext = (name as NSString).pathExtension
                    if ent.pointee.fts_info == FTS_SL {
                        if bundleExtensions.contains(ext) { queue.append(dir) }
                        continue
                    }
                    guard ent.pointee.fts_info == FTS_D else { continue }
                    if name == "Resources" {
                        // Bundles nested inside Resources are not searched: walking Resources cost ~40%
                        // more scan time and found no metadata on the Mac checked (2026-09-26).
                        fts_set(fts, ent, FTS_SKIP)
                        for sub in ["Metadata.appintents", "Link.data"] { check("\(dir)/\(sub)/extract.actionsdata") }
                    } else if skip.contains(name) || name.hasSuffix(".lproj") {
                        fts_set(fts, ent, FTS_SKIP)
                    } else if bundleExtensions.contains(ext) {
                        check("\(dir)/Metadata.appintents/extract.actionsdata")  // iOS-layout bundle
                    }
                }
            }
        }
        return out
    }

    public static func build(files: [URL], apps: AppDirectory, parser: MetadataParser = MetadataParser(),
                             reserved: Set<String> = []) -> ActionIndex {
        var actions: [ActionSpec] = []
        var byKey: [String: Int] = [:]
        var declared = 0
        var errors: [String] = []
        for file in files {
            guard let bundleURL = Bundles.containingBundle(of: file), let source = Bundles.facts(bundleURL) else {
                errors.append("no bundle for \(file.path)")
                continue
            }
            let resources = file.deletingLastPathComponent().deletingLastPathComponent()
            let raws: [RawAction]
            do {
                raws = try parser.parse(data: try Data(contentsOf: file), resources: resources, path: file.path)
            } catch {
                errors.append("\(file.path): \(error)")
                continue
            }
            declared += raws.count
            var hosts = raws.map { hostApp($0, source: source, apps: apps) }
            // Unattributed siblings follow the app the file's attributed actions name (if only one).
            let attributed = Set(hosts.filter { $0.1 == "attribution" }.map { $0.0.bundleID })
            if attributed.count == 1, let h = hosts.first(where: { $0.1 == "attribution" })?.0 {
                for i in hosts.indices where hosts[i].1 == "self" { hosts[i] = (h, "sibling-attribution") }
            }
            for (raw, (host, mapping)) in zip(raws, hosts) {
                let spec = makeSpec(raw, host: host, source: source, mapping: mapping)
                // One entry per (app users see, intent): drops Catalyst and extension copies. Only the
                // app's own declaration replaces an earlier copy (never a framework or Catalyst copy).
                let key = "\(host.bundleID.lowercased())/\(raw.identifier)"
                if let i = byKey[key] {
                    if source.bundleID.lowercased() == host.bundleID.lowercased(),
                       actions[i].source.bundleID.lowercased() != host.bundleID.lowercased() {
                        var replacement = spec
                        // Keep a translated title over an unresolved localization key ("FOO_BAR_TITLE").
                        if Self.looksLikeKey(spec.title), !Self.looksLikeKey(actions[i].title) {
                            replacement.title = actions[i].title
                        }
                        actions[i] = replacement
                    }
                } else {
                    byKey[key] = actions.count
                    actions.append(spec)
                }
            }
        }
        assignAliases(&actions, reserved: reserved)
        return ActionIndex(actions: actions, files: files.map(\.path), declaredCount: declared, errors: errors)
    }

    public static func scan(reserved: Set<String> = []) -> ActionIndex {
        build(files: findMetadataFiles(), apps: AppDirectory.scan(), reserved: reserved)
    }

    /// Which app a user would say the action belongs to (tech-notes §1.3: Reminders' and Calendar's
    /// intents live in private frameworks).
    static func hostApp(_ raw: RawAction, source: BundleFacts, apps: AppDirectory) -> (BundleFacts, String) {
        if let attr = raw.attributionBundleID, attr != source.bundleID {
            if let a = apps.app(bundleID: attr) { return (a, "attribution") }
        }
        if let appURL = Bundles.enclosingApp(of: source.url), appURL != source.url,
           let a = apps.app(bundleID: Bundles.facts(appURL)?.bundleID ?? "") ?? Bundles.facts(appURL) {
            return (a, "container")
        }
        if let a = apps.hostForExtension(source) { return (a, "settings-extension") }
        if source.url.pathExtension == "framework",
           let a = apps.hostForFramework(named: source.url.deletingPathExtension().lastPathComponent) {
            return (a, "framework-name")
        }
        return (source, "self")
    }

    static func makeSpec(_ raw: RawAction, host: BundleFacts, source: BundleFacts, mapping: String) -> ActionSpec {
        let (tier, tierReasons) = Classifier.tier(raw)
        let risk = Classifier.risk(raw)
        return ActionSpec(
            // The declaring bundle, as in Apple's own workflows for extension-hosted intents
            // (tech-notes §3.1). Not guaranteed to be what Shortcuts accepts: M0 showed Reminders'
            // framework intent is refused either way, so M2 verifies the invocation ID per action.
            id: "\(source.bundleID).\(raw.identifier)",
            alias: "",
            intentIdentifier: raw.identifier,
            app: host.appRef,
            source: SourceRef(bundleID: source.bundleID, path: source.url.path, hostMapping: mapping),
            title: raw.title,
            description: raw.description,
            parameters: raw.parameters,
            outputType: raw.outputType,
            supportedModes: Classifier.modes(raw),
            discoverable: raw.discoverable,
            availableOnMac: raw.availableOnMac ? nil : false,
            opensApp: Classifier.opensApp(raw),
            systemProtocols: raw.systemProtocols,
            risky: !risk.isEmpty,
            riskReasons: risk,
            tier: tier,
            tierReasons: tierReasons)
    }

    /// "<app>.<title>" in kebab case; the stable `id` stays the source of truth. Unique, and never one
    /// of `reserved` (catalog tools and read-back helpers).
    static func assignAliases(_ actions: inout [ActionSpec], reserved: Set<String> = []) {
        var used = reserved
        for i in actions.indices {
            let app = Classifier.slug(actions[i].app.name)
            var base = "\(app.isEmpty ? "app" : app).\(Classifier.slug(actions[i].title))"
            if base.hasSuffix(".") { base += Classifier.slug(actions[i].intentIdentifier) }
            var alias = base
            var n = 2
            while used.contains(alias) {
                alias = "\(base)-\(n)"
                n += 1
            }
            used.insert(alias)
            actions[i].alias = alias
        }
    }

    static func looksLikeKey(_ s: String) -> Bool {
        s.count > 3 && s.range(of: #"^[A-Z0-9_]+$"#, options: .regularExpression) != nil && s.contains("_")
    }

    public func lookup(_ key: String) -> ActionSpec? {
        actions.first { $0.id == key || $0.alias == key }
    }
}
