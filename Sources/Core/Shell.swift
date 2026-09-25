import Foundation

/// Runs a tool with stdin from /dev/null (an inherited stdin hangs `shortcuts`) and a timeout.
public enum Shell {
    public struct Result {
        public var status: Int32
        public var stdout: String
        public var stderr: String
        public var timedOut: Bool
    }

    public static func run(_ path: String, _ args: [String], timeout: TimeInterval = 20) -> Result? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        // Read while waiting so a full pipe can't block the child.
        let outData = LockedData(), errData = LockedData()
        let g = DispatchGroup()
        for (h, box) in [(out.fileHandleForReading, outData), (err.fileHandleForReading, errData)] {
            g.enter()
            DispatchQueue.global().async { box.set(h.readDataToEndOfFile()); g.leave() }
        }
        while p.isRunning && Date() < deadline { usleep(20_000) }
        let timedOut = p.isRunning
        if timedOut { p.terminate() }
        p.waitUntilExit()
        g.wait()
        return Result(status: p.terminationStatus, stdout: String(decoding: outData.get(), as: UTF8.self),
                      stderr: String(decoding: errData.get(), as: UTF8.self), timedOut: timedOut)
    }

    final class LockedData: @unchecked Sendable {
        private var data = Data()
        private let lock = NSLock()
        func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
        func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
    }
}
