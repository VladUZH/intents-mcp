import Core
import Foundation

/// Human-facing output. On a terminal it appears one line at a time (see `LinePacing`); through a
/// pipe or into a file it prints at once. JSON goes through `printJSON`, never through here.
enum Out {
    private static let state = State()

    /// Prints text (it may hold several lines).
    static func line(_ text: String = "") { state.emit(text.lines) }

    /// Prints a whole block: the gap shrinks to fit the time budget, and long blocks print at once.
    static func block(_ texts: [String]) { state.emit(texts.flatMap(\.lines)) }

    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var pacing = LinePacing(environment: ProcessInfo.processInfo.environment,
                                        stdoutIsTerminal: isatty(STDOUT_FILENO) == 1)
        private var last: TimeInterval?  // uptime when the previous line was printed

        func emit(_ lines: [String]) {
            lock.withLock {
                let g = pacing?.gap(forBlockOf: lines.count) ?? 0
                for l in lines {
                    if g > 0, var p = pacing {
                        let wait = p.pause(gap: g, sinceLast: last.map { ProcessInfo.processInfo.systemUptime - $0 })
                        pacing = p
                        if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
                    }
                    print(l)
                    last = ProcessInfo.processInfo.systemUptime
                }
            }
        }
    }
}

private extension String {
    var lines: [String] { split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
}
