import Core
import Foundation
import Testing

@Suite struct LinePacingTests {
    let term = ["TERM": "xterm-256color"]

    func env(_ delay: String) -> [String: String] { term.merging([LinePacing.variable: delay]) { $1 } }

    @Test func onlyOnARealTerminal() {
        #expect(LinePacing(environment: term, stdoutIsTerminal: false) == nil)  // pipe, file
        #expect(LinePacing(environment: [:], stdoutIsTerminal: true) == nil)  // no TERM
        #expect(LinePacing(environment: ["TERM": ""], stdoutIsTerminal: true) == nil)
        #expect(LinePacing(environment: ["TERM": "dumb"], stdoutIsTerminal: true) == nil)
        let p = LinePacing(environment: term, stdoutIsTerminal: true)
        #expect(p?.gap == LinePacing.defaultGap)
        #expect(p?.budget == LinePacing.defaultBudget)
    }

    @Test func theEnvironmentSetsTheGap() {
        #expect(LinePacing(environment: env("0"), stdoutIsTerminal: true) == nil)  // off
        let slow = LinePacing(environment: env(" 120 "), stdoutIsTerminal: true)
        #expect(slow?.gap == 0.12)
        #expect(slow?.budget == LinePacing.setBudget)  // a gap you set gets a longer budget
        #expect(LinePacing(environment: env("120\n"), stdoutIsTerminal: true)?.gap == 0.12)
        #expect(LinePacing(environment: env("0\r\n"), stdoutIsTerminal: true) == nil)
        #expect(LinePacing(environment: env("99999"), stdoutIsTerminal: true)?.gap == LinePacing.maxGap)
        for bad in ["", "fast", "-5", "1.5"] {  // unreadable: the default
            #expect(LinePacing(environment: env(bad), stdoutIsTerminal: true)?.gap == LinePacing.defaultGap)
        }
    }

    @Test func blocksFitTheBudget() throws {
        let p = try #require(LinePacing(environment: term, stdoutIsTerminal: true))
        #expect(p.gap(forBlockOf: 0) == 0)
        #expect(p.gap(forBlockOf: 1) == LinePacing.defaultGap)
        #expect(p.gap(forBlockOf: 30) == LinePacing.defaultGap)  // census: 30 × 40 ms < 2 s
        #expect(abs(p.gap(forBlockOf: 100) - 0.02) < 1e-9)  // shrunk: 100 lines in 2 s
        #expect(abs(p.gap(forBlockOf: LinePacing.maxBlockLines) - 2.0 / 300) < 1e-9)  // still paced
        #expect(p.gap(forBlockOf: LinePacing.maxBlockLines + 1) == 0)  // long output prints at once
        let slow = try #require(LinePacing(environment: env("120"), stdoutIsTerminal: true))
        #expect(slow.gap(forBlockOf: 50) == 0.12)  // census-sized: as set
        #expect(abs(slow.gap(forBlockOf: 200) - 0.05) < 1e-9)  // shrunk: 200 lines in 10 s
        #expect(slow.gap(forBlockOf: LinePacing.maxBlockLines + 1) == 0)
    }

    @Test func pausesSpendTheBudget() throws {
        var p = try #require(LinePacing(environment: term, stdoutIsTerminal: true))
        #expect(p.pause(gap: 0.04, sinceLast: nil) == 0)  // first line: no wait
        #expect(p.pause(gap: 0.04, sinceLast: 5) == 0)  // after slow work: no wait
        #expect(abs(p.pause(gap: 0.04, sinceLast: 0.01) - 0.03) < 1e-9)
        #expect(abs(p.budget - 1.97) < 1e-9)
        #expect(p.pause(gap: 0, sinceLast: 0) == 0)
        var spent = 0.0
        for _ in 0..<100 { spent += p.pause(gap: 0.04, sinceLast: 0) }
        #expect(abs(spent - 1.97) < 1e-9)  // never more than the budget
        #expect(p.budget == 0)
        #expect(p.gap(forBlockOf: 1) == 0)  // budget spent: the rest prints at once
    }
}
