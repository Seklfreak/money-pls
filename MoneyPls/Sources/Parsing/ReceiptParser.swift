import Foundation
import Vision
import CoreImage
import CoreGraphics
import UIKit

struct ParsedItem: Equatable { var name: String; var quantity: Int; var priceCents: Int }
struct ParsedReceipt {
    var merchant: String?
    /// Detected from the symbols on the receipt; the phone's currency when it prints none.
    var currencyCode: String = Currency.default
    var items: [ParsedItem] = []
    var subtotalCents: Int?
    var taxCents: Int?
    var tipCents: Int?
    var totalCents: Int?
    var lines: [String] = []
    /// Item-looking lines that never got a price, with the item index they would have had. Used to place a
    /// price recovered from another OCR pass.
    var orphans: [(name: String, index: Int)] = []
    var itemSumCents: Int { items.reduce(0) { $0 + $1.priceCents } }
    var reconciles: Bool { subtotalCents.map { $0 == itemSumCents } ?? false }
}

/// The on-device pipeline validated in money-pls-lab: document crop → Vision OCR (4 rotations) →
/// phrase/price line builder → deterministic parser. No network, no LLM on the primary path.
enum ReceiptParser {
    struct Word { let text: String; let conf: Float; let box: CGRect }

    static func parse(_ image: UIImage, alreadyCropped: Bool) async throws -> ParsedReceipt {
        guard let cg = image.normalizedCGImage() else { throw ParseError.badImage }
        ScanTrace.shared.reset()
        trace("parse start \(cg.width)x\(cg.height) cropped=\(alreadyCropped)")
        var source = cg
        var documentCropped = alreadyCropped
        if !alreadyCropped {
            do {
                if let c = try await cropToDocument(cg) { source = c; documentCropped = true; trace("document crop \(c.width)x\(c.height)") }
            } catch { traceError("document crop failed: \(error)") }
        }
        var best: (turns: Int, result: OCRResult)?
        var candidates: [OCRResult] = []   // every pass we ran; the parse decides among them below
        for n in 0..<4 {
            do {
                let r = try await ocr(rotated(source, quarterTurns: n))
                trace("rotation \(n) lines=\(r.lines.count) score=\(r.score)")
                candidates.append(r)
                if best == nil || r.score > best!.result.score { best = (n, r) }
            } catch { traceError("ocr rotation \(n) failed: \(error)") }
        }
        guard var chosen = best else { throw ParseError.badImage }
        if !documentCropped, chosen.result.words.count >= 5 {
            // No document quad (small receipt in a busy frame, or the simulator): crop the upright frame to the
            // text cluster and read it again at full resolution — small print needs the pixels.
            let upright = rotated(source, quarterTurns: chosen.turns)
            if let c = cropToWords(upright, chosen.result.words) {
                for n in 0..<4 {   // the crop is small, so re-checking orientation is cheap
                    guard let r = try? await ocr(rotated(c, quarterTurns: n)) else { continue }
                    let head = r.lines.prefix(12).joined(separator: " | ").replacingOccurrences(of: "\t", with: " ")
                    trace("text-cluster crop \(c.width)x\(c.height) rotation \(n) lines=\(r.lines.count) score=\(r.score) right=\(r.right) head=\(head)")
                    candidates.append(r)
                    if r.score > chosen.result.score { chosen = (n, r) }
                }
            }
        }
        // Vision drops or misplaces the odd price in any single pass. The OCR score can't see that, but the
        // parser can: a pass whose items sum to the printed subtotal beats the highest-scoring one that doesn't.
        var receipt = Heuristics.parse(lines: chosen.result.lines)
        var bestLines = chosen.result.lines
        if !receipt.reconciles {
            let alternatives = candidates.filter { $0.lines != chosen.result.lines }.sorted { $0.score > $1.score }
                .map { (result: $0, parsed: Heuristics.parse(lines: $0.lines)) }
            if let alt = alternatives.first(where: { $0.parsed.reconciles && $0.parsed.items.count >= max(1, receipt.items.count / 2) }) {
                trace("switching to a reconciling pass: score=\(alt.result.score) items=\(alt.parsed.items.count)")
                receipt = alt.parsed; bestLines = alt.result.lines
            } else if let subtotal = receipt.subtotalCents, subtotal > receipt.itemSumCents {
                // One line lost its price (typically the upright pass dropped a word the upside-down pass kept).
                // If exactly that amount shows up in another serious pass under a name we have no priced item
                // for, it is that item: put it where our own pass saw the name without a price, else at the end.
                let deficit = subtotal - receipt.itemSumCents
                let have = receipt.items.map { Heuristics.key($0.name) }
                search: for alt in alternatives where alt.parsed.items.count * 2 >= receipt.items.count {
                    for it in alt.parsed.items where it.priceCents == deficit {
                        let k = Heuristics.key(it.name)
                        guard k.filter(\.isLetter).count >= 3, !have.contains(where: { Heuristics.similar($0, k) }) else { continue }
                        var name = it.name, index = receipt.items.count
                        if let o = receipt.orphans.first(where: { Heuristics.similar(Heuristics.key($0.name), k) }) {
                            if o.name.count > name.count { name = o.name }
                            index = o.index
                        }
                        if name == name.uppercased() { name = name.capitalized }
                        receipt.items.insert(ParsedItem(name: name, quantity: 1, priceCents: deficit), at: min(index, receipt.items.count))
                        trace("recovered \(name) = \(deficit) from pass score=\(alt.result.score)")
                        break search
                    }
                }
            }
        }
        if !receipt.reconciles, Heuristics.trimToSubtotal(&receipt) { trace("dropped extra-column lines to meet the subtotal") }
        for (i, l) in bestLines.enumerated() { trace("L\(i): \(l.replacingOccurrences(of: "\t", with: " ⇥ "))") }
        receipt.lines = bestLines
        for it in receipt.items { trace("ITEM \(it.quantity) × \(it.name) = \(it.priceCents)") }
        return receipt
    }

    enum ParseError: Error { case badImage }

    // MARK: crop (what VisionKit's camera does for scanned pages)
    static func cropToDocument(_ img: CGImage) async throws -> CGImage? {
        let req = DetectDocumentSegmentationRequest()
        guard let obs = try await req.perform(on: img, orientation: .up) else { return nil }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        func pt(_ p: NormalizedPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }
        let f = CIFilter(name: "CIPerspectiveCorrection")!
        f.setValue(CIImage(cgImage: img), forKey: kCIInputImageKey)
        f.setValue(pt(obs.topLeft), forKey: "inputTopLeft")
        f.setValue(pt(obs.topRight), forKey: "inputTopRight")
        f.setValue(pt(obs.bottomLeft), forKey: "inputBottomLeft")
        f.setValue(pt(obs.bottomRight), forKey: "inputBottomRight")
        guard let out = f.outputImage else { return nil }
        return CIContext().createCGImage(out, from: out.extent)
    }

    static func cropToWords(_ img: CGImage, _ words: [Word]) -> CGImage? {
        let boxes = words.map(\.box)
        let minX = boxes.map(\.minX).min()!, maxX = boxes.map(\.maxX).max()!
        let minY = boxes.map(\.minY).min()!, maxY = boxes.map(\.maxY).max()!
        let w = CGFloat(img.width), h = CGFloat(img.height), pad: CGFloat = 0.02
        // Vision's normalized origin is bottom-left; CGImage cropping is top-left.
        let rect = CGRect(x: max(0, minX - pad) * w, y: max(0, 1 - maxY - pad) * h,
                          width: min(1, maxX - minX + 2 * pad) * w, height: min(1, maxY - minY + 2 * pad) * h)
        return img.cropping(to: rect.integral)
    }

    static func rotated(_ img: CGImage, quarterTurns n: Int) -> CGImage {
        if n == 0 { return img }
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let swap = n % 2 == 1
        let ow = Int(swap ? h : w), oh = Int(swap ? w : h)
        let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.translateBy(x: CGFloat(ow) / 2, y: CGFloat(oh) / 2)
        ctx.rotate(by: -CGFloat(n) * .pi / 2)
        ctx.draw(img, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        return ctx.makeImage() ?? img
    }

    // MARK: OCR
    struct OCRResult { let words: [Word]; let lines: [String]; let score: Float; let right: Float }
    static func ocr(_ img: CGImage) async throws -> OCRResult {
        var req = RecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = true
        req.automaticallyDetectsLanguage = true
        req.recognitionLanguages = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "zh-Hans")]
        let obs = try await req.perform(on: img, orientation: .up)
        let words: [Word] = obs.compactMap { o in
            guard let c = o.topCandidates(1).first else { return nil }
            let b = o.boundingBox
            return Word(text: c.string, conf: c.confidence, box: CGRect(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height))
        }
        let lines = groupLines(words)
        let priced = lines.filter { $0.range(of: #"\d+[.,]\d{2}\s*$"#, options: .regularExpression) != nil }.count
        let chars = words.reduce(Float(0)) { $0 + Float($1.text.count) * $1.conf }
        let priceX = words.filter { $0.text.range(of: Heuristics.priceRe, options: .regularExpression) != nil }.map { Float($0.box.midX) }
        let right = priceX.isEmpty ? 0 : priceX.reduce(0, +) / Float(priceX.count)
        // Upright receipts end with subtotal/total; an upside-down read starts with them.
        var orient: Float = 0
        if let i = lines.firstIndex(where: { $0.lowercased().range(of: #"sub\s?total|\btotal\b|amount due"#, options: .regularExpression) != nil }), lines.count > 1 {
            orient = Float(i) / Float(lines.count - 1) > 0.5 ? 300 : -300
        }
        return OCRResult(words: words, lines: lines, score: Float(priced) * 100 + chars / 100 + right * 100 + orient, right: right)
    }

    // MARK: line building — tight phrases, then each price attaches to one un-priced phrase on its row
    struct Phrase {
        var words: [Word]
        var minX: CGFloat { words.map(\.box.minX).min()! }
        var maxX: CGFloat { words.map(\.box.maxX).max()! }
        var midY: CGFloat { words.map(\.box.midY).reduce(0, +) / CGFloat(words.count) }
        var h: CGFloat { words.map(\.box.height).max()! }
        var rightY: CGFloat { words.max { $0.box.maxX < $1.box.maxX }!.box.midY }
        var leftY: CGFloat { words.min { $0.box.minX < $1.box.minX }!.box.midY }
        var text: String { words.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: "\t") }
        var isPrice: Bool { words.max { $0.box.minX < $1.box.minX }!.text.range(of: Heuristics.priceRe, options: .regularExpression) != nil }
    }

    static func groupLines(_ words: [Word]) -> [String] {
        let n = words.count
        if n == 0 { return [] }
        var parent = Array(0..<n)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }; return i }
        for i in 0..<n { for j in 0..<n where i != j {
            let a = words[i], b = words[j]; let h = min(a.box.height, b.box.height)
            let dx = b.box.minX - a.box.maxX, dy = abs(a.box.midY - b.box.midY)
            if dx > -0.3 * h, dx < 1.5 * h, dy < 0.5 * h { parent[find(i)] = find(j) }
        } }
        var g: [Int: [Word]] = [:]
        for i in 0..<n { g[find(i), default: []].append(words[i]) }
        let phrases = g.values.map { Phrase(words: $0) }.sorted { $0.midY > $1.midY }
        var used = Set<Int>()
        var lines: [Phrase] = []
        for (pi, p) in phrases.enumerated() where p.isPrice && !used.contains(pi) {
            var best: (Int, CGFloat)?
            for (qi, q) in phrases.enumerated() where qi != pi && !used.contains(qi) && !q.isPrice {
                guard q.maxX <= p.minX + 0.5 * p.h else { continue }
                let dy = abs(q.rightY - p.leftY)
                guard dy < 0.7 * max(p.h, q.h) else { continue }
                let cost = dy + max(p.minX - q.maxX, 0) * 0.01
                if best == nil || cost < best!.1 { best = (qi, cost) }
            }
            used.insert(pi)
            if let (qi, _) = best { used.insert(qi); lines.append(Phrase(words: phrases[qi].words + p.words)) } else { lines.append(p) }
        }
        for (qi, q) in phrases.enumerated() where !used.contains(qi) { lines.append(q) }
        return lines.sorted { $0.midY > $1.midY }.map(\.text)
    }
}

extension UIImage {
    /// CGImage with EXIF orientation baked in (Vision wants upright pixels).
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let r = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 1; return f }())
        return r.image { _ in draw(in: CGRect(origin: .zero, size: size)) }.cgImage
    }
}
