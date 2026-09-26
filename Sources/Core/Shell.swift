import Foundation

/// A cancellation flag shared between a request and the process it started.
public final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }
    public func cancel() { lock.withLock { cancelled = true } }
}

/// Runs a tool with stdin from /dev/null (an inherited stdin hangs `shortcuts`) and a timeout.
///
/// Everything blocking happens on dedicated threads: the pipe readers never wait for a slot in
/// a shared queue, and `runAsync` keeps callers off Swift's cooperative pool. Before, 13 parallel
/// tool calls on a 14-CPU Mac starved the readers and hung `serve` for good (bug hunt, 2026-09-26).
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var timedOut: Bool
        public var cancelled: Bool
        /// true when the output pipes were still open at the deadline (a grandchild held them), so
        /// stdout/stderr may be missing.
        public var incomplete: Bool = false
    }

    /// Set by `stopAll` on shutdown: no new processes start after it.
    public static var isShuttingDown: Bool { shutdown.isCancelled }
    private static let shutdown = CancelToken()

    /// Children that are running now, so a signal handler can stop them (see `stopAll`).
    private static let running = Registry()

    public static func run(_ path: String, _ args: [String], timeout: TimeInterval = 20,
                           cancel: CancelToken? = nil) -> Result? {
        guard !isShuttingDown else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        let exited = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        do { try p.run() } catch { return nil }
        running.insert(p)
        defer { running.remove(p) }

        // Read both pipes while the child runs, each on its own thread, so a full pipe can't block it.
        let outData = LockedData(), errData = LockedData()
        let readers = DispatchGroup()
        for (h, box) in [(out.fileHandleForReading, outData), (err.fileHandleForReading, errData)] {
            readers.enter()
            Thread.detachNewThread {
                box.set(h.readDataToEndOfFile())
                readers.leave()
            }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false, cancelled = false
        while exited.wait(timeout: .now() + 0.1) == .timedOut {
            if cancel?.isCancelled == true { cancelled = true; break }
            if Date() >= deadline { timedOut = true; break }
        }
        if timedOut || cancelled { stop(p, exited) }
        // The readers finish when the pipes close. A grandchild can keep them open after the child
        // exits: wait only as long as the timeout allows (at least 0.5 s), never forever.
        let grace = max(0.5, min(5, deadline.timeIntervalSinceNow))
        let complete = readers.wait(timeout: .now() + grace) == .success
        return Result(status: p.isRunning ? -1 : p.terminationStatus,
                      stdout: String(decoding: outData.get(), as: UTF8.self),
                      stderr: String(decoding: errData.get(), as: UTF8.self),
                      timedOut: timedOut, cancelled: cancelled, incomplete: !complete)
    }

    /// `run` on a dedicated thread: never blocks a cooperative-pool thread of the caller.
    public static func runAsync(_ path: String, _ args: [String], timeout: TimeInterval = 20,
                                cancel: CancelToken? = nil) async -> Result? {
        await withCheckedContinuation { c in
            Thread.detachNewThread { c.resume(returning: run(path, args, timeout: timeout, cancel: cancel)) }
        }
    }

    /// SIGINT first (the polite stop for a CLI; whether `shortcuts` also cancels a run that is
    /// waiting for a permission dialog is not verified), then SIGTERM, then SIGKILL.
    static func stop(_ p: Process, _ exited: DispatchSemaphore) {
        guard p.isRunning else { return }
        p.interrupt()
        if exited.wait(timeout: .now() + 1) == .success { return }
        p.terminate()
        if exited.wait(timeout: .now() + 1) == .success { return }
        kill(p.processIdentifier, SIGKILL)
        _ = exited.wait(timeout: .now() + 2)
    }

    /// Stops every running child (SIGINT, then SIGTERM). For signal handlers on shutdown.
    public static func stopAll() {
        shutdown.cancel()
        let ps = running.all().filter(\.isRunning)
        guard !ps.isEmpty else { return }  // idle: exit at once (clients SIGKILL soon after SIGTERM)
        for p in ps where p.isRunning { p.interrupt() }
        Thread.sleep(forTimeInterval: 0.3)
        for p in ps where p.isRunning { p.terminate() }
        Thread.sleep(forTimeInterval: 0.3)
        for p in ps where p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    final class LockedData: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func set(_ d: Data) { lock.withLock { data = d } }
        func get() -> Data { lock.withLock { data } }
    }

    final class Registry: @unchecked Sendable {
        private var items: [ObjectIdentifier: Process] = [:]
        private let lock = NSLock()
        func insert(_ p: Process) { lock.withLock { items[ObjectIdentifier(p)] = p } }
        func remove(_ p: Process) { _ = lock.withLock { items.removeValue(forKey: ObjectIdentifier(p)) } }
        func all() -> [Process] { lock.withLock { Array(items.values) } }
    }
}
