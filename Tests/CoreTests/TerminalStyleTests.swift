import Core
import Testing

@Suite struct TerminalStyleTests {
    @Test func colorOnlyOnATerminalWithoutNoColor() {
        let term = ["TERM": "xterm-256color"]
        #expect(TerminalStyle.enabled(environment: term, stdoutIsTerminal: true))
        #expect(!TerminalStyle.enabled(environment: term, stdoutIsTerminal: false))  // pipe, file
        #expect(!TerminalStyle.enabled(environment: [:], stdoutIsTerminal: true))
        #expect(!TerminalStyle.enabled(environment: ["TERM": "dumb"], stdoutIsTerminal: true))
        #expect(!TerminalStyle.enabled(environment: term.merging(["NO_COLOR": "1"]) { $1 }, stdoutIsTerminal: true))
        // no-color.org: only a non-empty NO_COLOR turns color off.
        #expect(TerminalStyle.enabled(environment: term.merging(["NO_COLOR": ""]) { $1 }, stdoutIsTerminal: true))
    }

    @Test func wrapResetsAndLeavesEmptyTextAlone() {
        #expect(TerminalStyle.wrap("945", "1") == "\u{1B}[1m945\u{1B}[0m")
        #expect(TerminalStyle.wrap("", "32") == "")
    }
}
