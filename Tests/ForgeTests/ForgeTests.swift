import Core
import Foundation
@testable import IntentsIndex
import Runner
import ShortcutForge
import Store
import Testing

func actions(_ r: Recipe) -> [[String: Any]] {
    WrapperBuilder.plist(r)["WFWorkflowActions"] as! [[String: Any]]
}

func params(_ a: [String: Any]) -> [String: Any] { a["WFWorkflowActionParameters"] as! [String: Any] }

@Suite struct WrapperTests {
    @Test func remindersWrapperMatchesTheM0Design() throws {
        // Same shape as Spike/forge.py's reminders-builtin, which created real reminders in M0,
        // plus the derived WFAlertEnabled value.
        let ids = actions(Catalog.remindersAdd).map { $0["WFWorkflowActionIdentifier"] as! String }
        #expect(ids == [
            "is.workflow.actions.detect.dictionary",
            "is.workflow.actions.getvalueforkey", "is.workflow.actions.gettext",  // title
            "is.workflow.actions.getvalueforkey", "is.workflow.actions.gettext",  // notes
            "is.workflow.actions.getvalueforkey", "is.workflow.actions.gettext",  // due
            "is.workflow.actions.getvalueforkey",                                  // alert (enum: attached as-is)
            "is.workflow.actions.addnewreminder",
            "is.workflow.actions.gettext", "is.workflow.actions.output",
        ])
        let p = params(actions(Catalog.remindersAdd)[8])
        #expect((p["WFCalendarItemTitle"] as? [String: Any])?["WFSerializationType"] as? String == "WFTextTokenString")
        #expect((p["WFAlertEnabled"] as? [String: Any])?["WFSerializationType"] as? String == "WFTextTokenAttachment")
        #expect(p["WFAlertCondition"] as? String == "At Time")
        #expect(p["AppIntentDescriptor"] == nil)
    }

    @Test func notesWrapperUsesTheLegacyKey() {
        let a = actions(Catalog.notesCreate)
        let act = a.first { ($0["WFWorkflowActionIdentifier"] as! String) == "com.apple.mobilenotes.SharingExtension" }!
        let p = params(act)
        #expect(p["WFCreateNoteInput"] != nil)
        #expect(p["contents"] == nil)
        #expect((p["AppIntentDescriptor"] as? [String: String])?["AppIntentIdentifier"] == "CreateNoteLinkAction")
        // title and body are folded into `contents` by prepare(); only that key is read.
        let keys = a.compactMap { params($0)["WFDictionaryKey"] as? String }
        #expect(keys == ["contents"])
    }

    @Test func wiringReferencesExistingUUIDs() {
        for r in Catalog.all {
            let a = actions(r)
            let uuids = Set(a.compactMap { params($0)["UUID"] as? String })
            #expect(uuids.count == a.count, "\(r.alias): UUIDs unique")
            var refs: [String] = []
            func walk(_ v: Any) {
                if let d = v as? [String: Any] {
                    if let u = d["OutputUUID"] as? String { refs.append(u) }
                    d.values.forEach(walk)
                } else if let arr = v as? [Any] { arr.forEach(walk) }
            }
            a.forEach(walk)
            #expect(refs.allSatisfy(uuids.contains), "\(r.alias): every reference points at an action")
        }
    }

    @Test func deterministicBinaryPlist() throws {
        let d1 = try WrapperBuilder.data(Catalog.calendarCreateEvent)
        let d2 = try WrapperBuilder.data(Catalog.calendarCreateEvent)
        #expect(d1.prefix(6) == Data("bplist".utf8))
        // Same content every build (key order in the binary plist may differ).
        let back = try PropertyListSerialization.propertyList(from: d1, format: nil) as? [String: Any]
        let back2 = try PropertyListSerialization.propertyList(from: d2, format: nil) as? [String: Any]
        #expect((back as NSDictionary?)?.isEqual(to: back2 ?? [:]) == true)
        #expect(back?["WFWorkflowHasOutputAction"] as? Bool == true)
    }

    @Test func generatedRecipeFromMetadata() throws {
        let spec = ActionSpec(
            id: "com.apple.WritingTools.WritingToolsAppIntentsExtension.SummarizeTextIntent", alias: "writing-tools.summarize-text",
            intentIdentifier: "SummarizeTextIntent",
            app: AppRef(name: "Writing Tools", bundleID: "com.apple.WritingTools", version: nil, path: "/x", teamID: "0000000000"),
            source: SourceRef(bundleID: "com.apple.WritingTools.WritingToolsAppIntentsExtension", path: "/x", hostMapping: "self"),
            title: "Summarize Text", description: nil,
            parameters: [ParamSpec(name: "text", title: "Text", description: nil, optional: false, kind: .attributedString),
                         ParamSpec(name: "summaryType", title: "Type", description: nil, optional: true,
                                   kind: .enumeration(id: "SummaryIntentMode", cases: ["summarize", "createKeyPoints"]))],
            outputType: "string", supportedModes: ["background"], discoverable: true, opensApp: false, systemProtocols: [],
            risky: false, riskReasons: [], tier: .simple, tierReasons: [])
        let r = try #require(Catalog.generated(from: spec))
        #expect(r.verified == nil)
        #expect(r.actionIdentifier == "com.apple.WritingTools.WritingToolsAppIntentsExtension.SummarizeTextIntent")
        #expect(r.descriptor?["BundleIdentifier"] == "com.apple.WritingTools.WritingToolsAppIntentsExtension")
        #expect(r.inputs.map(\.plistKey) == ["text", "summaryType"])
        #expect(r.inputs[1].kind == .enumeration(["summarize", "createKeyPoints"]))
        var entity = spec
        entity.tier = .needsEntity
        #expect(Catalog.generated(from: entity) == nil)
    }
}

@Suite struct RunnerTests {
    @Test func rejectsUnknownMissingAndMistypedArguments() {
        let r = Catalog.remindersAdd
        #expect(throws: CallError.invalidArguments("unknown argument \"titel\"; expected due, notes, title")) {
            try Runner.validate(["titel": "x"], for: r)
        }
        #expect(throws: CallError.invalidArguments("\"title\" is required")) { try Runner.validate([:], for: r) }
        #expect(throws: CallError.invalidArguments("\"title\" has the wrong type")) { try Runner.validate(["title": 3], for: r) }
        #expect(throws: CallError.invalidArguments("\"title\" is empty")) { try Runner.validate(["title": "  "], for: r) }
        // Derived inputs are not arguments.
        #expect(throws: CallError.self) { try Runner.validate(["title": "x", "alert": "Alert"], for: r) }
        #expect(throws: Never.self) { try Runner.validate(["title": "x", "due": "tomorrow at 10:00"], for: r) }
    }

    @Test func wrapperInputDerivesAndFilters() {
        let withDue = Runner.wrapperInput(["title": "Dentist", "due": "tomorrow at 10:00"], for: Catalog.remindersAdd)
        #expect(withDue == ["title": "Dentist", "due": "tomorrow at 10:00", "alert": "Alert"])
        #expect(Runner.wrapperInput(["title": "Dentist"], for: Catalog.remindersAdd)["alert"] == "No Alert")
        #expect(Runner.wrapperInput(["title": "Shopping", "body": "milk"], for: Catalog.notesCreate)
                == ["contents": "Shopping\nmilk"])
    }

    @Test func libraryListingParses() {
        let listing = """
            intents-mcp reminders.add (F6E3EE8E-5E47-4A86-957B-AA7320753648)
            intents-mcp reminders.add 2 (10B4B703-45D5-4B51-9984-AC4B156D55E7)
            Morning (routine) (401EBFE4-127A-4B6A-9B42-F28F8B35E53E)
            intents-mcp reminders.address (266C7C20-EDA8-4129-A2AC-4EDDC7D27443)
            not a shortcut line
            """
        let e = Library.parse(listing)
        #expect(e.count == 4)
        #expect(e[2].name == "Morning (routine)")
        let m = Library.matching("intents-mcp reminders.add", in: e)
        #expect(m.map(\.uuid) == ["F6E3EE8E-5E47-4A86-957B-AA7320753648", "10B4B703-45D5-4B51-9984-AC4B156D55E7"])
    }
}

@Suite struct StoreTests {
    func tempStore() -> Store {
        Store(root: FileManager.default.temporaryDirectory.appendingPathComponent("imcp-store-\(UUID().uuidString)"))
    }

    @Test func toolsRoundTrip() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.root) }
        #expect(try s.tools().isEmpty)
        let t = EnabledTool(alias: "reminders.add", source: "catalog", actionID: nil, version: 1,
                            shortcutName: "intents-mcp reminders.add", shortcutUUID: nil,
                            enabledAt: Date(timeIntervalSince1970: 1_790_000_000), allowRisky: false)
        try s.upsert(t)
        var t2 = t
        t2.shortcutUUID = "F6E3EE8E-5E47-4A86-957B-AA7320753648"
        try s.upsert(t2)
        #expect(try s.tools() == [t2])
        #expect(try s.remove("reminders.add") == t2)
        #expect(try s.tools().isEmpty)
    }

    @Test func logIsAppendOnlyAndPrivate() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.root) }
        for i in 0..<3 {
            try s.append(LogEntry(tool: "t\(i)", time: Date(timeIntervalSince1970: 1_790_000_000 + Double(i)),
                                  durationMs: i, ok: i != 1, verified: nil, error: i == 1 ? "timeout" : nil, caller: "cli"))
        }
        #expect(try s.log(last: 2).map(\.tool) == ["t1", "t2"])
        let attrs = try FileManager.default.attributesOfItem(atPath: s.logFile.path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let line = try String(contentsOf: s.logFile, encoding: .utf8).split(separator: "\n")[0]
        #expect(Set((try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]).keys)
                == ["tool", "time", "durationMs", "ok", "caller"])  // nil fields omitted; no arguments/output
    }

    @Test func wrapperFileNameIsTheShortcutName() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let u = try s.wrapperURL(alias: "reminders.add", version: 1, signed: true)
        #expect(u.lastPathComponent == "intents-mcp reminders.add.shortcut")
        #expect(u.deletingPathExtension().lastPathComponent == Catalog.remindersAdd.shortcutName)
    }
}

@Suite struct ReadBackWrapperTests {
    @Test func helperTakesNewestWithoutFilter() {
        let a = WrapperBuilder_actions(ReadBackWrappers.plist(.event))
        let find = params(a[0])
        #expect(a[0]["WFWorkflowActionIdentifier"] as? String == "is.workflow.actions.filter.calendarevents")
        #expect(find["WFContentItemFilter"] == nil)
        let r = WrapperBuilder_actions(ReadBackWrappers.plist(.reminder))
        #expect(r.map { $0["WFWorkflowActionIdentifier"] as! String }.prefix(4) == ["is.workflow.actions.detect.dictionary",
            "is.workflow.actions.getvalueforkey", "is.workflow.actions.gettext", "is.workflow.actions.filter.reminders"])
        #expect(params(r[3])["WFContentItemFilter"] != nil)
        #expect(find["WFContentItemSortProperty"] as? String == "Creation Date")
        #expect(find["WFContentItemLimitNumber"] as? Int == 1)
        // The date attachment sits right after "\n<separator>\n".
        let text = (params(a[2])["WFTextActionText"] as! [String: Any])["Value"] as! [String: Any]
        let s = text["string"] as! String
        let ranges = (text["attachmentsByRange"] as! [String: Any]).keys.sorted()
        let second = Int(ranges.first { $0 != "{0, 1}" }!.dropFirst().split(separator: ",")[0])!
        #expect(Array(s.utf16)[second] == 0xFFFC)
        #expect(ReadBackWrappers.shortcutName(.event) == "intents-mcp verify.calendar")
        #expect(ReadBackWrappers.version(.reminder) == 2)
    }

    @Test func parsesHelperOutput() {
        let sep = ReadBackWrappers.separator
        #expect(ReadBackWrappers.parse("Call dentist\n\(sep)\n26 Sep 2026 at 10:00")! == ("Call dentist", "26 Sep 2026 at 10:00"))
        #expect(ReadBackWrappers.parse("Call dentist\n\(sep)")! == ("Call dentist", ""))
        #expect(ReadBackWrappers.parse("garbage") == nil)
    }
}

func WrapperBuilder_actions(_ plist: [String: Any]) -> [[String: Any]] { plist["WFWorkflowActions"] as! [[String: Any]] }
