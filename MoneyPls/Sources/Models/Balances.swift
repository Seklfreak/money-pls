import Foundation

/// Where one friend stands with me. Positive cents = they owe me, negative = I owe them.
/// Currencies never mix and never convert: a euro debt and a dollar debt stay two numbers.
struct FriendBalance: Identifiable {
    let friend: Friend
    var byCurrency: [String: Int]
    var id: UUID { friend.id }

    /// What is still open, ignoring direction — what the list sorts on.
    var openMagnitude: Int { byCurrency.values.reduce(0) { $0 + abs($1) } }
    var isClear: Bool { openMagnitude == 0 }
}

/// One row of a friend's history with me.
enum LedgerEntry: Identifiable {
    /// A split we were both on. `cents` is signed: + they owe me, − I owe them.
    case split(Split, cents: Int, settled: Bool)
    case payment(Payment)

    var date: Date {
        switch self {
        case .split(let split, _, _): split.createdAt
        case .payment(let payment): payment.date
        }
    }
    var id: UUID {
        switch self {
        case .split(let split, _, _): split.id
        case .payment(let payment): payment.id
        }
    }
}

extension Money {
    /// Everyone I have an open (or freshly closed) line with, biggest debt first.
    ///
    /// Pure: hand it the rows, it hands back the numbers — no fetching in here, so it is testable.
    static func balances(splits: [Split], payments: [Payment], me: Friend) -> [FriendBalance] {
        var found: [UUID: Friend] = [:]
        var totals: [UUID: [String: Int]] = [:]
        func add(_ friend: Friend, _ code: String, _ cents: Int) {
            found[friend.id] = friend
            totals[friend.id, default: [:]][code, default: 0] += cents
        }

        for split in splits where split.people.count >= 2 {
            guard let payer = split.payer else { continue }
            let bills = Money.bills(for: split)
            if payer.friend?.id == me.id {
                // I paid: everyone else owes me their share, unless the per-bill toggle already covers them.
                for bill in bills where bill.person.id != payer.id && !bill.person.settled {
                    guard let friend = bill.person.friend, friend.id != me.id else { continue }
                    add(friend, split.currencyCode, bill.totalCents)
                }
            } else if let creditor = payer.friend, creditor.id != me.id,
                      let mine = bills.first(where: { $0.person.friend?.id == me.id }), !mine.person.settled {
                add(creditor, split.currencyCode, -mine.totalCents)
            }
            // A split I'm not on is somebody else's arithmetic — it never touches my balances.
        }

        // Split-linked payments are skipped on purpose: they only mirror that split's `settled`
        // flag, which the loop above already honours. Counting both would settle the same bill twice.
        for payment in payments where payment.split == nil && payment.cents != 0 {
            if payment.fromFriend?.id == me.id, let friend = payment.toFriend, friend.id != me.id {
                add(friend, payment.currencyCode, payment.cents)     // I paid them: less that I owe, or more that they do
            } else if payment.toFriend?.id == me.id, let friend = payment.fromFriend, friend.id != me.id {
                add(friend, payment.currencyCode, -payment.cents)    // they paid me: less that they owe
            }
        }

        return found.values.map { FriendBalance(friend: $0, byCurrency: totals[$0.id] ?? [:]) }
            .sorted {
                $0.openMagnitude != $1.openMagnitude
                    ? $0.openMagnitude > $1.openMagnitude
                    : $0.friend.name.localizedCaseInsensitiveCompare($1.friend.name) == .orderedAscending
            }
    }

    /// The two headline numbers, per currency. Both sides are positive amounts.
    static func overall(_ balances: [FriendBalance]) -> (owedToMe: [String: Int], iOwe: [String: Int]) {
        var owedToMe: [String: Int] = [:], iOwe: [String: Int] = [:]
        for balance in balances {
            for (code, cents) in balance.byCurrency where cents != 0 {
                if cents > 0 { owedToMe[code, default: 0] += cents } else { iOwe[code, default: 0] -= cents }
            }
        }
        return (owedToMe, iOwe)
    }

    /// One friend's history with me, newest first.
    ///
    /// Only standalone settle-ups show up as payments: a split-linked one is already the split
    /// row's own ✓, and listing it twice would read like they paid me twice.
    static func ledger(for friend: Friend, splits: [Split], payments: [Payment], me: Friend) -> [LedgerEntry] {
        var entries: [LedgerEntry] = []
        for split in splits where split.people.count >= 2 {
            guard let payer = split.payer else { continue }
            let bills = Money.bills(for: split)
            guard let theirs = bills.first(where: { $0.person.friend?.id == friend.id }),
                  let mine = bills.first(where: { $0.person.friend?.id == me.id }) else { continue }
            if payer.friend?.id == me.id, theirs.person.id != payer.id {
                entries.append(.split(split, cents: theirs.totalCents, settled: theirs.person.settled))
            } else if payer.friend?.id == friend.id, mine.person.id != payer.id {
                entries.append(.split(split, cents: -mine.totalCents, settled: mine.person.settled))
            }
        }
        for payment in payments where payment.split == nil {
            let pair: [UUID?] = [payment.fromFriend?.id, payment.toFriend?.id]
            if pair.contains(friend.id) && pair.contains(me.id) { entries.append(.payment(payment)) }
        }
        return entries.sorted { $0.date > $1.date }
    }

    /// "$42.10 + €18.00" — the phone's own currency first, then alphabetical. Zeroes are dropped.
    static func formatByCurrency(_ byCurrency: [String: Int]) -> String {
        let mine = Currency.default
        return byCurrency.filter { $0.value != 0 }
            .sorted {
                ($0.key == mine) != ($1.key == mine) ? $0.key == mine : $0.key < $1.key
            }
            .map { $0.value.money($0.key) }
            .joined(separator: " + ")
    }
}
