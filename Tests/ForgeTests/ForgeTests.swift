import Core
import Foundation
@testable import IntentsIndex
@testable import Runner
@testable import ShortcutForge
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
        var unchecked = spec
        unchecked.id = "com.example.Other.SummarizeTextIntent"
        #expect(Catalog.generated(from: unchecked)?.verified == nil)
        let r = try #require(Catalog.generated(from: spec))
        #expect(r.verified != nil)  // checked on a real run, keyed by action id
        #expect(r.actionIdentifier == "com.apple.WritingTools.WritingToolsAppIntentsExtension.SummarizeTextIntent")
        #expect(r.descriptor?["BundleIdentifier"] == "com.apple.WritingTools.WritingToolsAppIntentsExtension")
        // Only required parameters are wired: an omitted optional one would be sent as empty text.
        #expect(r.inputs.map(\.plistKey) == ["text"])
        var entity = spec
        entity.tier = .needsEntity
        #expect(Catalog.generated(from: entity) == nil)
        var broken = spec
        broken.id = "com.apple.Notes.CreateFolderLinkAction"
        #expect(Catalog.generated(from: broken) == nil)  // known not to work
        #expect(Catalog.refusal(for: broken)?.hasPrefix("known not to work") == true)
        var noTeam = spec
        noTeam.app.teamID = nil
        #expect(Catalog.generated(from: noTeam) == nil)  // never guess Apple's Team ID
        var reserved = spec
        reserved.alias = "verify.reminders"
        #expect(Catalog.generated(from: reserved) == nil)  // helpers can't be replaced by metadata actions
        var allOptional = spec
        allOptional.id = "com.apple.Notes.CreateTagLinkAction"
        allOptional.parameters = [ParamSpec(name: "name", title: "Name", description: nil, optional: true, kind: .string)]
        #expect(Catalog.refusal(for: allOptional)?.contains("all optional") == true)
        #expect(Catalog.generated(from: spec)?.version == 2)  // v1 wrappers wired optional inputs too
        var ints = spec
        ints.id = "x.Y"
        ints.intentIdentifier = "Y"
        ints.parameters = [ParamSpec(name: "count", title: "Count", description: nil, optional: false, kind: .int)]
        #expect(Catalog.generated(from: ints)?.inputs.first?.kind == .integer)
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

    @Test func integersAndWhitespace() {
        var r = Catalog.notesCreate
        r.inputs.append(RecipeInput("n", "n", .integer))
        #expect(throws: CallError.invalidArguments("\"n\" must be a whole number")) { try Runner.validate(["title": "x", "n": 1.5], for: r) }
        #expect(throws: Never.self) { try Runner.validate(["title": "x", "n": 2], for: r) }
        #expect(throws: CallError.invalidArguments("\"title\" is empty")) { try Runner.validate(["title": "\n\t "], for: r) }
        // A whitespace-only due time means no due time, not a failed date conversion.
        #expect(Runner.wrapperInput(["title": "  Dentist ", "due": "   "], for: Catalog.remindersAdd)
                == ["title": "Dentist", "due": "today", "alert": "No Alert"])
    }

    @Test func datesWithOffsetsBecomeLocalTime() throws {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd HH:mm"
        let utc = ISO8601DateFormatter().date(from: "2026-10-01T16:30:00Z")!
        let expected = f.string(from: utc)
        for s in ["2026-10-01T09:30:00-07:00", "2026-10-01T09:30-07:00", "2026-10-01T16:30:00.000Z",
                  "2026-10-01 09:30 -07:00", "2026-10-01T09:30:00-0700"] {
            #expect(try Runner.normalizedDate(s) == expected, "\(s)")
        }
        #expect(try Runner.normalizedDate("tomorrow at 10:00") == "tomorrow at 10:00")
        #expect(try Runner.normalizedDate("2026-10-01 09:30") == "2026-10-01 09:30")
        #expect(throws: CallError.self) { try Runner.normalizedDate("09:30 on 1 Oct -07:00") }
        // A local date written as DD-MM-YYYY after a time is not an offset.
        #expect(try Runner.normalizedDate("10:00 on 01-10-2026") == "10:00 on 01-10-2026")
        #expect(Runner.wrapperInput(["title": "t", "start": "2026-10-01T09:30:00-07:00", "end": "2026-10-01T10:00:00-07:00"],
                                    for: Catalog.calendarCreateEvent)["start"] == .string(expected))
    }

    @Test func wrapperInputDerivesAndFilters() {
        let withDue = Runner.wrapperInput(["title": "Dentist", "due": "tomorrow at 10:00"], for: Catalog.remindersAdd)
        #expect(withDue == ["title": "Dentist", "due": "tomorrow at 10:00", "alert": "Alert"])
        let noDue = Runner.wrapperInput(["title": "Dentist"], for: Catalog.remindersAdd)
        #expect(noDue["alert"] == "No Alert")
        #expect(noDue["due"] == "today")  // placeholder: an empty time can't be converted to a date
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
        #expect(try s.remove("reminders.add") == [t2])
        #expect(try s.tools().isEmpty)
        // By action id too (enable accepts ids, so disable must).
        var g = t
        g.alias = "writing-tools.summarize"
        g.actionID = "com.apple.WritingTools.X.SummarizeTextIntent"
        try s.upsert(g)
        #expect(try s.remove("com.apple.WritingTools.X.SummarizeTextIntent").map(\.alias) == ["writing-tools.summarize"])
        #expect(try s.remove("nothing").isEmpty)
    }

    @Test func updateReadsFreshState() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.root) }
        let t = EnabledTool(alias: "a", source: "catalog", actionID: nil, version: 1, shortcutName: "intents-mcp a",
                            shortcutUUID: nil, enabledAt: Date(timeIntervalSince1970: 1_790_000_000), allowRisky: false)
        try s.upsert(t)
        _ = try s.remove("a")  // disabled meanwhile
        #expect(try s.update("a") { $0.shortcutUUID = "X" } == false)
        #expect(try s.tools().isEmpty)  // a stale snapshot must not bring it back
    }

    @Test func concurrentAppendsLoseNothing() throws {
        let s = tempStore()
        defer { try? FileManager.default.removeItem(at: s.root) }
        DispatchQueue.concurrentPerform(iterations: 200) { i in
            try? s.append(LogEntry(tool: "t\(i)", time: Date(), durationMs: i, ok: true, verified: nil, error: nil, caller: "cli"))
        }
        #expect(try s.log(last: 1000).count == 200)
        // One bad byte doesn't hide the rest.
        let h = try FileHandle(forWritingTo: s.logFile)
        try h.seekToEnd()
        try h.write(contentsOf: Data([0xFF, 0x0A]))
        try h.close()
        try s.append(LogEntry(tool: "after", time: Date(), durationMs: 0, ok: true, verified: nil, error: nil, caller: "cli"))
        #expect(try s.log(last: 1000).count == 201)
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
    @Test func helpersFilterByTitleAndReturnCreationDate() {
        for kind in [ReadBack.reminder, .event] {
            let a = WrapperBuilder_actions(ReadBackWrappers.plist(kind))
            let ids = a.map { $0["WFWorkflowActionIdentifier"] as! String }
            #expect(ids.first == "is.workflow.actions.detect.dictionary")
            let find = params(a[3])
            #expect(find["WFContentItemFilter"] != nil)  // v1 of the event helper had none
            #expect(find["WFContentItemLimitNumber"] as? Int == 1)
            #expect(ids.contains("is.workflow.actions.format.date"))
            let fmt = params(a.first { ($0["WFWorkflowActionIdentifier"] as! String) == "is.workflow.actions.format.date" }!)
            #expect(fmt["WFDateFormatStyle"] as? String == "ISO 8601")
            // Every attachment offset points at an object-replacement character.
            let text = (params(a[a.count - 2])["WFTextActionText"] as! [String: Any])["Value"] as! [String: Any]
            let chars = Array((text["string"] as! String).utf16)
            for k in (text["attachmentsByRange"] as! [String: Any]).keys {
                let at = Int(k.dropFirst().split(separator: ",")[0])!
                #expect(chars[at] == 0xFFFC)
            }
        }
        #expect(ReadBackWrappers.version(.reminder) == 3)
        #expect(ReadBackWrappers.version(.event) == 2)
    }

    @Test func parsesHelperOutput() {
        let m = ReadBackWrappers.marker
        func out(_ t: String, _ d: String, _ c: String) -> String { "\(t)\n\(m)D:\(d)\n\(m)C:\(c)\n" }
        #expect(ReadBackWrappers.parse(out("Call dentist", "26 Sep 2026 at 10:00", "2026-09-26T09:00:00+02:00"))
                == .init(title: "Call dentist", date: "26 Sep 2026 at 10:00", created: "2026-09-26T09:00:00+02:00"))
        #expect(ReadBackWrappers.parse(out("", "", ""))?.title == "")  // nothing found
        #expect(ReadBackWrappers.parse(String(out("", "", "").dropFirst()))?.title == "")  // leading newline stripped
        // Titles may contain the marker or end in \r: parsing is from the end.
        #expect(ReadBackWrappers.parse(out("a\n\(m)D:x", "d", "c"))?.title == "a\n\(m)D:x")
        #expect(ReadBackWrappers.parse(out("abc\r", "", "c"))?.title == "abc\r")
        #expect(ReadBackWrappers.parse("garbage") == nil)
    }

    @Test func verifiedOnlyForAnItemCreatedDuringTheCall() {
        let start = ISO8601DateFormatter().date(from: "2026-09-26T09:00:00Z")!
        func p(_ t: String, _ created: String) -> ReadBackWrappers.Parsed { .init(title: t, date: "26 Sep 2026 at 10:00", created: created) }
        #expect(Verifier.judge(p("Call mom", "2026-09-26T09:00:02Z"), kind: .reminder, title: "Call mom", since: start).verified == true)
        // An older reminder with the same title must never pass.
        let old = Verifier.judge(p("Call mom", "2026-09-20T08:00:00Z"), kind: .reminder, title: "Call mom", since: start)
        #expect(old.verified == false)
        // The previous same-kind call's item (created seconds before this run started) must not pass.
        #expect(Verifier.judge(p("Call mom", "2026-09-26T08:59:57Z"), kind: .reminder, title: "Call mom", since: start).verified == false)
        #expect(Verifier.judge(p("Call mom", "2026-09-26T08:59:59Z"), kind: .reminder, title: "Call mom", since: start).verified == true)  // ISO seconds rounding
        #expect(Verifier.judge(p("Other", "2026-09-26T09:00:02Z"), kind: .event, title: "Call mom", since: start).verified == false)
        #expect(Verifier.judge(p("", ""), kind: .reminder, title: "Call mom", since: start).detail.contains("was found"))
        #expect(Verifier.judge(p("Call mom", ""), kind: .reminder, title: "Call mom", since: start).verified == nil)
        #expect(Verifier.judge(nil, kind: .reminder, title: "x", since: start).verified == nil)
        // The other item's title is never echoed.
        #expect(!Verifier.judge(p("Private thing", "2026-09-26T09:00:02Z"), kind: .reminder, title: "x", since: start).detail.contains("Private"))
    }
}

func WrapperBuilder_actions(_ plist: [String: Any]) -> [[String: Any]] { plist["WFWorkflowActions"] as! [[String: Any]] }
