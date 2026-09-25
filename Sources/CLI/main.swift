import Foundation
import IntentsIndex

let version = "0.1.0-dev"

let usage = """
    intents-mcp \(version): App Intents on your Mac as MCP tools. Runs on your Mac; public APIs only.

    usage:
      intents-mcp census [--json]                  count the actions this Mac declares
      intents-mcp list [--app <name>] [--tier simple|entity|unsupported|all] [--json]
      intents-mcp doctor [--json]                  check this Mac is ready
      intents-mcp enable | disable | serve | log   (not built yet)
      intents-mcp --version

    """

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
                if ["app", "tier"].contains(name) {
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
    }
}

enum CLIError: Error {
    case usage(String)
}

func printJSON<T: Encodable>(_ value: T) {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = (try? e.encode(value)) ?? Data("null".utf8)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func grouped(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_US")
    return f.string(from: NSNumber(value: n)) ?? String(n)
}

func census(_ args: Args) {
    let index = ActionIndex.scan()
    let c = Census(index)
    if args.flags.contains("json") { return printJSON(c) }
    let t = c.byTier
    print("""
        This Mac declares \(grouped(c.declaredActions)) App Intents actions (\(grouped(c.uniqueActions)) unique) \
        in \(c.metadataFiles) metadata files, across \(c.apps) apps and system components.

          discoverable in Shortcuts          \(grouped(c.discoverable))
          simple tier                        \(grouped(t["simple"] ?? 0))   background, plain inputs, returns output
          need an entity (a note, a list…)   \(grouped(t["entity"] ?? 0))   not supported yet
          other                              \(grouped(t["unsupported"] ?? 0))   hidden, opens the app, no output, files…
          flagged risky                      \(grouped(c.risky))   delete / send / buy / share; off unless allowed

          third-party apps: \(c.thirdParty.apps) apps, \(c.thirdParty.actions) actions \
        (\(c.thirdParty.discoverable) discoverable, \(c.thirdParty.simple) simple)

        Most actions:
        """)
    for a in c.topApps {
        print("  \(a.app.padding(toLength: 34, withPad: " ", startingAt: 0)) \(String(a.actions).leftPad(4))   simple \(a.simple)")
    }
    print("""

        These counts come from the metadata apps ship. Declared is not the same as usable: some \
        declared actions are refused by Shortcuts on the Mac, and Reminders and Calendar work \
        through built-in Shortcuts actions that are not counted here.
        """)
    for e in index.errors { FileHandle.standardError.write(Data("warning: \(e)\n".utf8)) }
}

func list(_ args: Args) throws {
    let index = ActionIndex.scan()
    var xs = index.actions
    let tier = args.options["tier"] ?? "all"
    if tier != "all" {
        guard let t = Tier(rawValue: tier) else { throw CLIError.usage("--tier must be simple, entity, unsupported or all") }
        xs = xs.filter { $0.tier == t }
    }
    if let app = args.options["app"]?.lowercased() {
        xs = xs.filter { $0.app.name.lowercased() == app || $0.app.bundleID.lowercased() == app }
    }
    xs.sort { ($0.app.name, $0.alias) < ($1.app.name, $1.alias) }
    if args.flags.contains("json") { return printJSON(xs) }
    for a in xs {
        let mark = a.risky ? " [risky]" : ""
        let params = a.parameters.map { "\($0.name)\($0.optional ? "?" : ""):\($0.kind.label)" }.joined(separator: ", ")
        let out = a.outputType.map { " -> \($0)" } ?? ""
        print("\(a.alias)  (\(a.tier.rawValue))\(mark)")
        print("    \(a.title)(\(params))\(out)")
        if !a.tierReasons.isEmpty { print("    why not simple: \(a.tierReasons.joined(separator: "; "))") }
    }
    FileHandle.standardError.write(Data("\(xs.count) actions\n".utf8))
}

extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}

do {
    let args = try Args(Array(CommandLine.arguments.dropFirst()))
    if args.flags.contains("version") { print(version); exit(0) }
    switch args.command {
    case "census": census(args)
    case "list": try list(args)
    case "debug-files":  // development aid: the metadata files the scan finds
        for f in ActionIndex.findMetadataFiles() { print(f.path) }
    case "doctor": exit(Doctor.run(json: args.flags.contains("json")))
    case "enable", "disable", "log": FileHandle.standardError.write(Data("not built yet (M2)\n".utf8)); exit(2)
    case "serve": FileHandle.standardError.write(Data("not built yet (M3)\n".utf8)); exit(2)
    case nil, "help": print(usage, terminator: "")
    case let c?: throw CLIError.usage("unknown command: \(c)")
    }
} catch CLIError.usage(let m) {
    FileHandle.standardError.write(Data("error: \(m)\n\n\(usage)".utf8))
    exit(64)
}
