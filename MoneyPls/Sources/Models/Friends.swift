import Foundation
import SwiftData

/// A person you split with, the same row across every split — where the running balance hangs off.
/// `Person` stays the per-split copy (its name and colour are frozen into the split it belongs to);
/// `Friend` is the identity behind it.
@Model
final class Friend {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var colorIndex: Int = 0
    var createdAt: Date = Date()
    /// The one friend that is you. Every balance is "them vs me", so exactly one row carries this.
    var isMe: Bool = false
    /// `CNContact.identifier`, when the friend came out of the address book. Nothing reads it yet.
    var contactIdentifier: String?
    @Relationship(deleteRule: .nullify, inverse: \Person.friend) var people: [Person] = []
    // Two relationships point at Friend from Payment; spelling both inverses out keeps SwiftData
    // from pairing them the wrong way round.
    @Relationship(deleteRule: .nullify, inverse: \Payment.fromFriend) var paymentsSent: [Payment] = []
    @Relationship(deleteRule: .nullify, inverse: \Payment.toFriend) var paymentsReceived: [Payment] = []

    init(name: String, colorIndex: Int, createdAt: Date = Date()) {
        self.name = name; self.colorIndex = colorIndex; self.createdAt = createdAt
    }

    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
    /// Last split this friend appeared on — what the "usual suspects" list sorts on.
    var lastUsedAt: Date { people.compactMap { $0.split?.createdAt }.max() ?? createdAt }
}

extension Friend {
    /// You. Nil until something has decided who that is (the backfill, or the You sheet).
    static func me(in context: ModelContext) -> Friend? {
        var d = FetchDescriptor<Friend>(predicate: #Predicate { $0.isMe })
        d.fetchLimit = 1
        return try? context.fetch(d).first
    }

    /// The friend behind a typed name: same name (trimmed, case-insensitive) means the same person.
    /// `preferredColor` only applies when the friend is new — an existing one keeps its colour.
    static func resolve(name: String, in context: ModelContext, preferredColor: Int? = nil) -> Friend {
        let clean = String(name.trimmingCharacters(in: .whitespaces).prefix(24))
        let known = (try? context.fetch(FetchDescriptor<Friend>())) ?? []
        if let hit = known.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { return hit }
        let friend = Friend(name: clean, colorIndex: preferredColor ?? known.count)
        context.insert(friend)
        return friend
    }
}

/// Money that actually changed hands: a settle-up, or the per-bill "paid" toggle writing down what it means.
@Model
final class Payment {
    @Attribute(.unique) var id: UUID = UUID()
    var fromFriend: Friend?
    var toFriend: Friend?
    var cents: Int = 0
    var currencyCode: String = "USD"
    var date: Date = Date()
    var note: String = ""
    /// Set when the per-bill "mark paid" toggle created this. Nil for a general settle-up.
    /// Balances skip these on purpose — see `Money.balances`.
    var split: Split?

    init(from: Friend?, to: Friend?, cents: Int, currencyCode: String, date: Date = Date(), note: String = "", split: Split? = nil) {
        self.fromFriend = from; self.toFriend = to; self.cents = cents
        self.currencyCode = currencyCode; self.date = date; self.note = note; self.split = split
    }
}

/// Where a split came from. Stored as a string so a new case can't break an old store.
enum SplitKind: String {
    case scanned
    case typed
}
