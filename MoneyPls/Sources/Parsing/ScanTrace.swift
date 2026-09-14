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

    /// What the parser produced, read back from a stored trace: one `ITEM q × name = cents` line per item.
    /// The split's items drift from this as soon as the user edits them, which is what a scan report needs
    /// to tell apart. Nil when the trace has no ITEM lines (a failed scan, or a split typed in by hand).
    static func parsedItems(in trace: String) -> (count: Int, sumCents: Int)? {
        let re = try! NSRegularExpression(pattern: #"^\S+ ITEM \d+ × .* = (-?\d+)$"#, options: .anchorsMatchLines)   // swiftlint:disable:this force_try
        let ns = trace as NSString
        let cents = re.matches(in: trace, range: NSRange(location: 0, length: ns.length)).compactMap { Int(ns.substring(with: $0.range(at: 1))) }
        return cents.isEmpty ? nil : (cents.count, cents.reduce(0, +))
    }
}

func trace(_ s: String) { parseLog.info("\(s, privacy: .public)"); ScanTrace.shared.add(s) }
func traceError(_ s: String) { parseLog.error("\(s, privacy: .public)"); ScanTrace.shared.add("ERROR " + s) }
