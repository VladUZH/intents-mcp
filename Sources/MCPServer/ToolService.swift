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
    case pending(String, copies: Int)
    case outdated(String)

    public var description: String {
        switch self {
        case .unknown(let a): return "no action named \"\(a)\" (see `intents-mcp list`)"
        case .notSimple(let a, let why):
            return "\(a) can't be a tool: \(why.joined(separator: "; "))"
        case .risky(let a, let why):
            return "\(a) looks risky (\(why.joined(separator: ", "))); enable it with --allow-risky if you are sure"
        case .notEnabled(let a) where ReadBackWrappers.aliases.contains(a):
            return "\(a) is a read-back helper, not a tool agents can call"
        case .notEnabled(let a): return "\(a) is not enabled; run `intents-mcp enable \(a)` first"
        case .pending(let a, let copies) where copies > 1:
            return "\(a) is waiting for its shortcut, and Shortcuts has \(copies) copies with its name; delete the ones you don't use (keep any that intents-mcp on another Mac with your iCloud account uses), then run `intents-mcp enable \(a)`"
        case .pending(let a, _):
            return "\(a) is waiting for its shortcut: click Add Shortcut in Shortcuts, then call it again"
        case .outdated(let a):
            return "\(a)'s wrapper shortcut is from an older intents-mcp; run `intents-mcp enable \(a)` to update it"
        }
    }
}

public struct CallReport: Codable, Sendable, Equatable {
    public var tool: String
    public var ok: Bool
    public var output: String?
    public var error: String?
    /// true when a failed call may still have taken effect (timeout, no result, cancelled).
    public var outcomeUnknown: Bool?
    public var verified: Bool?
    public var detail: String?
    public var durationMs: Int
    /// Set when the call could not be logged (the log must never be missing a call silently).
    public var logWarning: String?

    public init(tool: String, ok: Bool, output: String? = nil, error: String? = nil, outcomeUnknown: Bool? = nil,
                verified: Bool? = nil, detail: String? = nil, durationMs: Int = 0) {
        self.tool = tool
        self.ok = ok
        self.output = output
        self.error = error
        self.outcomeUnknown = outcomeUnknown
        self.verified = verified
        self.detail = detail
        self.durationMs = durationMs
    }
}

/// What the MCP server needs: the enabled tools and a way to call them. A protocol so the server
/// can be tested without running shortcuts.
public protocol ToolProvider: Sendable {
    func tools() -> [Recipe]
    func call(_ alias: String, args: [String: JSONValue], caller: String, cancel: CancelToken?) async -> CallReport
    /// Logs a call for a tool name that isn't enabled (never the name itself: it's client input).
    func logRejected(caller: String)
}

public extension ToolProvider {
    func logRejected(caller: String) {}
}

/// Enabled tools from the local store; calls run the wrapper, read back, and log.
public struct ToolService: ToolProvider {
    public let store: Store
    /// Budget for a whole call (run + read-back). Claude Desktop and Codex give up after 60 s.
    public var timeout: Int

    public init(store: Store = Store(), timeout: Int = 50) {
        self.store = store
        self.timeout = timeout
    }

    /// Enabled agent tools (helpers excluded). Generated specs were saved at enable time, so no rescan.
    public func tools() -> [Recipe] {
        do {
            return try store.tools().filter { $0.source != "helper" }.compactMap { t in
                guard let r = try? recipe(for: t), r.version == t.version else { return nil }
                return r
            }
        } catch {
            Warned.once("tools.json", "intents-mcp: no tools offered: \(error)")
            return []
        }
    }

    public func recipe(for tool: EnabledTool) throws -> Recipe {
        if tool.source == "catalog", let r = Catalog.recipe(tool.alias) { return r }
        let spec = try JSONDecoder().decode(ActionSpec.self, from: Data(contentsOf: specURL(tool.alias, tool.version)))
        guard let r = Catalog.generated(from: spec) else {
            throw ToolError.notSimple(tool.alias, [Catalog.refusal(for: spec) ?? "not in the simple tier"])
        }
        return r
    }

    public func specURL(_ alias: String, _ version: Int) throws -> URL {
        try store.wrapperURL(alias: alias, version: version, signed: true).deletingLastPathComponent()
            .appendingPathComponent("action.json")
    }

    /// The enabled tool for an alias or an action id.
    public func enabledTool(_ key: String, in all: [EnabledTool]) -> EnabledTool? {
        all.first { ($0.alias == key || ($0.actionID != nil && $0.actionID == key)) && $0.source != "helper" }
    }

    /// A pending entry (no UUID yet) takes the shortcut the user added, if exactly one shortcut has its
    /// name; the store is re-read before writing. Returns the UUID, or nil if still pending.
    public func adopt(_ t: EnabledTool, library: [Library.Entry]?) throws -> String? {
        if let u = t.shortcutUUID { return u }
        guard let library else { return nil }
        let stale = Set(t.staleUUIDs ?? [])
        let found = Library.matching(t.shortcutName, in: library).filter { !stale.contains($0.uuid) }
        guard found.count == 1 else { return nil }
        let uuid = found[0].uuid
        let still = try store.update(t.alias) { e in if e.shortcutUUID == nil { e.shortcutUUID = uuid } }
        if still { store.removeSignedWrapper(alias: t.alias, version: t.version) }
        return still ? uuid : nil
    }

    /// Adopts every pending tool and helper whose shortcut the user has added since (this also
    /// deletes their signed files). Returns how many were adopted.
    @discardableResult
    public func adoptPendingAll() async -> Int {
        guard let pending = try? store.tools().filter({ $0.shortcutUUID == nil }), !pending.isEmpty,
              let library = await Library.entries(timeout: 10) else { return 0 }
        var n = 0
        for t in pending where (try? adopt(t, library: library)) != nil { n += 1 }
        return n
    }

    public func logRejected(caller: String) {
        appendLog(LogEntry(tool: "<unknown>", time: Date(), durationMs: 0, ok: false, verified: nil,
                           error: "unknown-tool", caller: caller))
    }

    public func call(_ alias: String, args: [String: JSONValue], caller: String, cancel: CancelToken?) async -> CallReport {
        await call(alias, args: args, caller: caller, verify: true, cancel: cancel)
    }

    /// Runs one enabled tool, reads the result back where possible, and logs the call
    /// (tool, time, duration, ok, verified, error category; never arguments or output).
    /// `timeout` is the budget for the whole call, including waiting for other calls.
    public func call(_ alias: String, args: [String: JSONValue], caller: String, verify: Bool,
                     cancel: CancelToken? = nil) async -> CallReport {
        let started = Date()
        let deadline = started.addingTimeInterval(TimeInterval(timeout))
        func remaining() -> Int { max(0, Int(deadline.timeIntervalSinceNow.rounded(.down))) }
        let callID = UUID().uuidString
        var report = CallReport(tool: alias, ok: false)
        var category: String?
        var logName = "<unknown>"
        do {
            let all = try store.tools()
            guard var tool = enabledTool(alias, in: all) else { throw ToolError.notEnabled(alias) }
            logName = tool.alias
            report.tool = tool.alias
            let r = try recipe(for: tool)
            if tool.version != r.version { throw ToolError.outdated(tool.actionID ?? tool.alias) }
            var helper = r.readBack.flatMap { k in all.first { $0.alias == ReadBackWrappers.alias(k) } }
            var helperNote: String?
            if let k = r.readBack, let h = helper, h.version != ReadBackWrappers.version(k) {
                helper = nil  // an older helper returns a format this version can't read
                helperNote = "not verified: the read-back helper is from an older intents-mcp; run `intents-mcp enable \(ReadBackWrappers.owner(k))` to add the new one"
            }

            // Record the start first: if the process dies mid-call, the log still shows the attempt.
            if !appendLog(LogEntry(tool: tool.alias, time: started, durationMs: 0, ok: false, verified: nil, error: nil,
                                   caller: caller, callID: callID, event: "start")) {
                report.logWarning = "this call could not be written to the local log (run `intents-mcp doctor`)"
            }
            InFlight.shared.begin(callID, tool: tool.alias, caller: caller, started: started, store: store)
            defer { InFlight.shared.end(callID) }

            var helperUUID = helper?.shortcutUUID
            if tool.shortcutUUID == nil || (helper != nil && helperUUID == nil) {
                let library = await Library.entries(timeout: TimeInterval(max(1, min(15, remaining()))))
                if tool.shortcutUUID == nil {
                    guard let u = try adopt(tool, library: library) else {
                        throw ToolError.pending(tool.alias, copies: library.map { Library.matching(tool.shortcutName, in: $0).count } ?? 0)
                    }
                    tool.shortcutUUID = u
                }
                if let h = helper, helperUUID == nil { helperUUID = try adopt(h, library: library) }
            }

            let uuid = tool.shortcutUUID!
            let helperID = helperUUID
            let note = helperNote
            // A started wrapper always gets at least ~8 s (a cold run takes ~6 s), plus the read-back reserve.
            let minRun = r.readBack != nil && verify ? 20 : 8
            let budget = timeout
            let work: @Sendable () async -> Outcome = {
                func left() -> Int { max(0, Int(deadline.timeIntervalSinceNow.rounded(.down))) }
                var o = Outcome()
                // Queued calls re-check before starting: never start after a cancel, during shutdown, or
                // with no time left.
                if cancel?.isCancelled == true { o.error = .notStarted("cancelled while waiting for another call"); return o }
                if Shell.isShuttingDown { o.error = .notStarted("intents-mcp is shutting down"); return o }
                guard left() >= minRun else {
                    o.error = .notStarted(budget < minRun
                        ? "the call timeout (\(budget) s) is shorter than this tool needs (\(minRun) s); raise --timeout"
                        : "no time left after waiting for other calls")
                    return o
                }
                let runStart = Date()  // read-back only accepts items created from here on
                let readBackReserve = (verify && r.readBack != nil) ? 12 : 0
                do {
                    let out = try await Runner.call(r, uuid: uuid, args: args, timeout: max(1, left() - readBackReserve),
                                                    cancel: cancel)
                    let text = out.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    o.ok = true
                    o.output = text
                    if verify, r.readBack != nil {
                        let v = await Verifier.verify(r.readBack, args: args, since: runStart, helperUUID: helperID,
                                                      timeout: max(1, min(20, left())), cancel: cancel)
                        o.verified = v.verified
                        o.detail = (v.verified == nil && note != nil) ? note : v.detail
                    } else if text.isEmpty {
                        o.detail = "the shortcut returned no output, so the result couldn't be confirmed"
                    }
                } catch let e as CallError {
                    o.error = e
                    // The action may still have happened: look before reporting a failure.
                    if e.outcomeUnknown, e != .cancelled, verify, r.readBack != nil, left() >= 3 {
                        let v = await Verifier.verify(r.readBack, args: args, since: runStart, helperUUID: helperID,
                                                      timeout: min(10, left()), cancel: cancel)
                        if v.verified == true {
                            o.ok = true
                            o.error = nil
                            o.verified = true
                            o.detail = v.detail + " (the run itself reported: \(e.category))"
                        } else if v.verified == false {
                            // Not there yet doesn't mean it won't be: a pending permission dialog can still run it.
                            o.detail = "not found yet; it may still appear if a Shortcuts dialog is answered"
                        } else {
                            o.detail = (note ?? v.detail) + "; so whether it happened is unknown"
                        }
                    }
                } catch {
                    o.error = .failed("\(error)")
                }
                return o
            }
            // At most a few runs at once, and calls that read back the same kind of item one at a time
            // (so each read-back sees its own item). Waiting counts against this call's budget.
            // Gate first, then a run slot: a call waiting for its read-back kind must not hold a slot
            // that an unrelated call could use.
            let waited = Outcome(error: .notStarted(cancel?.isCancelled == true ? "cancelled while waiting for other calls"
                                                                                  : "no time left after waiting for other calls"))
            let slotted: @Sendable () async -> Outcome = {
                guard await CallSlots.shared.acquire(until: deadline, cancel: cancel) else { return waited }
                let o = await work()
                await CallSlots.shared.release()
                return o
            }
            let o: Outcome
            if let kind = r.readBack {
                o = await ReadBackGate.shared.run(kind, until: deadline, cancel: cancel, slotted) ?? waited
            } else {
                o = await slotted()
            }
            report.ok = o.ok
            report.output = o.output
            report.verified = o.verified
            report.detail = o.detail
            if let e = o.error { throw e }
        } catch let e as CallError {
            report.error = e.description
            report.outcomeUnknown = e.outcomeUnknown ? true : nil
            category = e.category
        } catch let e as ToolError {
            report.error = e.description
            category = { switch e { case .pending: return "pending"; case .outdated: return "outdated"; default: return "setup" } }()
        } catch {
            report.error = "\(error)"
            category = "setup"
        }
        report.durationMs = Int(Date().timeIntervalSince(started) * 1000)
        appendLog(LogEntry(tool: logName, time: started, durationMs: report.durationMs, ok: report.ok,
                           verified: report.verified, error: category, caller: caller,
                           callID: logName == "<unknown>" ? nil : callID, event: logName == "<unknown>" ? nil : "end"))
        return report
    }

    /// A failed log write must not fail the call, but it must not pass silently either.
    @discardableResult
    func appendLog(_ e: LogEntry) -> Bool {
        if let id = e.callID, e.event == "end", InFlight.shared.alreadyLogged(id) { return true }
        do { try store.append(e); return true } catch {
            FileHandle.standardError.write(Data("intents-mcp: could not write the call log (\(error))\n".utf8))
            return false
        }
    }
}

struct Outcome: Sendable {
    var ok = false
    var output: String?
    var verified: Bool?
    var detail: String?
    var error: CallError?
}

/// A FIFO async semaphore whose waiters give up at a deadline or on cancel.
actor AsyncGate {
    private let limit: Int
    private var held = 0
    private var waiters: [(id: UUID, c: CheckedContinuation<Bool, Never>)] = []

    init(limit: Int) { self.limit = limit }

    /// true when acquired; false when the deadline passed or the call was cancelled first.
    func acquire(until deadline: Date, cancel: CancelToken?) async -> Bool {
        if held < limit { held += 1; return true }
        let id = UUID()
        let watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                if Date() >= deadline || cancel?.isCancelled == true { await self?.giveUp(id); return }
            }
        }
        defer { watchdog.cancel() }
        return await withCheckedContinuation { waiters.append((id, $0)) }
    }

    private func giveUp(_ id: UUID) {
        guard let i = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: i).c.resume(returning: false)
    }

    func release() {
        if waiters.isEmpty { held -= 1 } else { waiters.removeFirst().c.resume(returning: true) }
    }
}

/// At most 4 tool runs at once per process (many parallel `shortcuts run` processes help nobody).
enum CallSlots {
    static let shared = AsyncGate(limit: 4)
}

/// One-at-a-time execution per read-back kind.
actor ReadBackGate {
    static let shared = ReadBackGate()
    private var gates: [String: AsyncGate] = [:]

    private func gate(_ kind: ReadBack) -> AsyncGate {
        if let g = gates[kind.rawValue] { return g }
        let g = AsyncGate(limit: 1)
        gates[kind.rawValue] = g
        return g
    }

    private var lastRelease: [String: Date] = [:]

    /// nil when the deadline passed or the call was cancelled while waiting. Consecutive holders of
    /// one kind start at least 1.2 s apart, so the previous call's item is always older than the
    /// read-back window (creation ≥ run start − 1 s) of the next.
    func run<T: Sendable>(_ kind: ReadBack, until deadline: Date, cancel: CancelToken?,
                          _ body: @Sendable () async -> T) async -> T? {
        let g = gate(kind)
        guard await g.acquire(until: deadline, cancel: cancel) else { return nil }
        if let last = lastRelease[kind.rawValue] {
            let wait = last.addingTimeInterval(1.2).timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
        }
        let result = await body()
        lastRelease[kind.rawValue] = Date()
        await g.release()
        return result
    }
}

/// Prints a warning to stderr once per key.
enum Warned {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var seen = Set<String>()

    static func once(_ key: String, _ message: String) {
        let first = lock.withLock { seen.insert(key).inserted }
        if first { FileHandle.standardError.write(Data((message + "\n").utf8)) }
    }
}

/// Calls in progress, so a shutdown (SIGTERM from the client, Ctrl-C) can log them as interrupted.
public final class InFlight: @unchecked Sendable {
    public static let shared = InFlight()
    struct Call { var tool: String; var caller: String; var started: Date; var store: Store }
    private var calls: [String: Call] = [:]
    private let lock = NSLock()

    func begin(_ id: String, tool: String, caller: String, started: Date, store: Store) {
        lock.withLock { calls[id] = Call(tool: tool, caller: caller, started: started, store: store) }
    }

    private var interrupted = Set<String>()

    func end(_ id: String) { _ = lock.withLock { calls.removeValue(forKey: id) } }

    func alreadyLogged(_ id: String) -> Bool { lock.withLock { interrupted.contains(id) } }

    /// Writes an "end" line with error "interrupted" for every call still running.
    public func logInterrupted() {
        let open = lock.withLock { () -> [String: Call] in
            interrupted.formUnion(calls.keys)
            return calls
        }
        for (id, c) in open {
            do {
                try c.store.append(LogEntry(tool: c.tool, time: c.started, durationMs: Int(Date().timeIntervalSince(c.started) * 1000),
                                            ok: false, verified: nil, error: "interrupted", caller: c.caller,
                                            callID: id, event: "end"))
            } catch {
                FileHandle.standardError.write(Data("intents-mcp: could not log an interrupted call (\(error))\n".utf8))
            }
        }
    }
}
