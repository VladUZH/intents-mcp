/// Whether human-facing CLI output may use color and bold: only on a terminal (TERM set, not
/// "dumb") and when `NO_COLOR` is unset or empty (https://no-color.org). Pipes, files, `--json`
/// output and the MCP server's stdio stay plain. Only the basic ANSI colors, bold and dim, so the
/// user's terminal theme decides the actual shades (dark and light backgrounds both work).
public enum TerminalStyle {
    public static func enabled(environment env: [String: String], stdoutIsTerminal: Bool) -> Bool {
        guard stdoutIsTerminal, let term = env["TERM"], !term.isEmpty, term != "dumb" else { return false }
        return env["NO_COLOR"]?.isEmpty ?? true
    }

    /// `text` wrapped in an SGR code (e.g. "1" bold, "2" dim, "32" green) and a reset.
    public static func wrap(_ text: String, _ code: String) -> String {
        text.isEmpty ? text : "\u{1B}[\(code)m\(text)\u{1B}[0m"
    }
}
