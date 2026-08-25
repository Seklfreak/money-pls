import Foundation
import os

let parseLog = Logger(subsystem: "dev.winktech.moneypls", category: "parse")

/// The parse log of the most recent scan, kept in memory so a failed scan can be reported with it.
/// Mirrors what `parseLog` writes to the unified log; reset at the start of every parse.
final class ScanTrace: @unchecked Sendable {
    static let shared = ScanTrace()
    private let lock = NSLock()
    private var lines: [String] = []
    private let clock = ISO8601DateFormatter()

    func reset() { lock.withLock { lines.removeAll() } }
    func add(_ line: String) { let stamp = clock.string(from: Date()); lock.withLock { lines.append("\(stamp) \(line)") } }
    var text: String { lock.withLock { lines.joined(separator: "\n") } }
}

func trace(_ s: String) { parseLog.info("\(s, privacy: .public)"); ScanTrace.shared.add(s) }
func traceError(_ s: String) { parseLog.error("\(s, privacy: .public)"); ScanTrace.shared.add("ERROR " + s) }
