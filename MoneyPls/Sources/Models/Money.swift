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
    static func allocate(_ cents: Int, weights: [Double]) -> [Int] {
        let total = weights.reduce(0, +)
        guard total > 0 else { return Money.divide(cents, into: weights.count) }
        let parts = weights.map { Double(cents) * $0 / total }
        var floors = parts.map { Int($0.rounded(.down)) }
        var left = cents - floors.reduce(0, +)
        let order = parts.indices.sorted { (parts[$0] - parts[$0].rounded(.down)) > (parts[$1] - parts[$1].rounded(.down)) }
        for i in order where left > 0 { floors[i] += 1; left -= 1 }
        return floors
    }

    static func fraction(_ n: Int) -> String {
        switch n {
        case 2: "½"
        case 3: "⅓"
        case 4: "¼"
        case 5: "⅕"
        case 6: "⅙"
        case 8: "⅛"
        default: "1/\(n)"
        }
    }

    /// Per-person bills for a split. Shared-by-everyone items are collapsed into one "N shared plates" line.
    ///
    /// Rounding happens once, on each person's exact total, not once per line: splitting 30 plates seven ways
    /// line by line leaves the same people with the spare pennies again and again, and equal shares end up
    /// several cents apart. Only the visible solo/partial lines are rounded individually; the shared pool and
    /// tax absorb the difference so every total is within a cent of exact.
    static func bills(for split: Split) -> [PersonBill] {
        let people = split.sortedPeople
        guard !people.isEmpty else { return [] }
        let n = people.count
        var lines: [[ShareLine]] = Array(repeating: [], count: n)
        var soloCents = Array(repeating: 0, count: n)
        var sharedExact = Array(repeating: 0.0, count: n)
        var sharedCount = 0
        var itemsTotal = 0

        for (index, item) in split.sortedItems.enumerated() {
            let idx: [Int] = item.everyone ? Array(0..<n) : people.indices.filter { item.assigneeIDs.contains(people[$0].id) }
            guard !idx.isEmpty else { continue }
            itemsTotal += item.priceCents
            if item.everyone && n > 1 {
                sharedCount += 1
                for i in idx { sharedExact[i] += Double(item.priceCents) / Double(n) }
            } else {
                let parts = divide(item.priceCents, into: idx.count, offset: index)
                for (k, i) in idx.enumerated() {
                    let label = idx.count > 1 ? "\(item.displayName) · \(fraction(idx.count))" : item.displayName
                    lines[i].append(ShareLine(label: label, cents: parts[k]))
                    soloCents[i] += parts[k]
                }
            }
        }
        let itemExact = (0..<n).map { Double(soloCents[$0]) + sharedExact[$0] }
        let taxTipTotal = split.taxCents + split.tipCents
        let itemsSum = itemExact.reduce(0, +)
        let taxExact = itemExact.map { itemsSum > 0 ? Double(taxTipTotal) * $0 / itemsSum : Double(taxTipTotal) / Double(n) }
        let itemCents = allocate(itemsTotal, weights: itemExact)
        var totalCents = allocate(itemsTotal + taxTipTotal, weights: (0..<n).map { itemExact[$0] + taxExact[$0] })
        var taxTip = (0..<n).map { totalCents[$0] - itemCents[$0] }
        if taxTip.contains(where: { $0 < 0 }) {   // sub-cent tax rounded the other way: fall back to a plain proportional split
            taxTip = allocate(taxTipTotal, weights: itemExact)
            totalCents = (0..<n).map { itemCents[$0] + taxTip[$0] }
        }
        return people.enumerated().map { i, p in
            var l = lines[i]
            if sharedCount > 0 {
                l.append(ShareLine(label: sharedCount == 1 ? "1 shared plate" : "\(sharedCount) shared plates", cents: itemCents[i] - soloCents[i]))
            }
            if taxTip[i] > 0 { l.append(ShareLine(label: split.tipCents > 0 ? "Tax + tip" : "Tax", cents: taxTip[i])) }
            return PersonBill(person: p, lines: l, itemCents: itemCents[i], taxTipCents: taxTip[i])
        }
    }

    /// What everyone but the payer still owes.
    static func outstanding(for split: Split) -> Int {
        let payer = split.payer?.id
        return bills(for: split).filter { $0.person.id != payer && !$0.person.settled }.reduce(0) { $0 + $1.totalCents }
    }
}
