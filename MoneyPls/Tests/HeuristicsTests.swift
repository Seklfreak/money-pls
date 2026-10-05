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
        // Toast prints "1 name" on every item; the summary and tip lines must not outvote that quantity column.
        XCTAssertEqual(r.items.map(\.name), ["lychee delight", "Mama J'O", "Walk into the Sea", "Kaeng Phed Ped Lychee", "Shrimp Summer Rolls"])
        XCTAssertEqual(r.items.map(\.quantity), [1, 1, 1, 1, 1])
        XCTAssertEqual(r.subtotalCents, 13580)
        XCTAssertEqual(r.tipCents, 2444)
        XCTAssertEqual(r.taxCents, 1207)
        XCTAssertEqual(r.totalCents, 17231)
        XCTAssertTrue(r.reconciles)
        XCTAssertEqual(r.currencyCode, "USD")
    }

    /// Menusifu receipt from a scan report: English header and footer, Chinese item names, lines as the flattened
    /// line builder reads the photo. Enough Latin lines that it isn't a CJK receipt, so names get their Han stripped.
    /// Consecutive Chinese-only lines used to overwrite each other's held price, add-ons came out named "-" and
    /// "•", the last item above "Subtotal:" was swapped in as the subtotal (pushing the subtotal into tax and the
    /// tax into total), and the order number "32" became the first item's quantity.
    func testChineseItemNamesUnderEnglishHeader() {
        let lines = [
            "坐吃", "Nai Brother", "1946 86th Street", "Brooklyn, NY 11214", "347-312-5982", "Server",
            "10/04/26 16:37:1GST: 6", "堂吃 A5",
            "32",
            "雪碧\t$5.85",
            "秘制口水鸡\t$7.95", "1",
            "沙爹牛肉串\t$5.95", "1",
            "奈哥酸菜口味\t$0.00",
            "肥牛（双人份）\t$28.90",
            "日照番茄口味\t$0.00", "1",
            "肥牛（单人份）\t$14.95",
            "1 肥牛香锅\t$14.95",
            "-莲藕\t$3.00",
            "-金针菇 X2\t$6.00",
            "-魔芋丝 X2\t$6.00",
            "-大虾\t$5.00",
            "-牛百叶\t$5.00",
            "-鱼豆腐\t$3.50",
            "-黑鱼X2\t$10.00",
            "双人份\t$14.95",
            "Subtotal:\t$146.95",
            "Tax:\t$13.04",
            "Total:\t$159.99",
            "*** Unpaid ***", "Tips Suggestions", "18%: $26.45", "20%: $29.39", "22%: $32.33", "POWERED BY MENUSIFU",
        ]
        let r = Heuristics.parse(lines: lines)
        XCTAssertEqual(r.items.map(\.name), ["雪碧", "秘制口水鸡", "沙爹牛肉串", "奈哥酸菜口味", "肥牛（双人份）", "日照番茄口味", "肥牛（单人份）",
                                             "肥牛香锅", "莲藕", "金针菇", "魔芋丝", "大虾", "牛百叶", "鱼豆腐", "黑鱼", "双人份"])
        XCTAssertEqual(r.items.map(\.priceCents), [585, 795, 595, 0, 2890, 0, 1495, 1495, 300, 600, 600, 500, 500, 350, 1000, 1495])
        XCTAssertEqual(r.items.map(\.quantity), [1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 1, 1, 1, 2, 1])
        // The receipt itself prints $14.95 more in its subtotal than its lines add up to.
        XCTAssertEqual(r.itemSumCents, 13200)
        XCTAssertEqual(r.subtotalCents, 14695)
        XCTAssertEqual(r.taxCents, 1304)
        XCTAssertEqual(r.totalCents, 15999)
        XCTAssertEqual(r.currencyCode, "USD")
    }

    /// On a Chinese-only receipt names are kept whole, so the quantity the line builder joins in front and the
    /// bullet of an add-on have to come off here.
    func testChineseOnlyReceiptTakesQuantityAndBulletOffTheName() {
        let r = Heuristics.parse(lines: ["奈哥", "3\t雪碧\t$5.85", "1 肥牛香锅\t$14.95", "-莲藕\t$3.00", "小计\t$23.80"])
        XCTAssertEqual(r.items.map(\.name), ["雪碧", "肥牛香锅", "莲藕"])
        XCTAssertEqual(r.items.map(\.quantity), [3, 1, 1])
        XCTAssertTrue(r.reconciles)
    }

    /// Recovering a lost price from another OCR pass must not add a dish we already have under a one-stroke
    /// misreading ("肥午" for "肥牛"): that invented a $14.95 item and made a receipt that overcharges add up.
    func testOneCharacterMisreadIsTheSameName() {
        XCTAssertTrue(Heuristics.similar(Heuristics.key("肥午（单人份）"), Heuristics.key("肥牛（单人份）")))
        XCTAssertTrue(Heuristics.similar("lotusroot", "otusroot"))
        XCTAssertFalse(Heuristics.similar("鸡", "鸭"))
        XCTAssertFalse(Heuristics.similar("肥牛单人份", "肥牛双人锅"))
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

    /// The scan report reads the parser's result back out of the stored trace, so it can show it next to
    /// whatever the user has edited the split into since.
    func testParsedItemsReadBackFromTrace() {
        let trace = """
        2026-09-06T01:00:55Z L15: 1 Shrimp Summer Rolls ⇥ $15.95
        2026-09-06T01:00:55Z ITEM 1 × 1 lychee delight = 1100
        2026-09-06T01:00:55Z ITEM 2 × Mama J'O = 3095
        2026-09-06T01:00:55Z ITEM 1 × Refund = -500
        2026-09-06T01:00:55Z parsed 3 items sum=3695 subtotal=1595
        """
        let parsed = ScanTrace.parsedItems(in: trace)
        XCTAssertEqual(parsed?.count, 3)
        XCTAssertEqual(parsed?.sumCents, 3695)
        XCTAssertNil(ScanTrace.parsedItems(in: "2026-09-06T01:00:55Z ERROR requestCancelled"))
        XCTAssertNil(ScanTrace.parsedItems(in: ""))
    }
}
