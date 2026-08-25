import Foundation
import SwiftData

@Model
final class Split {
    @Attribute(.unique) var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var taxCents: Int = 0
    var tipCents: Int = 0
    var payerID: UUID?
    /// Subtotal as printed on the receipt, to flag parses that don't add up.
    var printedSubtotalCents: Int?
    @Attribute(.externalStorage) var receiptImage: Data?
    /// Parse log of the scan this split came from, so a bad read can be reported later with the photo.
    @Attribute(.externalStorage) var parseTrace: String?
    @Relationship(deleteRule: .cascade, inverse: \LineItem.split) var items: [LineItem] = []
    @Relationship(deleteRule: .cascade, inverse: \Person.split) var people: [Person] = []

    init(title: String) { self.title = title }

    /// Title for display: falls back to a date when the user never named the split.
    var displayTitle: String { title.isEmpty ? "Split on \(createdAt.formatted(.dateTime.month(.abbreviated).day()))" : title }
    var sortedItems: [LineItem] { items.sorted { $0.order < $1.order } }
    var sortedPeople: [Person] { people.sorted { $0.order < $1.order } }
    var payer: Person? { people.first { $0.id == payerID } ?? sortedPeople.first }
    var subtotalCents: Int { items.reduce(0) { $0 + $1.priceCents } }
    var totalCents: Int { subtotalCents + taxCents + tipCents }
    var unassignedItems: [LineItem] { sortedItems.filter { !$0.everyone && $0.assigneeIDs.isEmpty } }
}

@Model
final class Person {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var colorIndex: Int = 0
    var order: Int = 0
    /// Has this person paid the payer back? (Stored under the old name so existing splits keep their state.)
    @Attribute(originalName: "paid") var settled: Bool = false
    var split: Split?

    init(name: String, colorIndex: Int, order: Int) { self.name = name; self.colorIndex = colorIndex; self.order = order }
    var initial: String { String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased() }
}

@Model
final class LineItem {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var quantity: Int = 1
    /// Line total (not unit price), in cents.
    var priceCents: Int = 0
    var order: Int = 0
    /// Default: shared by everyone. When false, `assigneeIDs` lists who had it (empty = nobody, blocks the bill).
    var everyone: Bool = true
    var assigneeIDs: [UUID] = []
    var split: Split?

    init(name: String, quantity: Int, priceCents: Int, order: Int) {
        self.name = name; self.quantity = quantity; self.priceCents = priceCents; self.order = order
    }
    var unitCents: Int { quantity > 0 ? priceCents / quantity : priceCents }
    var displayName: String { quantity > 1 ? "\(name) ×\(quantity)" : name }
}
