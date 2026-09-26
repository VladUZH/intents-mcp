import Foundation
import Testing
@testable import IntentsIndex

/// A throwaway app bundle on disk holding the fixture metadata and a `.loctable`.
struct FixtureApp {
    let root: URL
    let app: URL

    init(name: String = "Fixture", bundleID: String = "com.example.fixture") throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("imcp-test-\(UUID().uuidString)")
        app = root.appendingPathComponent("\(name).app")
        let resources = app.appendingPathComponent("Contents/Resources")
        let meta = resources.appendingPathComponent("Metadata.appintents")
        try FileManager.default.createDirectory(at: meta, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundleShortVersionString": "1.2"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let fixture = Bundle.module.url(forResource: "Fixtures/extract", withExtension: "actionsdata")!
        try FileManager.default.copyItem(at: fixture, to: meta.appendingPathComponent("extract.actionsdata"))
        let table: [String: Any] = ["en": ["LOCALIZED_THING_TITLE": "Localized Thing"], "de": ["LOCALIZED_THING_TITLE": "Lokalisiert"]]
        try PropertyListSerialization.data(fromPropertyList: table, format: .binary, options: 0)
            .write(to: resources.appendingPathComponent("FixtureIntents.loctable"))
    }

    var resources: URL { app.appendingPathComponent("Contents/Resources") }
    var metadata: URL { resources.appendingPathComponent("Metadata.appintents/extract.actionsdata") }

    func index() -> ActionIndex {
        ActionIndex.build(files: ActionIndex.findMetadataFiles(roots: [root.path]), apps: AppDirectory(apps: []))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Suite struct ParserTests {
    func raws() throws -> [String: RawAction] {
        let f = try FixtureApp()
        defer { f.remove() }
        let raws = try MetadataParser().parse(data: Data(contentsOf: f.metadata), resources: f.resources)
        return Dictionary(uniqueKeysWithValues: raws.map { ($0.identifier, $0) })
    }

    @Test func parameterKinds() throws {
        let create = try #require(try raws()["CreateThingIntent"])
        let kinds = Dictionary(uniqueKeysWithValues: create.parameters.map { ($0.name, $0.kind) })
        #expect(kinds["name"] == .string)
        #expect(kinds["pinned"] == .bool)
        #expect(kinds["count"] == .int)
        #expect(kinds["size"] == .double)
        #expect(kinds["when"] == .date)
        #expect(kinds["due"] == .dateComponents)
        #expect(kinds["link"] == .url)
        #expect(kinds["body"] == .attributedString)
        #expect(kinds["style"] == .enumeration(id: "ThingStyle", cases: ["plain", "fancy"]))
        #expect(create.outputType == "string")
        #expect(create.parameters.first { $0.name == "pinned" }?.optional == true)
    }

    @Test func entitiesArraysAndFiles() throws {
        let r = try raws()
        #expect(r["AppendToThingIntent"]?.parameters.first?.kind == .entity("ThingEntity"))
        #expect(r["DeleteThingsIntent"]?.parameters.first?.kind.needsEntity == true)
        #expect(r["ImportFileIntent"]?.parameters.first?.kind == .file)
    }

    @Test func localizedAndMissingTitles() throws {
        let r = try raws()
        #expect(r["LocalizedThingIntent"]?.title == "Localized Thing")  // English, not the user's language
        #expect(r["CRLUntitledThingIntent"]?.title == "CRL Untitled Thing")
        #expect(r["CreateThingIntent"]?.title == "Create Thing")
    }

    @Test func humanize() {
        #expect(MetadataParser.humanize("CRLCreateBoardIntent") == "CRL Create Board")
        #expect(MetadataParser.humanize("TTRCreateReminderAppIntent") == "TTR Create Reminder")
        #expect(MetadataParser.humanize("CreateNoteLinkAction") == "Create Note")
    }

    @Test func rejectsNonObject() {
        #expect(throws: MetadataError.self) { try MetadataParser().parse(data: Data("[]".utf8), resources: nil) }
    }
}

@Suite struct ClassifierTests {
    func spec(_ id: String) throws -> ActionSpec {
        let f = try FixtureApp()
        defer { f.remove() }
        return try #require(f.index().actions.first { $0.intentIdentifier == id })
    }

    @Test func simpleTier() throws {
        let s = try spec("CreateThingIntent")
        #expect(s.tier == .simple)
        #expect(s.tierReasons.isEmpty)
        #expect(s.supportedModes == ["background"])
        #expect(!s.risky)
    }

    @Test func entityTier() throws {
        #expect(try spec("AppendToThingIntent").tier == .needsEntity)
        #expect(try spec("DeleteThingsIntent").tier == .needsEntity)
    }

    @Test func unsupportedTiers() throws {
        let open = try spec("OpenThingIntent")
        #expect(open.tier == .unsupported)
        #expect(open.opensApp)
        #expect(open.tierReasons.contains("opens the app"))
        #expect(try spec("HiddenThingIntent").tierReasons.contains("not discoverable in Shortcuts"))
        #expect(try spec("TestDebugThingIntent").tierReasons.contains("looks internal (test/debug)"))
        #expect(try spec("ImportFileIntent").tier == .unsupported)
    }

    @Test func risk() throws {
        let del = try spec("DeleteThingsIntent")
        #expect(del.risky)
        #expect(del.riskReasons.contains("DeleteEntity protocol"))
        #expect(try spec("SendThingIntent").riskReasons == ["name: send"])
        #expect(try !spec("GetLockMessageIntent").risky)
    }

    @Test func tokensAndSlugs() {
        #expect(Classifier.tokens("TTRCreateReminderAppIntent") == ["ttr", "create", "reminder", "app", "intent"])
        #expect(Classifier.tokens("get_lock-message2") == ["get", "lock", "message2"])
        #expect(Classifier.tokens("DeleteNotesLinkAction").contains("delete"))
        #expect(Classifier.slug("Get Guest User's Status") == "get-guest-user-s-status")
    }

    @Test func modesFromBits() {
        func raw(_ m: Int?, open: Bool? = nil) -> RawAction {
            RawAction(identifier: "X", fullyQualifiedTypeName: nil, title: "X", description: nil, parameters: [],
                      outputType: nil, supportedModes: m, openAppWhenRun: open, discoverable: true,
                      systemProtocols: [], attributionBundleID: nil)
        }
        #expect(Classifier.modes(raw(1)) == ["background"])
        #expect(Classifier.modes(raw(3)) == ["background", "foreground"])
        #expect(Classifier.modes(raw(nil, open: true)) == ["foreground"])
        #expect(Classifier.opensApp(raw(2)))
        #expect(!Classifier.opensApp(raw(3)))
    }
}

@Suite struct IndexTests {
    @Test func scanBuildAndCensus() throws {
        let f = try FixtureApp()
        defer { f.remove() }
        let index = f.index()
        #expect(index.files.count == 1)
        #expect(index.declaredCount == 11)
        #expect(index.actions.count == 11)
        #expect(index.errors.isEmpty)
        let a = try #require(index.lookup("fixture.create-thing"))
        #expect(a.id == "com.example.fixture.CreateThingIntent")
        #expect(a.app.bundleID == "com.example.fixture")
        #expect(a.app.version == "1.2")
        #expect(a.source.hostMapping == "self")
        #expect(index.lookup(a.id) == a)

        let c = Census(index)
        #expect(c.declaredActions == 11)
        // Create, Send, Get Lock Message, Localized, CRL Untitled (no parameters, returns output)
        #expect(c.byTier["simple"] == 5)
        #expect(c.byTier["entity"] == 2)
        #expect(c.byTier["unsupported"] == 4)  // Open, Hidden, Test Debug, Import File
        #expect(c.risky == 2)
        #expect(c.thirdParty.apps == 1)  // unsigned temp bundle: no Apple Team ID
    }

    @Test func aliasesAreUnique() throws {
        let f = try FixtureApp()
        defer { f.remove() }
        var actions = f.index().actions
        actions.append(actions[0])
        ActionIndex.assignAliases(&actions)
        #expect(Set(actions.map(\.alias)).count == actions.count)
        #expect(actions.last?.alias.hasSuffix("-2") == true)
    }

    @Test func jsonRoundTrip() throws {
        let f = try FixtureApp()
        defer { f.remove() }
        let actions = f.index().actions
        let data = try JSONEncoder().encode(actions)
        #expect(try JSONDecoder().decode([ActionSpec].self, from: data) == actions)
    }

    @Test func findsBundlesAndSkipsSymlinkedResources() throws {
        let f = try FixtureApp()
        defer { f.remove() }
        // A framework laid out like Apple's: top-level Resources is a symlink to Versions/A/Resources,
        // and a nested bundle follows it. Both metadata files must be found, once each.
        let fw = f.root.appendingPathComponent("Thing.framework")
        let real = fw.appendingPathComponent("Versions/A/Resources/Metadata.appintents")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: f.metadata, to: real.appendingPathComponent("extract.actionsdata"))
        try FileManager.default.createSymbolicLink(atPath: fw.appendingPathComponent("Resources").path,
                                                   withDestinationPath: "Versions/A/Resources")
        let nested = fw.appendingPathComponent("zzhelper.app/Contents/Resources/Metadata.appintents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: f.metadata, to: nested.appendingPathComponent("extract.actionsdata"))
        #expect(ActionIndex.findMetadataFiles(roots: [f.root.path]).count == 3)
        #expect(Bundles.containingBundle(of: real.appendingPathComponent("extract.actionsdata"))?.lastPathComponent == "Thing.framework")
    }

    @Test func frameworkHostNames() {
        let apps = AppDirectory(apps: [
            BundleFacts(url: URL(fileURLWithPath: "/System/Applications/Reminders.app"), bundleID: "com.apple.reminders", name: "Reminders"),
            BundleFacts(url: URL(fileURLWithPath: "/System/Applications/Calendar.app"), bundleID: "com.apple.iCal", name: "Calendar"),
            BundleFacts(url: URL(fileURLWithPath: "/System/Applications/Photos.app"), bundleID: "com.apple.Photos", name: "Photos"),
        ])
        #expect(apps.hostForFramework(named: "RemindersAppIntents")?.name == "Reminders")
        #expect(apps.hostForFramework(named: "CalendarLink")?.name == "Calendar")
        #expect(apps.hostForFramework(named: "PhotosUICore")?.name == "Photos")
        #expect(apps.hostForFramework(named: "WidgetKit") == nil)
    }
}

@Suite struct BugHuntRegressionTests {
    @Test func aliasesStayUniqueAndAvoidReservedNames() throws {
        let f = try FixtureApp()
        defer { f.remove() }
        var actions = f.index().actions
        // A title whose slug already ends in "-2" must not collide with a numbered duplicate.
        actions[1].title = actions[0].title + " 2"
        actions.append(actions[0])
        ActionIndex.assignAliases(&actions, reserved: ["fixture.create-thing"])
        #expect(Set(actions.map(\.alias)).count == actions.count)
        #expect(!actions.map(\.alias).contains("fixture.create-thing"))
    }

    @Test func walkFollowsSymlinkedRootsAndBundlesAndFindsFlatMetadata() throws {
        let f = try FixtureApp()
        defer { f.remove() }
        let fm = FileManager.default
        // A symlinked root (like /System/Cryptexes/App).
        let link = f.root.deletingLastPathComponent().appendingPathComponent("imcp-link-\(UUID().uuidString)")
        try fm.createSymbolicLink(at: link, withDestinationURL: f.root)
        defer { try? fm.removeItem(at: link) }
        #expect(ActionIndex.findMetadataFiles(roots: [link.path]).count == 1)
        // A symlinked bundle inside a root (like SafariSwift.framework).
        let elsewhere = f.root.deletingLastPathComponent().appendingPathComponent("imcp-target-\(UUID().uuidString)")
        let fw = elsewhere.appendingPathComponent("Real.framework/Resources/Metadata.appintents")
        try fm.createDirectory(at: fw, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: elsewhere) }
        try fm.copyItem(at: f.metadata, to: fw.appendingPathComponent("extract.actionsdata"))
        try fm.createSymbolicLink(at: f.root.appendingPathComponent("Linked.framework"),
                                  withDestinationURL: elsewhere.appendingPathComponent("Real.framework"))
        // An iOS-layout app (metadata at the bundle's top level) and a bundle nested in Resources.
        let flat = f.root.appendingPathComponent("Wrapped.app/Wrapper/Inner.app/Metadata.appintents")
        try fm.createDirectory(at: flat, withIntermediateDirectories: true)
        try fm.copyItem(at: f.metadata, to: flat.appendingPathComponent("extract.actionsdata"))
        let nested = f.resources.appendingPathComponent("Plugin.bundle/Contents/Resources/Metadata.appintents")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try fm.copyItem(at: f.metadata, to: nested.appendingPathComponent("extract.actionsdata"))
        // Symlinked bundle + iOS-layout app are found; bundles nested inside Resources are not
        // searched on purpose (cost ~40% more scan time and found nothing on the Mac checked).
        #expect(ActionIndex.findMetadataFiles(roots: [f.root.path]).count == 3)
    }

    @Test func availabilityOnMac() {
        #expect(!MetadataParser.availableOnMac(["LNPlatformNameMACOS": ["obsoletedVersion": "*"]]))
        #expect(!MetadataParser.availableOnMac(["LNPlatformNameMACOS": ["introducedVersion": "99.0"]], running: [27, 0, 0]))
        #expect(!MetadataParser.availableOnMac(["LNPlatformNameMACOS": ["introducedVersion": "26.4"]], running: [26, 2, 0]))
        #expect(MetadataParser.availableOnMac(["LNPlatformNameMACOS": ["introducedVersion": "26.4"]], running: [27, 0, 0]))
        #expect(MetadataParser.availableOnMac(["LNPlatformNameMACOS": ["obsoletedVersion": "30.0"]], running: [27, 0, 0]))
        #expect(MetadataParser.availableOnMac(["LNPlatformNameWildcard": ["introducedVersion": "*"]]))
        #expect(MetadataParser.availableOnMac(nil))
    }

    @Test func namesAppleAndRisk() {
        #expect(Bundles.clean("\u{200E}WhatsApp ") == "WhatsApp")
        #expect(AppRef(name: "Pages", bundleID: "com.apple.iWork.Pages", version: nil, path: "/", teamID: "K36BKF7T3D").isApple)
        #expect(!AppRef(name: "X", bundleID: "com.example.x", version: nil, path: "/", teamID: "ABCDE12345").isApple)
        func raw(_ id: String) -> RawAction {
            RawAction(identifier: id, fullyQualifiedTypeName: nil, title: id, description: nil, parameters: [],
                      outputType: "string", supportedModes: 1, openAppWhenRun: false, discoverable: true,
                      systemProtocols: [], attributionBundleID: nil)
        }
        for id in ["DeletedItemsIntent", "SentMessageIntent", "SharingIntent", "PaymentIntent", "UnsubscribeIntent", "TransferFundsIntent"] {
            #expect(!Classifier.risk(raw(id)).isEmpty, "\(id)")
        }
        #expect(Classifier.risk(raw("GetLockMessageIntent")).isEmpty)
        #expect(!ParamKind.enumeration(id: "X", cases: []).isSimple)
    }
}

@Suite struct VerificationRoundRegressionTests {
    @Test func riskFromDescriptionsAndMoreWords() {
        func raw(_ id: String, _ desc: String? = nil) -> RawAction {
            RawAction(identifier: id, fullyQualifiedTypeName: nil, title: id, description: desc, parameters: [],
                      outputType: "string", supportedModes: 1, openAppWhenRun: false, discoverable: true,
                      systemProtocols: [], attributionBundleID: nil)
        }
        #expect(Classifier.risk(raw("UnsaveArticleIntent")).contains("name: unsave"))
        #expect(Classifier.risk(raw("RemoveFromListIntent2", "Deletes the item from your list")).contains("description: deletes"))
    }

    @Test func unavailableActionsAreNotEntityOrDiscoverable() {
        var raw = RawAction(identifier: "X", fullyQualifiedTypeName: nil, title: "X", description: nil,
                            parameters: [ParamSpec(name: "n", title: "N", description: nil, optional: false, kind: .entity("NoteEntity"))],
                            outputType: "string", supportedModes: 1, openAppWhenRun: false, discoverable: true,
                            systemProtocols: [], attributionBundleID: nil)
        #expect(Classifier.tier(raw).0 == .needsEntity)
        raw.availableOnMac = false
        #expect(Classifier.tier(raw).0 == .unsupported)
    }

    @Test func frameworkHostForSafari() {
        let apps = AppDirectory(apps: [BundleFacts(url: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari", name: "Safari")])
        #expect(apps.hostForFramework(named: "SafariSwift")?.name == "Safari")
        #expect(apps.app(bundleID: "COM.APPLE.SAFARI")?.name == "Safari")
    }
}
