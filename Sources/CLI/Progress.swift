import Foundation

/// A spinner on stderr while slow work runs (the metadata scan takes about 10 s), so the
/// terminal never looks stuck. Only on a real terminal (not TERM=dumb): pipes, JSON output and the
/// MCP server's stdio stay clean. Each frame is cut to the terminal width so it never wraps.
enum Progress {
    static func run<T>(_ message: String, _ work: () throws -> T) rethrows -> T {
        let term = ProcessInfo.processInfo.environment["TERM"] ?? ""
        guard isatty(STDERR_FILENO) == 1, !term.isEmpty, term != "dumb" else { return try work() }
        let done = Flag()
        let thread = Thread {
            let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
            let start = Date()
            var i = 0
            while !done.value {
                let s = Int(Date().timeIntervalSince(start))
                var line = "\(frames[i % frames.count]) \(message) \(s) s"
                let width = terminalWidth()
                if line.count > width - 1 { line = String(line.prefix(max(1, width - 1))) }
                FileHandle.standardError.write(Data("\r\u{1B}[2K\(line)".utf8))
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

    static func terminalWidth() -> Int {
        var ws = winsize()
        guard ioctl(STDERR_FILENO, TIOCGWINSZ, &ws) == 0, ws.ws_col > 0 else { return 80 }
        return Int(ws.ws_col)
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
