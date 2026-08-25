import SwiftUI
import SwiftData
import Translation
import NaturalLanguage

/// "Look right?" — editable parsed receipt on the tray.
struct ItemsView: View {
    @Bindable var split: Split
    @Binding var path: [Route]
    @Environment(\.modelContext) private var context
    @State private var showPeople = false
    @State private var translation: TranslationSession.Configuration?
    @State private var translations: [String: String] = [:]
    @State private var translationFailure: String?
    @FocusState private var focus: UUID?

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 14) {
                BrandHeader { path.removeAll() }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Look right?").font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink)
                    Text(split.items.isEmpty ? "Type in what you had — a line per dish is plenty."
                         : "We read \(split.items.count) thing\(split.items.count == 1 ? "" : "s") off the receipt. Tap anything to fix it.")
                        .font(Theme.text(14)).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                TrayScroll {
                    Tray {
                        HStack(spacing: 8) {
                            // Translate names (on device) — only offered while some name is in a script we could translate.
                            if split.items.contains(where: { $0.needsTranslation && $0.translatedName == nil }) {
                                Button { translate() } label: {
                                    Image(systemName: "character.book.closed").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.pink)
                                        .frame(width: 52, height: 24).background(Capsule().fill(Theme.bg))
                                }.accessibilityLabel("Translate names")
                            } else {
                                Color.clear.frame(width: 52, height: 1)
                            }
                            TextField("Where was this?", text: $split.title).font(Theme.disp(16, .bold)).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
                            // Currency is read off the receipt; this is the override when it guessed wrong. Amounts don't convert.
                            Menu {
                                ForEach(Currency.supported, id: \.self) { code in
                                    Button { split.currencyCode = code } label: {
                                        if code == split.currencyCode { Label(code, systemImage: "checkmark") } else { Text(code) }
                                    }
                                }
                            } label: {
                                Text(split.currencyCode).font(Theme.text(11, .extrabold)).foregroundStyle(Theme.muted).kerning(0.4)
                                    .padding(.horizontal, 8).padding(.vertical, 4).background(Capsule().fill(Theme.bg)).frame(width: 52)
                            }
                        }.padding(.bottom, 8)
                        HStack(spacing: 8) {
                            Text("ITEM").frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 10)
                            Text("QTY").frame(width: 44)
                            Text("PRICE").frame(width: 72, alignment: .trailing).padding(.trailing, 10)
                        }.font(Theme.text(11, .extrabold)).foregroundStyle(Theme.faint).kerning(0.4).padding(.bottom, 4)
                        ForEach(split.sortedItems) { item in
                            ItemRow(item: item, focus: $focus) { context.delete(item) }
                        }
                        Button { addItem() } label: {
                            HStack(spacing: 6) { Image(systemName: "plus").font(.system(size: 14, weight: .heavy)); Text("Add a line") }
                                .font(Theme.text(13, .extrabold)).foregroundStyle(Theme.pink)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                        DottedRule().padding(.vertical, 10)
                        HStack(spacing: 8) {
                            MoneyField(label: "TAX", cents: $split.taxCents)
                            MoneyField(label: tipLabel, cents: $split.tipCents)
                        }
                        HStack(spacing: 6) {
                            ForEach([15, 18, 20, 25], id: \.self) { pct in
                                let on = tipPercent == pct
                                Button { split.tipCents = (split.subtotalCents * pct + 50) / 100 } label: {
                                    Text("\(pct)%").font(Theme.text(12, .extrabold)).foregroundStyle(on ? Theme.bg : Theme.body)
                                        .padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(on ? Theme.ink : Theme.bg))
                                }.buttonStyle(PressStyle())
                            }
                            Spacer()
                        }.padding(.top, 6)
                        HStack { Text("Total"); Spacer(); Text(split.totalCents.money(split.currencyCode)).monospacedDigit() }
                            .font(Theme.disp(17, .bold)).foregroundStyle(Theme.ink).padding(.top, 10)
                        if let printed = split.printedSubtotalCents, printed != split.subtotalCents {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                Text("Items add up to \(split.subtotalCents.money(split.currencyCode)), but the receipt says \(printed.money(split.currencyCode)). Worth a look.")
                            }
                            .font(Theme.text(12, .extrabold)).foregroundStyle(Theme.amber)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amberBg)).padding(.top, 8)
                        }
                    }
                    if let data = split.receiptImage, let image = UIImage(data: data) {
                        HStack(spacing: 4) {
                            Text("Read something wrong?")
                            ReportScanButton(image: image, trace: split.parseTrace ?? "", context: reportContext)
                        }
                        .font(Theme.text(13, .extrabold)).foregroundStyle(Theme.faint)
                        .padding(.top, 14).padding(.bottom, 24)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .padding(.horizontal, 16)
            .safeAreaInset(edge: .bottom) {
                Footer { PrimaryButton(title: "Yep, who's splitting?") { showPeople = true } }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.currency, split.currencyCode)
        .translateNames($translation, names: untranslated, results: $translations, failure: $translationFailure)
        .alert("Translation unavailable", isPresented: Binding(get: { translationFailure != nil }, set: { if !$0 { translationFailure = nil } })) {
            Button("OK") {}
        } message: { Text(translationFailure ?? "") }
        .onChange(of: translations) { _, new in
            for item in split.items { if let t = new[item.id.uuidString] { item.translatedName = t } }
        }
        .sheet(isPresented: $showPeople) {
            PeopleSheet(split: split) { showPeople = false; path.append(.assign(split.id)) }
                .presentationDetents([.large]).presentationDragIndicator(.hidden)
        }
    }

    private var tipPercent: Int? {
        guard split.subtotalCents > 0, split.tipCents > 0 else { return nil }
        return Int((Double(split.tipCents) / Double(split.subtotalCents) * 100).rounded())
    }
    private var reportContext: String {
        let c = split.currencyCode
        return "Items after parse: \(split.items.count), sum \(split.subtotalCents.money(c)), printed subtotal \(split.printedSubtotalCents?.money(c) ?? "none"), currency \(c)"
    }
    private var tipLabel: String { tipPercent.map { "TIP · \($0)%" } ?? "TIP" }
    private var untranslated: [String: String] {
        Dictionary(uniqueKeysWithValues: split.items.filter { $0.needsTranslation && $0.translatedName == nil }.map { ($0.id.uuidString, $0.name) })
    }
    private func translate() {
        // One session per source language: detect the script ourselves and translate the most common one first;
        // the button stays until every name is done, so a second tap covers a mixed receipt.
        let recognizer = NLLanguageRecognizer()
        var votes: [String: Int] = [:]
        for name in untranslated.values {
            recognizer.reset(); recognizer.processString(name)
            if let l = recognizer.dominantLanguage?.rawValue { votes[l, default: 0] += 1 }
        }
        guard let source = votes.max(by: { $0.value < $1.value })?.key else { return }
        translation = TranslationSession.Configuration(source: Locale.Language(identifier: source), target: Locale.current.language)
    }
    private func addItem() {
        let item = LineItem(name: "", quantity: 1, priceCents: 0, order: (split.items.map(\.order).max() ?? -1) + 1)
        split.items.append(item)
        focus = item.id
    }
}

struct ItemRow: View {
    @Bindable var item: LineItem
    var focus: FocusState<UUID?>.Binding
    let delete: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Item", text: $item.name, axis: .vertical).lineLimit(1...3).focused(focus, equals: item.id)
                    .font(Theme.text(14)).foregroundStyle(Theme.ink)
                if let t = item.subtitle { Text(t).font(Theme.text(11)).foregroundStyle(Theme.muted).lineLimit(2) }
            }
            .padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 40).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
            .onChange(of: item.name) { old, new in if item.translatedName != nil, old != new { item.translatedName = nil } }
            TextField("1", value: $item.quantity, format: .number).keyboardType(.numberPad).multilineTextAlignment(.center)
                .font(Theme.text(14)).foregroundStyle(Theme.ink).frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
            CentsField(cents: $item.priceCents).frame(width: 72, height: 40)
            // `.swipeActions` only works inside a List, so the delete lives here: visible while the line is being edited.
            if focus.wrappedValue == item.id {
                Button(action: delete) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.faint)
                        .frame(width: 28, height: 40).background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
                }
                .accessibilityLabel("Delete line")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 6)
        .animation(.snappy, value: focus.wrappedValue == item.id)
        .contextMenu { Button(role: .destructive, action: delete) { Label("Delete line", systemImage: "trash") } }
    }
}

struct MoneyField: View {
    let label: String
    @Binding var cents: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.text(11, .extrabold)).foregroundStyle(Theme.faint)
            CentsField(cents: $cents, alignment: .leading).frame(height: 40).frame(maxWidth: .infinity)
        }
    }
}

/// Decimal text field bound to an integer number of cents.
struct CentsField: View {
    @Environment(\.currency) private var currency
    @Binding var cents: Int
    var alignment: TextAlignment = .trailing
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TextField("0.00", text: $text).keyboardType(.decimalPad).multilineTextAlignment(alignment).focused($focused)
            .font(Theme.text(14)).foregroundStyle(Theme.ink).monospacedDigit()
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
            .onAppear { text = cents.moneyPlain(currency) }
            .onChange(of: cents) { _, v in if !focused { text = v.moneyPlain(currency) } }
            .onChange(of: currency) { _, c in if !focused { text = cents.moneyPlain(c) } }
            .onChange(of: focused) { _, f in
                if f { if cents == 0 { text = "" } } else { cents = Currency.minorUnits(from: text, code: currency); text = cents.moneyPlain(currency) }
            }
    }
}
