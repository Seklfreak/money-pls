import XCTest
@testable import MoneyPls

/// The line builder on Vision-shaped words: normalized boxes, origin bottom-left.
final class LineBuilderTests: XCTestCase {
    private func word(_ text: String, x: CGFloat, to maxX: CGFloat, y midY: CGFloat, slope: CGFloat = 0) -> ReceiptParser.Word {
        ReceiptParser.Word(text: text, conf: 1, box: CGRect(x: x, y: midY - 0.01, width: maxX - x, height: 0.02), slope: slope)
    }

    /// A curl at the top of a hand-held receipt: the names climb 0.04 towards the price column, so each price sits
    /// nearer the row above than its own and the first one used to join the order number printed over the items.
    /// Flat rows below stay as they are.
    func testCurledRowsAreFlattenedBeforePricesAttach() {
        let curl: CGFloat = 0.04
        func price(_ text: String, row: CGFloat) -> ReceiptParser.Word { word(text, x: 0.71, to: 0.86, y: row + curl * (0.785 - 0.285), slope: curl) }
        let words = [
            word("32", x: 0.10, to: 0.18, y: 0.72),
            word("雪碧", x: 0.17, to: 0.40, y: 0.69, slope: curl), price("$5.85", row: 0.69),
            word("秘制口水鸡", x: 0.17, to: 0.40, y: 0.655, slope: curl), price("$7.95", row: 0.655),
            word("沙爹牛肉串", x: 0.17, to: 0.40, y: 0.62, slope: curl), price("$5.95", row: 0.62),
            word("Subtotal:", x: 0.20, to: 0.42, y: 0.30), word("$19.75", x: 0.70, to: 0.86, y: 0.30),
        ]
        XCTAssertEqual(ReceiptParser.groupLines(words), ["32", "雪碧\t$5.85", "秘制口水鸡\t$7.95", "沙爹牛肉串\t$5.95", "Subtotal:\t$19.75"])
    }

    /// Vision's slope isn't always true: rows that lie level with their prices keep their pairing even when the
    /// names report a tilt (a blurry Toast receipt reads 0.03 on every row).
    func testFalseSlopeIsIgnoredWhenRowsAlreadyLineUp() {
        let words = [
            word("1 Beef Tartare", x: 0.05, to: 0.34, y: 0.343, slope: 0.03), word("$34.00", x: 0.75, to: 0.89, y: 0.344),
            word("1 Fried Dorade", x: 0.05, to: 0.34, y: 0.314, slope: 0.03), word("$75.00", x: 0.75, to: 0.89, y: 0.316),
            word("1 Passion Fruit Gelato", x: 0.05, to: 0.49, y: 0.288, slope: 0.03), word("$14.00", x: 0.75, to: 0.89, y: 0.288),
        ]
        XCTAssertEqual(ReceiptParser.groupLines(words), ["1 Beef Tartare\t$34.00", "1 Fried Dorade\t$75.00", "1 Passion Fruit Gelato\t$14.00"])
    }

    /// A quantity column too far left to join the name as a phrase, sitting a little below the name's row: it used
    /// to become a line of its own after the item and went to the next one.
    func testLoneQuantityJoinsTheNameOnItsRow() {
        let words = [
            word("3", x: 0.10, to: 0.12, y: 0.496), word("雪碧", x: 0.17, to: 0.28, y: 0.50), word("$5.85", x: 0.71, to: 0.86, y: 0.50),
            word("1", x: 0.10, to: 0.12, y: 0.466), word("秘制口水鸡", x: 0.17, to: 0.40, y: 0.47), word("$7.95", x: 0.71, to: 0.86, y: 0.47),
        ]
        XCTAssertEqual(ReceiptParser.groupLines(words), ["3\t雪碧\t$5.85", "1\t秘制口水鸡\t$7.95"])
    }
}
