import Foundation

/// One line on a person's bill.
struct ShareLine: Identifiable {
    let id = UUID()
    let label: String
    let cents: Int
}

struct PersonBill: Identifiable {
    let person: Person
    var id: UUID { person.id }
    var lines: [ShareLine]
    var itemCents: Int
    var taxTipCents: Int
    var totalCents: Int { itemCents + taxTipCents }
}

enum Money {
    /// Split `cents` into `n` parts that sum exactly. `offset` rotates who gets the extra pennies so they
    /// don't all land on the same people across a long receipt.
    static func divide(_ cents: Int, into n: Int, offset: Int = 0) -> [Int] {
        guard n > 0 else { return [] }
        let base = cents / n, rem = cents - base * n
        return (0..<n).map { base + (((($0 - offset) % n) + n) % n < rem ? 1 : 0) }
    }

    /// Allocate `cents` across weights so the parts sum exactly (largest remainder).
    static func allocate(_ cents: Int, weights: [Int]) -> [Int] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return Money.divide(cents, into: weights.count) }
        var parts = weights.map { Double(cents) * Double($0) / Double(total) }
        var floors = parts.map { Int($0.rounded(.down)) }
        var left = cents - floors.reduce(0, +)
        let order = parts.indices.sorted { (parts[$0] - parts[$0].rounded(.down)) > (parts[$1] - parts[$1].rounded(.down)) }
        for i in order where left > 0 { floors[i] += 1; left -= 1 }
        parts = []
        return floors
    }

    static func fraction(_ n: Int) -> String {
        switch n { case 2: "½"; case 3: "⅓"; case 4: "¼"; case 5: "⅕"; case 6: "⅙"; case 8: "⅛"; default: "1/\(n)" }
    }

    /// Per-person bills for a split. Shared-by-everyone items are collapsed into one "N shared plates" line.
    static func bills(for split: Split) -> [PersonBill] {
        let people = split.sortedPeople
        guard !people.isEmpty else { return [] }
        var lines: [UUID: [ShareLine]] = [:]
        var sharedCents: [UUID: Int] = [:]
        var sharedCount = 0
        var itemCents: [UUID: Int] = [:]
        for p in people { lines[p.id] = []; sharedCents[p.id] = 0; itemCents[p.id] = 0 }

        for (index, item) in split.sortedItems.enumerated() {
            let ids: [UUID] = item.everyone ? people.map(\.id) : people.map(\.id).filter { item.assigneeIDs.contains($0) }
            guard !ids.isEmpty else { continue }
            let parts = divide(item.priceCents, into: ids.count, offset: index)
            if item.everyone && people.count > 1 {
                sharedCount += 1
                for (i, id) in ids.enumerated() { sharedCents[id, default: 0] += parts[i]; itemCents[id, default: 0] += parts[i] }
            } else {
                for (i, id) in ids.enumerated() {
                    let label = ids.count > 1 ? "\(item.displayName) · \(fraction(ids.count))" : item.displayName
                    lines[id, default: []].append(ShareLine(label: label, cents: parts[i]))
                    itemCents[id, default: 0] += parts[i]
                }
            }
        }
        let weights = people.map { itemCents[$0.id] ?? 0 }
        let taxTip = allocate(split.taxCents + split.tipCents, weights: weights)
        return people.enumerated().map { i, p in
            var l = lines[p.id] ?? []
            if let s = sharedCents[p.id], sharedCount > 0 {
                l.append(ShareLine(label: sharedCount == 1 ? "1 shared plate" : "\(sharedCount) shared plates", cents: s))
            }
            if taxTip[i] > 0 { l.append(ShareLine(label: split.tipCents > 0 ? "Tax + tip" : "Tax", cents: taxTip[i])) }
            return PersonBill(person: p, lines: l, itemCents: itemCents[p.id] ?? 0, taxTipCents: taxTip[i])
        }
    }

    /// What everyone but the payer still owes.
    static func outstanding(for split: Split) -> Int {
        let payer = split.payer?.id
        return bills(for: split).filter { $0.person.id != payer && !$0.person.paid }.reduce(0) { $0 + $1.totalCents }
    }
}
