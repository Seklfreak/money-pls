import Foundation

enum AppConfig {
    /// Optional — empty/missing disables crash reporting (simulator and CI builds run from the
    /// placeholder xcconfig, which leaves it blank).
    static var sentryDSN: String? {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SENTRY_DSN") as? String, !dsn.isEmpty else { return nil }
        return dsn
    }
}
