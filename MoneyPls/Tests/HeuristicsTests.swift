import XCTest
@testable import MoneyPls

/// The deterministic parser on OCR lines as the app's line builder emits them (tab before the price). Each
/// receipt here came from a scan report where the OCR was right and the parser wasn't.
final class HeuristicsTests: XCTestCase {
    /// Toast receipt from a scan report: "Summer" contains the German total word "summe", so the last item used
    /// to be read as the total line, which dropped it and turned its price into the subtotal.
    func testItemNameContainingForeignTotalWordStaysAnItem() {
        let lines = [
            "MISC", "758 Franklin Ave", "Brooklyn, NY 11238", "347-663-4020",
            "Server: Shoot S", "Table 8", "Check #30", "Guest Count: 4", "9/5/26 4:26 PM", "Ordered:",
            "1 lychee delight\t$11.00",
            "1 Mama J'O\t$30.95",
            "1 Walk into the Sea\t$43.95",
            "1 Kaeng Phed Ped Lychee\t$33.95",
            "1 Shrimp Summer Rolls\t$15.95",
            "Subtotal\t$135.80",
            "Service charge (18.00%)\t$24.44",
            "Tax\t$12.07",
            "Total\t$172.31",
            "Suggested Additional Tip:",
            "+ 2%: (Tip $2.96 Total $175.27)",
            "+ 3%: (Tip $4.44 Total $176.75)",
            "Powered by Toast",
        ]
        let r = Heuristics.parse(lines: lines)
        XCTAssertEqual(r.items.map(\.priceCents), [1100, 3095, 4395, 3395, 1595])
        XCTAssertEqual(r.subtotalCents, 13580)
        XCTAssertEqual(r.tipCents, 2444)
        XCTAssertEqual(r.taxCents, 1207)
        XCTAssertEqual(r.totalCents, 17231)
        XCTAssertTrue(r.reconciles)
        XCTAssertEqual(r.currencyCode, "USD")
    }

    /// The keyword rule itself: a Latin word matches only where it ends a word, clipped fragments and
    /// German compounds included; CJK matches anywhere.
    func testSummaryKeywordsEndAWord() {
        XCTAssertFalse(Heuristics.isTotal("1 shrimp summer rolls"))
        XCTAssertFalse(Heuristics.isTotal("totally awesome burger"))
        XCTAssertTrue(Heuristics.isTotal("total"))
        XCTAssertTrue(Heuristics.isTotal("grand total:"))
        XCTAssertTrue(Heuristics.isTotal("otal due"))          // crop shaved the first letter
        XCTAssertTrue(Heuristics.isTotal("gesamtsumme"))
        XCTAssertTrue(Heuristics.isTotal("gesamtbetrag"))
        XCTAssertTrue(Heuristics.isTotal("totale"))
        XCTAssertTrue(Heuristics.isTotal("合計金額"))
        XCTAssertTrue(Heuristics.isSubtotal("btotal"))
        XCTAssertTrue(Heuristics.isSubtotal("zwischensumme"))
        XCTAssertFalse(Heuristics.isSubtotal("subtotals are fun")) // not a receipt line anyway; "subtotals" ≠ "subtotal"
    }
}
