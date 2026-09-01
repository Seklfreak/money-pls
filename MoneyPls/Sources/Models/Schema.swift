import Foundation
import SwiftData

/// Schema history and the store that opens it.
///
/// V1 is what the first TestFlight builds wrote: splits, people, line items. V2 adds `Friend`,
/// `Payment` and the fields hanging off them — new optional properties and new entities only, so
/// SwiftData can migrate it lightweight. The V1 copies below are frozen on purpose: they describe
/// the bytes already on people's phones, so they must never be "kept in sync" with Models.swift.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [Split.self, Person.self, LineItem.self] }

    @Model
    final class Split {
        @Attribute(.unique) var id: UUID = UUID()
        var title: String = ""
        var createdAt: Date = Date()
        var taxCents: Int = 0
        var tipCents: Int = 0
        var currencyCode: String = "USD"
        var payerID: UUID?
        var printedSubtotalCents: Int?
        @Attribute(.externalStorage) var receiptImage: Data?
        @Attribute(.externalStorage) var parseTrace: String?
        @Relationship(deleteRule: .cascade, inverse: \LineItem.split) var items: [LineItem] = []
        @Relationship(deleteRule: .cascade, inverse: \Person.split) var people: [Person] = []

        init(title: String) { self.title = title }
    }

    @Model
    final class Person {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var colorIndex: Int = 0
        var order: Int = 0
        @Attribute(originalName: "paid") var settled: Bool = false
        var split: Split?

        init(name: String, colorIndex: Int, order: Int) { self.name = name; self.colorIndex = colorIndex; self.order = order }
    }

    @Model
    final class LineItem {
        @Attribute(.unique) var id: UUID = UUID()
        var name: String = ""
        var quantity: Int = 1
        var priceCents: Int = 0
        var order: Int = 0
        var everyone: Bool = true
        var assigneeIDs: [UUID] = []
        var translatedName: String?
        var split: Split?

        init(name: String, quantity: Int, priceCents: Int, order: Int) {
            self.name = name; self.quantity = quantity; self.priceCents = priceCents; self.order = order
        }
    }
}

/// The live models — the ones in Models.swift and Friends.swift.
enum SchemaV2: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }
    static var models: [any PersistentModel.Type] { [Split.self, Person.self, LineItem.self, Friend.self, Payment.self] }
}

enum MoneyPlsMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self, SchemaV2.self] }
    // Lightweight is enough: V2 only adds entities and optional/defaulted properties. Filling the
    // new rows in from the old ones is `FriendsBackfill`, which runs once after the store opens —
    // a lightweight stage has no hook to do it in.
    static var stages: [MigrationStage] { [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)] }
}

enum ModelStore {
    static var schema: Schema { Schema(versionedSchema: SchemaV2.self) }

    /// Built by hand rather than with `.modelContainer(for:)` so the migration plan is in play.
    static func container(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Self.schema
        return try ModelContainer(for: schema, migrationPlan: MoneyPlsMigrationPlan.self,
                                  configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory))
    }
}

/// One-time upgrade of a pre-Friends store: every `Person` gets the `Friend` it always meant,
/// one of them is you, and anything already ticked off becomes a payment.
enum FriendsBackfill {
    private static let flagKey = "friendsBackfillDone"

    /// Guarded twice — the flag, and "there are no Friends yet" — so a run that died halfway
    /// through (or a store restored onto a fresh install) can't mint a second set of friends.
    static func run(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: flagKey) else { return }
        defer { defaults.set(true, forKey: flagKey) }
        guard (try? context.fetchCount(FetchDescriptor<Friend>())) == 0 else { return }

        let people = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        guard !people.isEmpty else { return }
        let splits = (try? context.fetch(FetchDescriptor<Split>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []

        // Oldest split first, so the spelling and colour that stick are the ones from the first time.
        var friends: [String: Friend] = [:]
        for person in people.sorted(by: { ($0.split?.createdAt ?? .distantPast, $0.order) < ($1.split?.createdAt ?? .distantPast, $1.order) }) {
            let key = Self.key(person.name)
            guard !key.isEmpty else { continue }
            if let known = friends[key] {
                person.friend = known
            } else {
                let friend = Friend(name: person.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                    colorIndex: person.colorIndex, createdAt: person.split?.createdAt ?? Date())
                context.insert(friend)
                friends[key] = friend
                person.friend = friend
            }
        }

        let me = electMe(splits: splits, friends: friends)
        me?.isMe = true

        // A ticked-off person is a payment that already happened; write it down so it shows up in
        // their history. `settled` stays the source of truth for balances, so these are ignored there.
        for split in splits where split.people.count >= 2 {
            let payerID = split.payer?.id
            guard let payee = split.payer?.friend ?? me else { continue }
            for bill in Money.bills(for: split) where bill.person.settled && bill.person.id != payerID {
                guard let payer = bill.person.friend, payer.id != payee.id else { continue }
                context.insert(Payment(from: payer, to: payee, cents: bill.totalCents,
                                       currencyCode: split.currencyCode, date: split.createdAt, split: split))
            }
        }
        try? context.save()
    }

    /// You are whoever paid most often; a tie goes to whoever paid the most recent split.
    private static func electMe(splits: [Split], friends: [String: Friend]) -> Friend? {
        var counts: [String: Int] = [:]
        for split in splits {
            let key = Self.key(split.payer?.name ?? "")
            if !key.isEmpty { counts[key, default: 0] += 1 }
        }
        guard let best = counts.values.max() else { return nil }
        let leaders = counts.filter { $0.value == best }.map(\.key)
        if leaders.count > 1, let latest = splits.reversed().compactMap({ $0.payer?.name }).map(Self.key).first(where: leaders.contains) {
            return friends[latest]
        }
        return leaders.sorted().first.flatMap { friends[$0] }
    }

    private static func key(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
