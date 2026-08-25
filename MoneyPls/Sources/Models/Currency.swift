import Foundation
import SwiftUI

/// Currency support: everything is stored in minor units (cents, pence, yen) next to an ISO 4217 code
/// on the split. No conversion anywhere — a receipt is one currency and the payer is owed in it.
enum Currency {
    /// What the picker offers; the phone's own currency is listed first.
    static var supported: [String] {
        let base = ["USD", "EUR", "GBP", "JPY", "CHF", "CAD", "AUD", "MXN", "CNY", "HKD", "SGD", "KRW", "INR",
                    "SEK", "NOK", "DKK", "NZD", "TWD", "THB", "PLN", "CZK", "BRL"]
        let mine = `default`
        return base.contains(mine) ? [mine] + base.filter { $0 != mine } : [mine] + base
    }
    /// The phone's region currency — what a receipt without any symbol is assumed to be in.
    static var `default`: String { Locale.current.currency?.identifier ?? "USD" }

    /// Currencies whose receipts carry whole numbers: ¥1,200 is 1200 minor units, not 12.00.
    static let zeroDecimal: Set<String> = ["JPY", "KRW", "VND", "CLP", "ISK"]
    static func minorDigits(_ code: String) -> Int { zeroDecimal.contains(code) ? 0 : 2 }

    static func format(_ minor: Int, code: String, symbol: Bool) -> String {
        let digits = minorDigits(code)
        let value = Decimal(minor) / pow(10, digits)
        if symbol {
            return value.formatted(.currency(code: code).precision(.fractionLength(digits)))
        }
        return value.formatted(.number.precision(.fractionLength(digits)).grouping(.never))
    }

    /// Parse what the user typed in a price field, in the current locale's decimal style.
    static func minorUnits(from text: String, code: String) -> Int {
        let digits = minorDigits(code)
        let cleaned = text.replacingOccurrences(of: ",", with: ".").filter { $0.isNumber || $0 == "." || $0 == "-" }
        let value = Double(cleaned) ?? 0
        return Int((value * pow(10, Double(digits))).rounded())
    }
}

extension Int {
    /// Minor units → "$12.34", "12,34 €", "¥1,200" for the phone's locale.
    func money(_ code: String) -> String { Currency.format(self, code: code, symbol: true) }
    /// Minor units → "12.34" / "1200", no symbol, no grouping (fields and receipt columns).
    func moneyPlain(_ code: String) -> String { Currency.format(self, code: code, symbol: false) }
}

private struct CurrencyKey: EnvironmentKey { static let defaultValue = Currency.default }
extension EnvironmentValues {
    /// The split's currency code, set at each screen's root so rows and cards format without threading it by hand.
    var currency: String { get { self[CurrencyKey.self] } set { self[CurrencyKey.self] = newValue } }
}
