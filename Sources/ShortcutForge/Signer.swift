import Core
import Foundation

public enum SignerError: Error, CustomStringConvertible {
    case failed(String)
    case notSigned(String)

    public var description: String {
        switch self {
        case .failed(let m): return "shortcuts sign failed: \(m)"
        case .notSigned(let p): return "shortcuts sign did not produce a signed file: \(p)"
        }
    }
}

/// `shortcuts sign`. Uses the user's iCloud account; Apple receives a copy for validation
/// (Apple's Shortcuts guide). "people-who-know-me" signs locally and the file imports on this Mac (M0).
public enum Signer {
    public static func sign(unsigned: URL, to output: URL, mode: String = "people-who-know-me") throws {
        try? FileManager.default.removeItem(at: output)
        guard let r = Shell.run("/usr/bin/shortcuts", ["sign", "--mode", mode, "--input", unsigned.path, "--output", output.path],
                                timeout: 60) else {
            throw SignerError.failed("could not start /usr/bin/shortcuts")
        }
        if r.timedOut { throw SignerError.failed("timed out") }
        // The exit status is unreliable (cherri#49): check for the AEA1 magic instead.
        guard isSigned(output) else {
            let msg = (r.stderr + r.stdout).trimmingCharacters(in: .whitespacesAndNewlines)
            throw msg.isEmpty ? SignerError.notSigned(output.path) : SignerError.failed(msg)
        }
    }

    public static func isSigned(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        return (try? h.read(upToCount: 4)) == Data("AEA1".utf8)
    }
}
