import Core
import Foundation
import IntentsIndex
import Runner
import ShortcutForge
import Store

public enum ToolError: Error, CustomStringConvertible {
    case unknown(String)
    case notSimple(String, [String])
    case risky(String, [String])
    case notEnabled(String)
    case pending(String)

    public var description: String {
        switch self {
        case .unknown(let a): return "no action named \"\(a)\" (see `intents-mcp list`)"
        case .notSimple(let a, let why):
            return "\(a) is not in the simple tier yet: \(why.joined(separator: "; "))"
        case .risky(let a, let why):
            return "\(a) looks risky (\(why.joined(separator: ", "))); enable it with --allow-risky if you are sure"
        case .notEnabled(let a): return "\(a) is not enabled; run `intents-mcp enable \(a)` first"
        case .pending(let a):
            return "\(a) is waiting for its shortcut: click Add Shortcut in Shortcuts, or run `intents-mcp enable \(a)` again"
        }
    }
}

public struct CallReport: Codable, Sendable, Equatable {
    public var tool: String
    public var ok: Bool
    public var output: String?
    public var error: String?
    public var verified: Bool?
    public var detail: String?
    public var durationMs: Int

    public init(tool: String, ok: Bool, output: String? = nil, error: String? = nil, verified: Bool? = nil,
                detail: String? = nil, durationMs: Int = 0) {
        self.tool = tool
        self.ok = ok
        self.output = output
        self.error = error
        self.verified = verified
        self.detail = detail
        self.durationMs = durationMs
    }
}

/// What the MCP server needs: the enabled tools and a way to call them. A protocol so the server
/// can be tested without running shortcuts.
public protocol ToolProvider: Sendable {
    func tools() -> [Recipe]
    func call(_ alias: String, args: [String: JSONValue], caller: String) async -> CallReport
}

/// Enabled tools from the local store; calls run the wrapper, read back, and log.
public struct ToolService: ToolProvider {
    public let store: Store
    public var timeout: Int

    public init(store: Store = Store(), timeout: Int = 30) {
        self.store = store
        self.timeout = timeout
    }

    /// Enabled agent tools (helpers excluded). Generated specs were saved at enable time, so no rescan.
    public func tools() -> [Recipe] {
        ((try? store.tools()) ?? []).filter { $0.source != "helper" }.compactMap { try? recipe(for: $0) }
    }

    public func recipe(for tool: EnabledTool) throws -> Recipe {
        if tool.source == "catalog", let r = Catalog.recipe(tool.alias) { return r }
        let spec = try JSONDecoder().decode(ActionSpec.self, from: Data(contentsOf: specURL(tool.alias, tool.version)))
        guard let r = Catalog.generated(from: spec) else { throw ToolError.notSimple(tool.alias, spec.tierReasons) }
        return r
    }

    public func specURL(_ alias: String, _ version: Int) throws -> URL {
        try store.wrapperURL(alias: alias, version: version, signed: true).deletingLastPathComponent()
            .appendingPathComponent("action.json")
    }

    /// Runs one enabled tool, reads the result back where possible, and logs the call
    /// (tool, time, duration, ok, verified, error category; never arguments or output).
    public func call(_ alias: String, args: [String: JSONValue], caller: String) async -> CallReport {
        await call(alias, args: args, caller: caller, verify: true)
    }

    public func call(_ alias: String, args: [String: JSONValue], caller: String, verify: Bool) async -> CallReport {
        let started = Date()
        var report = CallReport(tool: alias, ok: false)
        var category: String?
        do {
            let all = try store.tools()
            guard var tool = all.first(where: { $0.alias == alias && $0.source != "helper" }) else {
                throw ToolError.notEnabled(alias)
            }
            let r = try recipe(for: tool)
            if tool.shortcutUUID == nil {
                // Pending since enable: adopt the shortcut if exactly one with this name exists.
                let found = Library.entries().map { Library.matching(tool.shortcutName, in: $0) } ?? []
                guard found.count == 1 else { throw ToolError.pending(alias) }
                tool.shortcutUUID = found[0].uuid
                try store.upsert(tool)
            }
            let out = try Runner.call(r, uuid: tool.shortcutUUID!, args: args, timeout: timeout)
            report.ok = true
            report.output = out.text
            if verify {
                let helper = r.readBack.flatMap { k in all.first { $0.alias == ReadBackWrappers.alias(k) }?.shortcutUUID }
                let v = await Verifier.verify(r.readBack, args: args, since: started, helperUUID: helper)
                report.verified = v.verified
                report.detail = v.detail
            }
        } catch let e as CallError {
            report.error = e.description
            category = e.category
        } catch {
            report.error = "\(error)"
            category = "setup"
        }
        report.durationMs = Int(Date().timeIntervalSince(started) * 1000)
        try? store.append(LogEntry(tool: alias, time: started, durationMs: report.durationMs, ok: report.ok,
                                   verified: report.verified, error: category, caller: caller))
        return report
    }
}
