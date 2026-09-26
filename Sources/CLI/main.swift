import Core
import Foundation
import IntentsIndex
import MCPServer
import Runner
import ShortcutForge
import Store

let version = IntentsMCPVersion.current

let usage = """
    intents-mcp \(version): App Intents on your Mac as MCP tools. Runs on your Mac; public APIs only.

    usage:
      intents-mcp census [--json]                  count the actions this Mac declares
      intents-mcp list [--app <name>] [--tier simple|entity|unsupported|all] [--json]
      intents-mcp enable <tool>... [--allow-risky] [--no-wait] [--dry-run]
                                                   make actions available to agents
      intents-mcp disable <tool>...                stop exposing them (alias or action id)
      intents-mcp call <tool> '<json args>' [--timeout <s>] [--no-verify]
                                                   run an enabled tool, as an agent would
      intents-mcp tools [--json]                   the enabled tools
      intents-mcp log [--last <n>] [--json]        what was called (no personal content)
      intents-mcp doctor [--json]                  check this Mac is ready
      intents-mcp serve [--timeout <s>]            MCP over stdio for Claude Code, Codex, …
                                                   (claude mcp add --scope user mac -- intents-mcp serve)
      intents-mcp --version

    """

/// Flags and options each command accepts; anything else is a usage error, so a typo such as
/// `--dryrun` can never fall through to a real sign-and-import.
let accepted: [String: (flags: Set<String>, options: Set<String>)] = [
    "census": (["json"], []),
    "list": (["json"], ["app", "tier"]),
    "enable": (["allow-risky", "allow-destructive", "no-wait", "dry-run"], []),
    "disable": ([], []),
    "call": (["no-verify"], ["timeout"]),
    "tools": (["json"], []),
    "log": (["json"], ["last"]),
    "doctor": (["json"], []),
    "serve": ([], ["timeout"]),
    "debug-files": ([], []),
    "help": ([], []),
]

struct Args {
    var command: String?
    var flags: Set<String> = []
    var options: [String: String] = [:]
    var positional: [String] = []

    init(_ argv: [String]) throws {
        var it = argv.makeIterator()
        while let a = it.next() {
            if a.hasPrefix("--") {
                let name = String(a.dropFirst(2))
                if ["app", "tier", "timeout", "last"].contains(name) {
                    guard let v = it.next() else { throw CLIError.usage("--\(name) needs a value") }
                    options[name] = v
                } else {
                    flags.insert(name)
                }
            } else if command == nil {
                command = a
            } else {
                positional.append(a)
            }
        }
        if flags.contains("version") || flags.contains("help") { return }
        if let c = command, let ok = accepted[c] {
            if let bad = flags.subtracting(ok.flags).sorted().first { throw CLIError.usage("unknown flag --\(bad) for \(c)") }
            if let bad = Set(options.keys).subtracting(ok.options).sorted().first {
                throw CLIError.usage("unknown option --\(bad) for \(c)")
            }
        }
    }

    /// A positive whole number option, or the default.
    func positive(_ name: String, default d: Int) throws -> Int {
        guard let v = options[name] else { return d }
        guard let n = Int(v), n > 0 else { throw CLIError.usage("--\(name) must be a positive whole number") }
        return n
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case failure(String)

    var description: String {
        switch self {
        case .usage(let m), .failure(let m): return m
        }
    }
}

func printJSON<T: Encodable>(_ value: T) {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    e.dateEncodingStrategy = .iso8601
    let data = (try? e.encode(value)) ?? Data("null".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

/// SIGINT/SIGTERM/SIGHUP (Ctrl-C, a client quitting): log the calls still running as interrupted,
/// stop their `shortcuts` children, remove temporary files, then exit.
func installSignalHandlers() {
    for sig in [SIGINT, SIGTERM, SIGHUP] {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
        src.setEventHandler {
            guard shuttingDown.claim() else { return }  // SIGINT then SIGTERM: run once
            TempDir.removeAll()  // first: a SIGKILL may follow soon (arguments must not stay on disk)
            InFlight.shared.logInterrupted()
            Shell.stopAll()
            TempDir.removeAll()
            exit(128 + sig)
        }
        src.resume()
        signalSources.append(src)
    }
}
nonisolated(unsafe) var signalSources: [DispatchSourceSignal] = []
let shuttingDown = Once()

final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
}

/// The product needs macOS 26 (Shortcuts signing, App Intents metadata); fail clearly elsewhere.
func requireMacOS26() throws {
    let v = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    guard v >= 26 else { throw CLIError.failure("intents-mcp needs macOS 26 or later (this Mac runs \(v))") }
}

func grouped(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    return f.string(from: NSNumber(value: n)) ?? String(n)
}

func census(_ args: Args) {
    let index = Progress.run("Scanning App Intents metadata (about 10 s)…") { ActionIndex.scan(reserved: Catalog.reservedAliases) }
    let c = Census(index)
    if args.flags.contains("json") { return printJSON(c) }
    let t = c.byTier
    // Fits an 80-column terminal, so no line breaks mid-word as it appears line by line.
    let rows = [
        ("discoverable in Shortcuts", c.discoverable, ""),
        ("simple tier", t["simple"] ?? 0, "background, plain inputs, returns output"),
        ("need an entity (a note…)", t["entity"] ?? 0, "not supported yet"),
        ("other", t["unsupported"] ?? 0, "hidden, opens the app, no output, files…"),
        ("flagged risky", c.risky, "delete, send, buy, share; off unless allowed"),
    ]
    let labelWidth = rows.map(\.0.count).max()! + 2
    let numberWidth = rows.map { grouped($0.1).count }.max()!
    var lines = [
        "This Mac declares \(grouped(c.declaredActions)) App Intents actions (\(grouped(c.uniqueActions)) unique)",
        "in \(c.metadataFiles) metadata files, across \(c.apps) apps and system components.",
        "",
    ]
    lines += rows.map { label, n, note in
        "  \(label.padding(toLength: labelWidth, withPad: " ", startingAt: 0))\(grouped(n).leftPad(numberWidth))"
            + (note.isEmpty ? "" : "  \(note)")
    }
    lines += [
        "",
        "  third-party apps: \(c.thirdParty.apps) apps, \(c.thirdParty.actions) actions "
            + "(\(c.thirdParty.discoverable) discoverable, \(c.thirdParty.simple) simple)",
        "",
        "Most actions:",
    ]
    lines += c.topApps.map { a in
        "  \(a.app.padding(toLength: 34, withPad: " ", startingAt: 0)) \(String(a.actions).leftPad(4))   simple \(a.simple)"
    }
    lines += [
        "",
        "These counts come from the metadata apps ship. Declared is not the same as",
        "usable: some declared actions are refused by Shortcuts on the Mac, and",
        "Reminders and Calendar work through built-in Shortcuts actions that are not",
        "counted here.",
    ]
    Out.block(lines)
    for e in index.errors { FileHandle.standardError.write(Data("warning: \(e)\n".utf8)) }
}

func callCommand(_ args: Args) async throws -> Int32 {
    guard let alias = args.positional.first else { throw CLIError.usage("call needs a tool name") }
    var callArgs: [String: JSONValue] = [:]
    if args.positional.count > 1 {
        guard case .object(let o)? = try? JSONDecoder().decode(JSONValue.self, from: Data(args.positional[1].utf8)) else {
            throw CLIError.usage("arguments must be a JSON object, e.g. '{\"title\": \"Call the dentist\"}'")
        }
        callArgs = o
    }
    let timeout = try args.positive("timeout", default: 30)
    guard (20...600).contains(timeout) else { throw CLIError.usage("--timeout must be 20 to 600 seconds") }
    installSignalHandlers()
    let report = await Tools.call(alias, args: callArgs, caller: "cli", timeout: timeout, verify: !args.flags.contains("no-verify"))
    // If a signal handler already took over (Ctrl-C), let it finish and exit; don't race it.
    guard shuttingDown.claim() else { while true { sleep(60) } }
    printJSON(report)
    return report.ok ? 0 : 1
}

func toolsCommand(_ args: Args) throws {
    let tools = try Tools.store.tools()
    if args.flags.contains("json") { return printJSON(tools) }
    if tools.isEmpty { Out.line("No tools enabled. Try `intents-mcp enable reminders.add`."); return }
    var lines: [String] = []
    for t in tools {
        let kind = t.source == "helper" ? "read-back helper (not an agent tool)" : t.source
        let key = Tools.enableKey(t.alias, actionID: t.actionID)
        var state = t.shortcutUUID == nil ? "pending (click Add Shortcut, then run `intents-mcp enable \(key)`)" : "ready"
        if t.source == "helper", !Tools.helperInUse(t.alias, among: tools) {
            state = "unused: run `intents-mcp disable \(t.alias)` and delete its shortcut"
        } else if let k = ReadBackWrappers.kind(forAlias: t.alias), t.version != ReadBackWrappers.version(k) {
            state = "outdated: run `intents-mcp enable \(key)`"
        } else if t.source != "helper" {
            switch Result(catching: { try Tools.service.recipe(for: t) }) {
            case .success(let r) where r.version != t.version: state = "outdated: run `intents-mcp enable \(key)`"
            case .failure: state = "not usable any more (see `intents-mcp doctor`)"
            default: break
            }
        }
        lines.append("\(t.alias)  \(state)  \(kind)\(t.allowRisky ? "  risky allowed" : "")")
    }
    Out.block(lines)
}

func logCommand(_ args: Args) throws {
    let all = try Tools.store.log(last: .max)
    // A "start" line with no matching "end": still running if recent, otherwise interrupted
    // (the action may still have run).
    let ended = Set(all.filter { $0.event != "start" }.compactMap(\.callID))
    var entries = all.filter { e in e.event != "start" || !ended.contains(e.callID ?? "") }.map { e -> LogEntry in
        guard e.event == "start" else { return e }
        var x = e
        x.error = Date().timeIntervalSince(e.time) < 900 ? "running (no result yet)"
            : "no end recorded: interrupted? (the action may still have run)"
        return x
    }
    entries = Array(entries.suffix(try args.positive("last", default: 50)))
    if FileManager.default.fileExists(atPath: Tools.store.logFile.path), !FileManager.default.isWritableFile(atPath: Tools.store.logFile.path) {
        FileHandle.standardError.write(Data("warning: \(Tools.store.logFile.path) is not writable: new calls are not being logged\n".utf8))
    }
    if args.flags.contains("json") { return printJSON(entries) }
    let f = ISO8601DateFormatter()
    var lines: [String] = []
    for e in entries {
        let v = e.verified.map { $0 ? "verified" : "NOT verified" } ?? "unverified"
        if e.event == "start" {
            lines.append("\(f.string(from: e.time))  \(e.tool.padding(toLength: max(24, e.tool.count), withPad: " ", startingAt: 0)) \(e.error ?? "")  \(e.caller)")
            continue
        }
        lines.append("\(f.string(from: e.time))  \(e.tool.padding(toLength: max(24, e.tool.count), withPad: " ", startingAt: 0)) \(e.ok ? "ok   " : "error") \(String(e.durationMs).leftPad(6)) ms  \(v)\(e.error.map { "  (\($0))" } ?? "")  \(e.caller)")
    }
    Out.block(lines)
}

func list(_ args: Args) throws {
    let index = Progress.run("Scanning App Intents metadata (about 10 s)…") { ActionIndex.scan(reserved: Catalog.reservedAliases) }
    var xs = index.actions
    let tier = args.options["tier"] ?? "all"
    if tier != "all" {
        guard let t = Tier(rawValue: tier) else { throw CLIError.usage("--tier must be simple, entity, unsupported or all") }
        xs = xs.filter { $0.tier == t }
    }
    let appFilter = args.options["app"]?.lowercased()
    if let app = appFilter {
        xs = xs.filter { [$0.app.name, $0.app.shownName, $0.app.bundleID].map { $0.lowercased() }.contains(app) }
    }
    xs.sort { ($0.app.shownName, $0.alias) < ($1.app.shownName, $1.alias) }
    for i in xs.indices {
        if let why = Catalog.knownBroken[xs[i].id] { xs[i].status = "known-broken: \(why)" }
        else if let how = Catalog.checkedGenerated[xs[i].id] { xs[i].status = "checked: \(how)" }
    }
    if args.flags.contains("json") { return printJSON(xs) }
    var lines: [String] = []
    // Checked tools first: they are known to work (Reminders and Calendar are built-in Shortcuts
    // actions, so they are not in the metadata list below).
    let checked = Catalog.all.filter { r in
        guard let app = appFilter else { return true }
        return r.appName.lowercased() == app || index.actions.contains { $0.app.bundleID.lowercased() == app && $0.app.name == r.appName }
    }
    let checkedGenerated = xs.filter { Catalog.checkedGenerated[$0.id] != nil }
    if tier == "all" || tier == "simple", !(checked.isEmpty && checkedGenerated.isEmpty) {
        lines.append("Checked on a real run (recommended):")
        for r in checked {
            let params = r.exposedInputs.map { "\($0.name)\($0.required ? "" : "?")" }.joined(separator: ", ")
            lines.append("  \(r.alias)  \(r.title)(\(params))")
        }
        for a in checkedGenerated {
            lines.append("  \(a.alias)  \(a.title)(\(a.parameters.filter { !$0.optional }.map(\.name).joined(separator: ", ")))")
        }
        lines.append("\nFrom app metadata (not yet checked; try one with `intents-mcp call` before relying on it):")
    }
    for a in xs where Catalog.checkedGenerated[a.id] == nil {
        if let why = Catalog.knownBroken[a.id] {
            lines.append("\(a.alias)  (known not to work)")
            lines.append("    \(why)")
            continue
        }
        let mark = a.risky ? " [risky]" : ""
        let params = a.parameters.map { "\($0.name)\($0.optional ? "?" : ""):\($0.kind.label)" }.joined(separator: ", ")
        let out = a.outputType.map { " -> \($0)" } ?? ""
        lines.append("\(a.alias)  (\(a.tier.rawValue))\(mark)")
        lines.append("    \(a.title)(\(params))\(out)")
        if !a.tierReasons.isEmpty { lines.append("    why not simple: \(a.tierReasons.joined(separator: "; "))") }
        if a.tier == .simple {
            if let why = Catalog.refusal(for: a) {
                lines.append("    can't be a tool yet: \(why)")
            } else if a.parameters.contains(where: \.optional) {
                lines.append("    as a tool: only the required inputs are passed (optional ones aren't offered yet)")
            }
        }
    }
    Out.block(lines)
    FileHandle.standardError.write(Data("\(xs.count) actions\n".utf8))
}

extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}

do {
    let args = try Args(Array(CommandLine.arguments.dropFirst()))
    if args.flags.contains("version") { print(version); exit(0) }
    if args.flags.contains("help") { print(usage, terminator: ""); exit(0) }
    // Human-facing output appears line by line even through a pipe (enable waits minutes for clicks).
    if args.command != "serve" { setvbuf(stdout, nil, _IOLBF, 0) }
    switch args.command {
    case "census": census(args)
    case "list": try list(args)
    case "debug-files":  // development aid: the metadata files the scan finds
        for f in ActionIndex.findMetadataFiles() { print(f.path) }
    case "doctor": exit(await Doctor.run(json: args.flags.contains("json")))
    case "enable":
        try requireMacOS26()
        let done = try await Tools.enable(args.positional,
                                          allowRisky: args.flags.contains("allow-risky") || args.flags.contains("allow-destructive"),
                                          wait: !args.flags.contains("no-wait"), dryRun: args.flags.contains("dry-run"))
        if !done { exit(3) }
    case "disable": try await Tools.disable(args.positional)
    case "call":
        try requireMacOS26()
        exit(try await callCommand(args))
    case "tools": try toolsCommand(args)
    case "log": try logCommand(args)
    case "serve":
        // stdout is the JSON-RPC channel: nothing else may be printed there.
        let timeout = try args.positive("timeout", default: 50)
        guard (20...600).contains(timeout) else { throw CLIError.usage("--timeout must be 20 to 600 seconds") }
        try requireMacOS26()
        installSignalHandlers()
        await Tools.service.adoptPendingAll()
        Tools.store.removeSignedWrappersOfAddedTools()
        await MCPServer.serveStdio(provider: ToolService(store: Tools.store, timeout: timeout))
    case nil, "help": print(usage, terminator: "")
    case let c?: throw CLIError.usage("unknown command: \(c)")
    }
} catch CLIError.usage(let m) {
    FileHandle.standardError.write(Data("error: \(m)\n\n\(usage)".utf8))
    exit(64)
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
