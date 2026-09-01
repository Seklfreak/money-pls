import SwiftData
import XCTest
@testable import MoneyPls

/// Opens a store written by the V1 schema — what shipped before Friends existed — and checks that
/// migrating it keeps every row and fills the new ones in. Existing TestFlight installs run this path.
final class MigrationTests: XCTestCase {
    private var storeURL: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        storeURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        suite = "MigrationTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removePersistentDomain(forName: suite)
        for url in [storeURL!, storeURL.appendingPathExtension("shm"), storeURL.appendingPathExtension("wal")] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Writes the old shape: two splits, "Me" paid both, Ann is already ticked off.
    private func writeV1Store() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: storeURL))
        let context = ModelContext(container)

        func make(_ title: String, at date: Date, with them: SchemaV1.Person, total: Int) {
            let split = SchemaV1.Split(title: title)
            split.createdAt = date
            context.insert(split)
            let me = SchemaV1.Person(name: "Me", colorIndex: 0, order: 0)
            split.people.append(contentsOf: [me, them])
            split.payerID = me.id
            split.items.append(SchemaV1.LineItem(name: "Dinner", quantity: 1, priceCents: total, order: 0))
        }
        let ann = SchemaV1.Person(name: "Ann", colorIndex: 1, order: 1)
        ann.settled = true
        make("Hot pot", at: Date(timeIntervalSince1970: 1_000), with: ann, total: 2000)
        make("Bar", at: Date(timeIntervalSince1970: 2_000), with: SchemaV1.Person(name: "Bo", colorIndex: 2, order: 1), total: 1000)
        try context.save()
    }

    private func openV2() throws -> ModelContext {
        let schema = ModelStore.schema
        let container = try ModelContainer(for: schema, migrationPlan: MoneyPlsMigrationPlan.self,
                                          configurations: ModelConfiguration(schema: schema, url: storeURL))
        return ModelContext(container)
    }

    func testV1StoreMigratesAndBackfills() throws {
        try writeV1Store()
        let context = try openV2()
        FriendsBackfill.run(in: context, defaults: defaults)

        // Nothing lost.
        let splits = try context.fetch(FetchDescriptor<Split>(sortBy: [SortDescriptor(\.createdAt)]))
        XCTAssertEqual(splits.map(\.title), ["Hot pot", "Bar"])
        XCTAssertEqual(splits.map(\.totalCents), [2000, 1000])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<LineItem>()), 2)
        XCTAssertEqual(splits[0].sortedPeople[1].settled, true)
        XCTAssertEqual(splits[0].splitKind, .scanned)

        // One Friend per name, everyone linked, and "Me" elected as me.
        let friends = try context.fetch(FetchDescriptor<Friend>())
        XCTAssertEqual(Set(friends.map(\.name)), ["Me", "Ann", "Bo"])
        XCTAssertEqual(friends.first { $0.isMe }?.name, "Me")
        XCTAssertTrue(splits.flatMap(\.people).allSatisfy { $0.friend != nil })
        XCTAssertEqual(friends.first { $0.name == "Ann" }?.colorIndex, 1)

        // The one ticked-off person became a payment, linked to its split.
        let payments = try context.fetch(FetchDescriptor<Payment>())
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(payments.first?.fromFriend?.name, "Ann")
        XCTAssertEqual(payments.first?.toFriend?.name, "Me")
        XCTAssertEqual(payments.first?.cents, 1000)
        XCTAssertEqual(payments.first?.split?.id, splits[0].id)

        // Balances read straight off the migrated store: Ann is settled, Bo still owes half of the bar.
        let me = try XCTUnwrap(Friend.me(in: context))
        let balances = Money.balances(splits: splits, payments: payments, me: me)
        XCTAssertEqual(balances.map { $0.friend.name }, ["Bo"])
        XCTAssertEqual(balances.first?.byCurrency["USD"], 500)
    }

    func testBackfillOnlyRunsOnce() throws {
        try writeV1Store()
        let context = try openV2()
        FriendsBackfill.run(in: context, defaults: defaults)
        FriendsBackfill.run(in: context, defaults: defaults)
        // Even with the flag cleared, the "there are already Friends" guard holds.
        defaults.removeObject(forKey: "friendsBackfillDone")
        FriendsBackfill.run(in: context, defaults: defaults)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Friend>()), 3)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Payment>()), 1)
    }
}
