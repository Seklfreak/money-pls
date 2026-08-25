import Foundation

// MARK: - Deterministic parser
enum Heuristics {
    /// Currency markers a receipt prints next to a price, before ("$12.99", "CHF 12.90") or after ("12,99 €", "45 kr").
    static let symbolRe = #"(?:[$€£¥₩]|CHF|EUR|USD|GBP|CAD|AUD|SEK|NOK|DKK|kr)"#
    /// A price is a number with decimals, or any number with a currency marker. OCR drops dots ("$799"),
    /// adds spaces ("$18. 99", "$18 99") and receipts abroad use decimal commas and thousands groups ("1.234,50").
    /// Three forms: marker before the number (decimals optional, but a bare integer needs three digits so "Check $21"
    /// stays a check number), marker after the number, or a plain number with decimals.
    static let priceRe = #"(?:"# + symbolRe + #"\s?-?(?:\d{1,3}(?:[.,]\d{3})+(?:[.,] ?\d{2})?|\d{1,5}(?:[.,] ?| )\d{2}|\d{3,5})"#
        + #"|-?\d{1,3}(?:[.,]\d{3})*(?:[.,] ?\d{2})?\s?"# + symbolRe + #"|-?\d{1,5}(?:[.,]\d{3})*[.,] ?\d{2})\s*$"#
    static let noise = ["reprint", "suggested", "you pay", "order:", "order #", "table:", "guests", "qr code", "powered by", "unpaid",
                        "check #", "server", "ticket", "authorization", "receipt:", "station"]
    // Summary-line keywords, English plus the languages of receipts people bring home. CJK ones are matched
    // by containment, Latin ones as whole words.
    // "btotal" / "otal due": the document crop sometimes shaves the first letters off the left column.
    static let subtotalWords = ["subtotal", "sub total", "btotal", "zwischensumme", "sous-total", "subtotaal", "小計", "小计", "소계"]
    static let totalWords = ["total", "otal due", "otal:", "amount due", "balance due", "gesamt", "summe", "totaal", "montant", "合計", "合计", "総計", "합계", "총액"]
    static let taxRe = #"\b(tax|mwst|ust|tva|iva|vat|btw|gst|hst)\b"#
    static let taxWords = ["消費税", "税", "부가세"]
    static let tipRe = #"\b(tip|gratuity|service|trinkgeld|pourboire)\b"#
    static func isSubtotal(_ s: String) -> Bool { subtotalWords.contains { s.contains($0) } }
    static func isTotal(_ s: String) -> Bool { totalWords.contains { s.contains($0) } }
    static func isTax(_ s: String) -> Bool { s.range(of: taxRe, options: .regularExpression) != nil || taxWords.contains { s.contains($0) } }
    static func isTip(_ s: String) -> Bool { s.range(of: tipRe, options: .regularExpression) != nil }

    /// Which currency a symbol on the receipt means. The ambiguous ones ($, ¥, kr) lean on the phone's region.
    static func currency(forSymbol sym: String) -> String {
        let mine = Currency.default
        switch sym {
        case "$": return ["CAD", "AUD", "MXN", "NZD", "SGD", "HKD", "TWD"].contains(mine) ? mine : "USD"
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥": return mine == "CNY" ? "CNY" : "JPY"
        case "₩": return "KRW"
        case "kr": return ["SEK", "NOK", "DKK", "ISK"].contains(mine) ? mine : "SEK"
        default: return sym
        }
    }
    /// The currency the receipt is in: whichever marker its priced lines use most, else the phone's.
    static func detectCurrency(_ lines: [String]) -> String {
        var votes: [String: Int] = [:]
        for l in lines {
            guard let r = l.range(of: priceRe, options: .regularExpression),
                  let m = l[r].range(of: symbolRe, options: .regularExpression) else { continue }
            votes[currency(forSymbol: String(l[r][m])), default: 0] += 1
        }
        return votes.max { $0.value < $1.value }?.key ?? Currency.default
    }

    /// Amount in minor units of a currency with `digits` decimals, plus where the price sits in the line.
    static func money(_ s: String, digits: Int = 2) -> (Int, Range<String.Index>)? {
        guard let r = s.range(of: priceRe, options: .regularExpression) else { return nil }
        var t = s[r].trimmingCharacters(in: .whitespaces)
        let hadSymbol = t.range(of: symbolRe, options: .regularExpression) != nil
        t = t.replacingOccurrences(of: symbolRe, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        if hadSymbol, t.range(of: #"^-?\d{1,5} \d{2}$"#, options: .regularExpression) != nil { t = t.replacingOccurrences(of: " ", with: ".") }   // "$18 99"
        t = t.replacingOccurrences(of: " ", with: "")
        // Separators: with both kinds present the last one is the decimal point; alone, two trailing digits
        // mean decimals and three mean a thousands group ("1,200" is twelve hundred, not 1.20).
        let seps = t.filter { $0 == "." || $0 == "," }
        var integerPart = t, fraction = ""
        if let last = seps.last {
            let lastSep = t.lastIndex(of: last)!
            let tail = String(t[t.index(after: lastSep)...])
            if seps.count == 1 && tail.count == 3 {
                integerPart = t.filter(\.isNumber)
            } else if Set(seps).count == 1 && seps.count > 1 && tail.count == 3 {
                integerPart = t.filter(\.isNumber)
            } else {
                integerPart = String(t[..<lastSep]).filter(\.isNumber); fraction = tail
            }
        }
        guard let whole = Int(integerPart.isEmpty ? "0" : integerPart) else { return nil }
        let negative = t.hasPrefix("-")
        var minor: Int
        if fraction.isEmpty {
            // "$799": a symbol-prefixed integer on a 2-decimal receipt is a price whose dot the OCR dropped.
            minor = hadSymbol && digits == 2 && integerPart.count >= 3 ? whole : whole * Int(pow(10.0, Double(digits)))
        } else {
            let frac = Int(fraction) ?? 0
            minor = digits == 0 ? whole : whole * Int(pow(10.0, Double(digits))) + frac
        }
        return (negative ? -minor : minor, r)
    }
    static func stripHan(_ s: String) -> String {
        s.replacingOccurrences(of: #"\d*[\p{Han}（）()/、·]+\d*"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }
    /// Letters and digits only, lowercased — what two OCR passes reliably agree on for the same name.
    static func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
    /// OCR clips edges ("otus Root" for "LOTUS ROOT"), so containment counts once there is enough to go on.
    static func similar(_ a: String, _ b: String) -> Bool {
        a == b || (min(a.count, b.count) >= 4 && (a.contains(b) || b.contains(a)))
    }
    static func boxes(_ raw: String) -> [String] {
        raw.split(separator: "\t").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func parse(lines: [String]) -> ParsedReceipt {
        var r = ParsedReceipt()
        r.currencyCode = detectCurrency(lines)
        let digits = Currency.minorDigits(r.currencyCode)
        func money(_ s: String) -> (Int, Range<String.Index>)? { Heuristics.money(s, digits: digits) }
        var pendingName: String?
        var pendingQty: Int?
        // A price with no Latin name yet: (price, qty, the CJK text it came with — used as the name if no
        // English line claims it).
        var pendingPrice: (price: Int, qty: Int, name: String?)?
        func flushPending() {
            guard let pp = pendingPrice, let n = pp.name else { return }
            r.items.append(ParsedItem(name: n, quantity: pp.qty, priceCents: pp.price)); pendingPrice = nil
        }
        // A receipt with hardly any Latin lines (Japanese, Chinese-only) names its items in CJK: keep that text
        // instead of treating it as the sub-label of an English line that never comes.
        let latinLines = lines.filter { $0.filter { $0.isLetter && $0.isASCII }.count >= 3 }.count
        let cjkReceipt = latinLines * 4 < lines.count
        func latin(_ s: String) -> String { cjkReceipt ? s.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces) : stripHan(s) }
        let priced = lines.filter { money($0) != nil }
        let leadingInt = priced.filter { $0.range(of: #"^\d{1,2}\s+\D"#, options: .regularExpression) != nil }.count
        let qtyColumn = priced.count >= 3 && leadingInt * 10 >= priced.count * 6

        func dropPending() {
            guard let p = pendingName else { return }
            pendingName = nil
            let t = p.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces)
            guard let f = t.first, f.isLetter, t.filter(\.isLetter).count >= 3 else { return }
            r.orphans.append((name: t, index: r.items.count))
        }

        func nameAndQty(_ raw: String) -> (String, Int?) {
            var b = boxes(raw)
            var q: Int?
            if let f = b.first, let n = Int(f), n > 0, n < 100 { q = n; b.removeFirst() }
            var name = b.joined(separator: " ")
            if qtyColumn, let m = name.range(of: #"^\d{1,2}\s+(?=\D)"#, options: .regularExpression) { q = Int(name[m].trimmingCharacters(in: .whitespaces)); name.removeSubrange(m) }
            if let m = name.range(of: #"\s*[×xX]\s?(\d{1,2})\s*$"#, options: .regularExpression) { q = Int(name[m].filter(\.isNumber)); name.removeSubrange(m) }
            return (name.trimmingCharacters(in: .whitespaces), q)
        }

        // merchant: first mostly-alphabetic line before any priced line
        for raw in lines {
            let t = latin(raw.replacingOccurrences(of: "\t", with: " "))
            if money(t) != nil { break }
            let letters = t.filter(\.isLetter).count
            if letters >= 3, letters * 10 >= t.count * 7, !noise.contains(where: { t.lowercased().contains($0) }) { r.merchant = t; break }
        }

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if noise.contains(where: { lower.contains($0) }) { dropPending(); continue }
            if lower.range(of: #"\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]* \d{1,2},? ?\d{4}"#, options: .regularExpression) != nil { continue }
            if lower.range(of: #"\d{1,2}/\d{1,2}/\d{2,4}"#, options: .regularExpression) != nil { continue }
            let bare = line.lowercased()   // keywords are checked with the CJK intact: 小計 is a subtotal too
            let isKeyword = isSubtotal(bare) || isTotal(bare) || isTax(bare) || isTip(bare)
            guard var (price, pr) = money(line) else {
                let latin = latin(line)
                let flat = latin.replacingOccurrences(of: "\t", with: "")
                if isKeyword, let pp = pendingPrice?.price {   // price column drifted a row: the pending price is this line's
                    pendingPrice = nil
                    if isSubtotal(bare) { r.subtotalCents = pp; continue }
                    if isTotal(bare) { r.totalCents = pp; break }
                    if isTax(bare) { r.taxCents = (r.taxCents ?? 0) + pp; continue }
                    r.tipCents = pp; continue
                }
                if let q = Int(flat), q > 0, q < 100 {
                    // A bilingual sub-label can leave its leading number behind ("10 秒牛舌" → "10"). When the
                    // English line above starts with the same number it is part of the name, not a quantity.
                    if pendingName?.hasPrefix("\(q) ") != true { pendingQty = q }
                    continue
                }
                if flat.count >= 3 {
                    if let pp = pendingPrice {
                        let (name, q) = nameAndQty(latin)
                        r.items.append(ParsedItem(name: name, quantity: q ?? pp.qty, priceCents: pp.price))
                        pendingPrice = nil; pendingName = nil; pendingQty = nil
                    } else { dropPending(); pendingName = latin }
                }
                continue
            }
            var text = line; text.removeSubrange(pr)
            let tl = text.lowercased()
            let cjkName = text.replacingOccurrences(of: "\t", with: " ").trimmingCharacters(in: .whitespaces)
            text = latin(text)
            let summary = isSubtotal(tl) || isTotal(tl) || isTax(tl) || isTip(tl)
            // Column-table receipts ("Unit Qty Price Vip Amount") leave rows of bare numbers once the name and the
            // amount have gone to other lines: "2 49.99 | 46.99". The leading number is the quantity; the rest are
            // other columns, not items.
            if text.range(of: #"^[\d.,\s]+$"#, options: .regularExpression) != nil, text.contains(where: { $0 == "." || $0 == "," }) {
                let q = Int(text.split(whereSeparator: \.isWhitespace).first ?? "").flatMap { $0 > 0 && $0 < 100 ? $0 : nil }
                if let pp = pendingPrice, let n = pp.name {
                    r.items.append(ParsedItem(name: n, quantity: q ?? pp.qty, priceCents: pp.price)); pendingPrice = nil
                } else if let p = pendingName {
                    r.items.append(ParsedItem(name: nameAndQty(p).0, quantity: q ?? 1, priceCents: price)); pendingName = nil
                } else if let q, !r.items.isEmpty {
                    r.items[r.items.count - 1].quantity = q
                }
                pendingQty = nil
                continue
            }
            if let pp = pendingPrice, !text.isEmpty {
                if summary || pp.name == nil {   // drifted column: swap — the pending price is ours, ours belongs to the next line
                    pendingPrice = (price, 1, nil); price = pp.price
                } else { flushPending() }   // the held CJK-named line was an item after all
            }
            if summary { dropPending(); pendingQty = nil }   // nothing above a summary line is waiting for a price
            if isSubtotal(tl) { r.subtotalCents = price; continue }
            if isTotal(tl) { r.totalCents = price; break }
            if isTax(tl) { r.taxCents = (r.taxCents ?? 0) + price; continue }
            if isTip(tl) { r.tipCents = price; continue }
            var qty = pendingQty ?? 1
            var (name, q) = nameAndQty(text)
            if name.isEmpty, let p = pendingName { let (pn, pq) = nameAndQty(p); name = pn; q = q ?? pq; pendingName = nil }
            if let q { qty = q }
            dropPending(); pendingQty = nil
            if name.isEmpty {
                // Past the subtotal, an amount with no label is tax or a fee whose label the OCR dropped.
                if r.subtotalCents != nil { r.taxCents = (r.taxCents ?? 0) + price; continue }
                pendingPrice = (price, qty, cjkName.contains(where: \.isLetter) ? cjkName : nil); continue
            }
            r.items.append(ParsedItem(name: name, quantity: qty, priceCents: price))
        }
        flushPending()
        if r.subtotalCents == nil, let total = r.totalCents { r.subtotalCents = total - (r.taxCents ?? 0) - (r.tipCents ?? 0) }
        return r
    }

    /// A receipt with extra price columns (unit price, member price) can leave the item sum above the printed
    /// subtotal. If exactly one cheapest way to drop items lands on the subtotal, take it — dropping a line whose
    /// "name" is just numbers is nearly free, a real name costs more, and an ambiguous answer is no answer.
    static func trimToSubtotal(_ r: inout ParsedReceipt) -> Bool {
        guard let subtotal = r.subtotalCents, r.itemSumCents > subtotal, (1...18).contains(r.items.count) else { return false }
        let surplus = r.itemSumCents - subtotal
        func weak(_ it: ParsedItem) -> Bool { it.name.filter(\.isLetter).count < 3 }
        let cost = r.items.map { weak($0) ? 1 : 3 }
        var best: (cost: Int, mask: Int, ways: Int)?
        for mask in 1..<(1 << r.items.count) {
            var sum = 0, c = 0
            for i in 0..<r.items.count where mask & (1 << i) != 0 { sum += r.items[i].priceCents; c += cost[i] }
            guard sum == surplus else { continue }
            if best == nil || c < best!.cost { best = (c, mask, 1) } else if c == best!.cost { best!.ways += 1 }
        }
        guard let b = best, b.ways == 1, b.cost <= 9 else { return false }
        r.items = r.items.enumerated().filter { b.mask & (1 << $0.offset) == 0 }.map(\.element)
        return true
    }
}
