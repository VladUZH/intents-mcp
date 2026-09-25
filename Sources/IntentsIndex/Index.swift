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

    /// `extract.actionsdata` (all current apps) and the legacy `Link.data` location (Weather).
    /// Metadata always sits in a bundle's `Resources` directory, so the walk checks the two known
    /// paths there and never descends into `Resources` or other directories that can't hold it.
    public static func findMetadataFiles(roots: [String] = defaultRoots) -> [URL] {
        let fm = FileManager.default
        var seen = Set<String>()
        var out: [URL] = []
        let skip: Set<String> = ["_CodeSignature", "Headers", "PrivateHeaders", "Modules", "MacOS", "Caches",
                                 "Assets", "AssetsV2", "Fonts", "Updates"]
        // fts(3), as find(1) uses: physical walk (symlinks not followed), one device per root.
        for root in roots where fm.fileExists(atPath: root) {
            root.withCString { cRoot in
                var paths: [UnsafeMutablePointer<CChar>?] = [strdup(cRoot), nil]
                defer { free(paths[0]) }
                guard let fts = fts_open(&paths, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else { return }
                defer { fts_close(fts) }
                while let ent = fts_read(fts) {
                    guard ent.pointee.fts_info == FTS_D else { continue }
                    // fts_name is a flexible array member (unsafe to read through a copy); use the path.
                    let dir = String(cString: ent.pointee.fts_path)
                    let name = (dir as NSString).lastPathComponent
                    if name == "Resources" {
                        fts_set(fts, ent, FTS_SKIP)
                        for sub in ["Metadata.appintents", "Link.data"] {
                            let path = "\(dir)/\(sub)/extract.actionsdata"
                            guard fm.fileExists(atPath: path) else { continue }
                            let url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
                            if seen.insert(url.path).inserted { out.append(url) }
                        }
                    } else if skip.contains(name) || name.hasSuffix(".lproj") {
                        fts_set(fts, ent, FTS_SKIP)
                    }
                }
            }
        }
        return out
    }

    public static func build(files: [URL], apps: AppDirectory, parser: MetadataParser = MetadataParser()) -> ActionIndex {
        var actions: [ActionSpec] = []
        var seenIDs = Set<String>()
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
            for raw in raws {
                let (host, mapping) = hostApp(raw, source: source, apps: apps)
                let spec = makeSpec(raw, host: host, source: source, mapping: mapping)
                // One entry per (app users see, intent): drops Catalyst and extension copies.
                if seenIDs.insert("\(host.bundleID)/\(raw.identifier)").inserted { actions.append(spec) }
            }
        }
        assignAliases(&actions)
        return ActionIndex(actions: actions, files: files.map(\.path), declaredCount: declared, errors: errors)
    }

    public static func scan() -> ActionIndex {
        build(files: findMetadataFiles(), apps: AppDirectory.scan())
    }

    /// Which app a user would say the action belongs to (tech-notes §1.3: Reminders' and Calendar's
    /// intents live in private frameworks).
    static func hostApp(_ raw: RawAction, source: BundleFacts, apps: AppDirectory) -> (BundleFacts, String) {
        if let attr = raw.attributionBundleID, attr != source.bundleID {
            if let a = apps.app(bundleID: attr) { return (a, "attribution") }
        }
        if let appURL = Bundles.enclosingApp(of: source.url), appURL != source.url,
           let a = apps.byBundleID[Bundles.facts(appURL)?.bundleID ?? ""] ?? Bundles.facts(appURL) {
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
            opensApp: Classifier.opensApp(raw),
            systemProtocols: raw.systemProtocols,
            risky: !risk.isEmpty,
            riskReasons: risk,
            tier: tier,
            tierReasons: tierReasons)
    }

    /// "<app>.<title>" in kebab case; the stable `id` stays the source of truth.
    static func assignAliases(_ actions: inout [ActionSpec]) {
        var used: [String: Int] = [:]
        for i in actions.indices {
            let app = Classifier.slug(actions[i].app.name)
            var base = "\(app.isEmpty ? "app" : app).\(Classifier.slug(actions[i].title))"
            if base.hasSuffix(".") { base += Classifier.slug(actions[i].intentIdentifier) }
            let n = (used[base] ?? 0) + 1
            used[base] = n
            actions[i].alias = n == 1 ? base : "\(base)-\(n)"
        }
    }

    public func lookup(_ key: String) -> ActionSpec? {
        actions.first { $0.id == key || $0.alias == key }
    }
}
