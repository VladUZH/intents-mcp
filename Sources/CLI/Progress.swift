import Foundation

/// A spinner on stderr while slow work runs (the metadata scan takes about 10 s), so the
/// terminal never looks stuck. Only when stderr is a terminal: pipes, JSON output and the MCP
/// server's stdio stay clean.
enum Progress {
    static func run<T>(_ message: String, _ work: () throws -> T) rethrows -> T {
        guard isatty(STDERR_FILENO) == 1 else { return try work() }
        let done = Flag()
        let thread = Thread {
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            let start = Date()
            var i = 0
            while !done.value {
                let s = Int(Date().timeIntervalSince(start))
                FileHandle.standardError.write(Data("\r\(frames[i % frames.count]) \(message) \(s) s ".utf8))
                i += 1
                Thread.sleep(forTimeInterval: 0.1)
            }
            FileHandle.standardError.write(Data("\r\u{1B}[2K".utf8))  // clear the line
            done.finished = true
        }
        thread.start()
        defer {
            done.value = true
            while !done.finished { Thread.sleep(forTimeInterval: 0.01) }
        }
        return try work()
    }

    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var _value = false, _finished = false
        var value: Bool {
            get { lock.withLock { _value } }
            set { lock.withLock { _value = newValue } }
        }
        var finished: Bool {
            get { lock.withLock { _finished } }
            set { lock.withLock { _finished = newValue } }
        }
    }
}
