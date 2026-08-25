import Foundation
import FoundationModels

/// Optional on-device LLM pass, used only when the deterministic parse doesn't reconcile with the
/// printed subtotal. Its answer is accepted only if it reconciles exactly: the model drops items and
/// misreads names with numbers in them ("10 Second Beef Tongue" becomes ten beef tongues), so a
/// "closer but still wrong" answer would replace one wrong line with several.
enum ReceiptRepair {
    @Generable struct Item {
        @Guide(description: "Count from the quantity column; 1 if not printed. A number that is part of the name (\"10 Second Beef Tongue\", \"7 Up\") is not a quantity") var quantity: Int
        @Guide(description: "Item name exactly as printed, without Chinese characters") var name: String
        @Guide(description: "Line total in dollars exactly as printed; never compute or invent") var price: Double
    }
    @Generable struct Receipt {
        @Guide(description: "Every purchased line item in printed order. Exclude subtotal, tax, tip, total and suggested-tip lines.") var items: [Item]
        var subtotal: Double?
        var tax: Double?
        @Guide(description: "Tip only if actually charged") var tip: Double?
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func repair(_ parsed: ParsedReceipt) async -> ParsedReceipt? {
        guard isAvailable, let subtotal = parsed.subtotalCents else { return nil }
        let session = LanguageModelSession(instructions: """
        You convert OCR text of a receipt into structured data. Copy numbers exactly as printed; do not compute or invent values. \
        Lines with a name and a trailing price are purchased items. Ignore address, phone, order numbers, suggested tips and 'you pay' lines.
        """)
        let latin = parsed.lines.map { Heuristics.stripHan($0.replacingOccurrences(of: "\t", with: "  ")) }.filter { !$0.isEmpty }
        // The plain-English framing sentence matters: bare receipt text trips the model's language guard.
        let prompt = "Here is the text of a restaurant receipt, read line by line by OCR. Please extract the purchased items, subtotal, tax and tip.\n\n" + latin.joined(separator: "\n")
        guard let out = try? await session.respond(to: prompt, generating: Receipt.self).content else { return nil }
        var fixed = parsed
        fixed.items = out.items.map { ParsedItem(name: $0.name, quantity: max(1, $0.quantity), priceCents: Int(($0.price * 100).rounded())) }
        guard fixed.itemSumCents == subtotal, !fixed.items.isEmpty else { return nil }
        // Where the model agrees with the deterministic parse on name and price, keep the deterministic quantity.
        fixed.items = fixed.items.map { item in
            guard let match = parsed.items.first(where: { $0.priceCents == item.priceCents && $0.name.caseInsensitiveCompare(item.name) == .orderedSame }) else { return item }
            return ParsedItem(name: match.name, quantity: match.quantity, priceCents: item.priceCents)
        }
        return fixed
    }
}
