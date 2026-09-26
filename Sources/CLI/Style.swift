import Core
import Foundation

/// Color and bold for human-facing output (see `TerminalStyle`); plain text when it's off. Apply it
/// after padding: escape codes take no columns on screen but count as characters.
enum Style {
    static let on = TerminalStyle.enabled(environment: ProcessInfo.processInfo.environment,
                                          stdoutIsTerminal: isatty(STDOUT_FILENO) == 1)

    static func bold(_ s: String) -> String { on ? TerminalStyle.wrap(s, "1") : s }
    static func dim(_ s: String) -> String { on ? TerminalStyle.wrap(s, "2") : s }
    static func green(_ s: String) -> String { on ? TerminalStyle.wrap(s, "32") : s }
    static func yellow(_ s: String) -> String { on ? TerminalStyle.wrap(s, "33") : s }
    /// The one number worth zooming in on (the census headline): bold cyan.
    static func accent(_ s: String) -> String { on ? TerminalStyle.wrap(s, "1;36") : s }
    static func red(_ s: String) -> String { on ? TerminalStyle.wrap(s, "31") : s }
    /// The command a message tells the user to run, in bold: `intents-mcp …` inside backticks.
    static func commands(_ s: String) -> String {
        guard on else { return s }
        return s.replacingOccurrences(of: #"`intents-mcp [^`]*`"#, with: "\u{1B}[1m$0\u{1B}[0m", options: .regularExpression)
    }
}
