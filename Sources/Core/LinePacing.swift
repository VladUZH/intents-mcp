import Foundation

/// Paces human-facing CLI output so it appears one line at a time on a terminal: easier to follow
/// (and to record) than a burst. Pure policy; the CLI measures time and sleeps.
///
/// Off unless stdout is a terminal and TERM is set (not "dumb"), so pipes, files, `--json` output
/// and the MCP server's stdio are never slowed. `INTENTS_MCP_LINE_DELAY_MS` sets the gap between
/// lines (0 turns pacing off). Pausing adds at most `defaultBudget` seconds to a command, or
/// `setBudget` with a gap from the environment (e.g. slower, for a screen recording); blocks shrink
/// their gap to fit. Blocks longer than `maxBlockLines` print at once.
public struct LinePacing: Sendable, Equatable {
    public static let variable = "INTENTS_MCP_LINE_DELAY_MS"
    public static let defaultGap: TimeInterval = 0.04
    public static let defaultBudget: TimeInterval = 2
    public static let setBudget: TimeInterval = 10
    public static let maxGap: TimeInterval = 2
    public static let maxBlockLines = 300
    /// A shorter gap isn't worth sleeping for: the lines print at once.
    public static let minGap: TimeInterval = 0.005

    public let gap: TimeInterval
    /// Seconds of pausing left for this command.
    public private(set) var budget: TimeInterval

    /// nil: print at once. An unreadable `INTENTS_MCP_LINE_DELAY_MS` counts as unset.
    public init?(environment env: [String: String], stdoutIsTerminal: Bool) {
        guard stdoutIsTerminal, let term = env["TERM"], !term.isEmpty, term != "dumb" else { return nil }
        if let raw = env[Self.variable], let ms = Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)), ms >= 0 {
            guard ms > 0 else { return nil }
            gap = min(Double(ms) / 1000, Self.maxGap)
            budget = Self.setBudget
        } else {
            gap = Self.defaultGap
            budget = Self.defaultBudget
        }
    }

    /// The gap before each line of an n-line block: the configured gap, shrunk so the whole block
    /// fits the budget left. 0 prints the block at once.
    public func gap(forBlockOf n: Int) -> TimeInterval {
        guard n > 0, n <= Self.maxBlockLines else { return 0 }
        let g = min(gap, budget / Double(n))
        return g < Self.minGap ? 0 : g
    }

    /// How long to wait before the next line: what is left of `gap` since the previous line (no
    /// wait before a command's first line, or after slow work), within the budget. Spends it.
    public mutating func pause(gap g: TimeInterval, sinceLast elapsed: TimeInterval?) -> TimeInterval {
        guard let elapsed, g > 0 else { return 0 }
        let p = min(max(0, g - elapsed), budget)
        budget -= p
        return p
    }
}
