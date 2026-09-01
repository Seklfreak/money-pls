import SwiftData
import XCTest
@testable import MoneyPls

/// The balance engine, on an in-memory store. Every case here is a rule from `Money.balances`
/// that a screen would otherwise have to re-derive by hand.
final class BalancesTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var me: Friend!

    override func setUpWithError() throws {
        container = try ModelStore.container(inMemory: true)
        context = ModelContext(container)
        me = friend("Me")
        me.isMe = true
    }

    override func tearDown() {
        container = nil
        context = nil
        me = nil
    }

    // MARK: - Fixtures

    @discardableResult
    private func friend(_ name: String, color: Int = 0) -> Friend {
        let f = Friend(name: name, colorIndex: color)
        context.insert(f)
        return f
    }

    /// One shared item of `total`, split evenly; the first friend listed paid.
    @discardableResult
    private func split(_ title: String, total: Int, paidBy payer: Friend, with others: [Friend],
                       currency: String = "USD", on date: Date = Date()) -> Split {
        let s = Split(title: title)
        s.currencyCode = currency
        s.createdAt = date
        context.insert(s)
        for (i, f) in ([payer] + others).enumerated() {
            let p = Person(name: f.name, colorIndex: f.colorIndex, order: i)
            p.friend = f
            s.people.append(p)
        }
        s.payerID = s.sortedPeople.first?.id
        s.items.append(LineItem(name: "Dinner", quantity: 1, priceCents: total, order: 0))
        return s
    }

    private func balance(_ friend: Friend, _ splits: [Split], _ payments: [Payment] = []) -> [String: Int] {
        Money.balances(splits: splits, payments: payments, me: me)
            .first { $0.friend.id == friend.id }?.byCurrency ?? [:]
    }

    // MARK: - Splits

    func testIPaidSoTheyOweMe() {
        let ann = friend("Ann", color: 1)
        let s = split("Dinner", total: 2000, paidBy: me, with: [ann])
        XCTAssertEqual(balance(ann, [s])["USD"], 1000)
    }

    func testFriendPaidSoIOweThem() {
        let ann = friend("Ann", color: 1)
        let s = split("Brunch", total: 3000, paidBy: ann, with: [me])
        XCTAssertEqual(balance(ann, [s])["USD"], -1500)
    }

    func testSettledPersonIsExcluded() {
        let ann = friend("Ann", color: 1)
        let s = split("Dinner", total: 2000, paidBy: me, with: [ann])
        s.sortedPeople[1].settled = true
        XCTAssertTrue(Money.balances(splits: [s], payments: [], me: me).isEmpty)
    }

    func testSplitIAmNotOnIsIgnored() {
        let ann = friend("Ann", color: 1), bo = friend("Bo", color: 2)
        let s = split("Their lunch", total: 2000, paidBy: ann, with: [bo])
        XCTAssertTrue(Money.balances(splits: [s], payments: [], me: me).isEmpty)
    }

    // MARK: - Payments

    func testGeneralPaymentReducesTheBalance() {
        let ann = friend("Ann", color: 1)
        let s = split("Dinner", total: 2000, paidBy: me, with: [ann])
        let paid = Payment(from: ann, to: me, cents: 400, currencyCode: "USD")
        context.insert(paid)
        XCTAssertEqual(balance(ann, [s], [paid])["USD"], 600)
    }

    func testPaymentFromMeMakesThemOweMe() {
        let ann = friend("Ann", color: 1)
        let paid = Payment(from: me, to: ann, cents: 750, currencyCode: "USD")
        context.insert(paid)
        XCTAssertEqual(balance(ann, [], [paid])["USD"], 750)
    }

    func testSplitLinkedPaymentIsIgnored() {
        let ann = friend("Ann", color: 1)
        let s = split("Dinner", total: 2000, paidBy: me, with: [ann])
        // The per-bill toggle writes both; only `settled` may move the balance.
        let paid = Payment(from: ann, to: me, cents: 1000, currencyCode: "USD", split: s)
        context.insert(paid)
        XCTAssertEqual(balance(ann, [s], [paid])["USD"], 1000)
    }

    // MARK: - Currencies and totals

    func testCurrenciesStaySeparate() {
        let ann = friend("Ann", color: 1)
        let dollars = split("Dinner", total: 2000, paidBy: me, with: [ann])
        let euros = split("Bar", total: 3000, paidBy: ann, with: [me], currency: "EUR")
        let byCurrency = balance(ann, [dollars, euros])
        XCTAssertEqual(byCurrency["USD"], 1000)
        XCTAssertEqual(byCurrency["EUR"], -1500)
        XCTAssertEqual(byCurrency.count, 2)
    }

    func testOverallTotals() {
        let ann = friend("Ann", color: 1), bo = friend("Bo", color: 2)
        let mine = split("Dinner", total: 2000, paidBy: me, with: [ann])
        let theirs = split("Bar", total: 3000, paidBy: bo, with: [me], currency: "EUR")
        let totals = Money.overall(Money.balances(splits: [mine, theirs], payments: [], me: me))
        XCTAssertEqual(totals.owedToMe, ["USD": 1000])
        XCTAssertEqual(totals.iOwe, ["EUR": 1500])
    }

    func testBiggestBalanceSortsFirst() {
        let ann = friend("Ann", color: 1), bo = friend("Bo", color: 2)
        let small = split("Coffee", total: 400, paidBy: me, with: [ann])
        let big = split("Dinner", total: 9000, paidBy: me, with: [bo])
        XCTAssertEqual(Money.balances(splits: [small, big], payments: [], me: me).map { $0.friend.name }, ["Bo", "Ann"])
    }

    // MARK: - Ledger

    func testLedgerIsNewestFirstAndSigned() {
        let ann = friend("Ann", color: 1)
        let old = split("Dinner", total: 2000, paidBy: me, with: [ann], on: Date(timeIntervalSince1970: 1_000))
        let new = split("Brunch", total: 3000, paidBy: ann, with: [me], on: Date(timeIntervalSince1970: 3_000))
        let paid = Payment(from: ann, to: me, cents: 500, currencyCode: "USD", date: Date(timeIntervalSince1970: 2_000))
        context.insert(paid)
        let entries = Money.ledger(for: ann, splits: [old, new], payments: [paid], me: me)
        XCTAssertEqual(entries.count, 3)
        guard case .split(let first, let firstCents, let firstSettled) = entries[0] else { return XCTFail("expected a split first") }
        XCTAssertEqual(first.id, new.id)
        XCTAssertEqual(firstCents, -1500)
        XCTAssertFalse(firstSettled)
        guard case .payment = entries[1] else { return XCTFail("expected the payment in the middle") }
        guard case .split(let last, let lastCents, _) = entries[2] else { return XCTFail("expected a split last") }
        XCTAssertEqual(last.id, old.id)
        XCTAssertEqual(lastCents, 1000)
    }

    func testLedgerSkipsSplitLinkedPayments() {
        let ann = friend("Ann", color: 1)
        let s = split("Dinner", total: 2000, paidBy: me, with: [ann])
        let paid = Payment(from: ann, to: me, cents: 1000, currencyCode: "USD", split: s)
        context.insert(paid)
        XCTAssertEqual(Money.ledger(for: ann, splits: [s], payments: [paid], me: me).count, 1)
    }

    // MARK: - Formatting

    func testFormatByCurrencyPutsThePhoneCurrencyFirst() {
        let mine = Currency.default
        let other = mine == "EUR" ? "USD" : "EUR"
        XCTAssertEqual(Money.formatByCurrency([other: 1800, mine: 4210]),
                       "\(4210.money(mine)) + \(1800.money(other))")
    }

    func testFormatByCurrencyDropsZeroes() {
        XCTAssertEqual(Money.formatByCurrency([:]), "")
        XCTAssertEqual(Money.formatByCurrency(["USD": 0, "EUR": 1800]), 1800.money("EUR"))
    }
}
