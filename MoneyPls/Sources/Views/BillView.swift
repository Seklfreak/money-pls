import SwiftUI
import SwiftData

/// "The bill" — one card per person who owes the payer. Tap a card to share it; tap the check to mark paid.
struct BillView: View {
    @Bindable var split: Split
    @Binding var path: [Route]
    @State private var sharing: PersonBill?
    @State private var shareAll = false

    var body: some View {
        let bills = Money.bills(for: split)
        let payer = split.payer
        ZStack {
            PageBackground(stop: 0.3)
            ScrollView {
                VStack(spacing: 16) {
                    // The bill is the finish line: back goes home, not back through Assign and Items.
                    BrandHeader { path.removeAll() }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Who owes what").font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink)
                            Text("\(split.displayTitle) · \(payer?.name ?? "You") paid \(split.totalCents.money(split.currencyCode))").font(Theme.text(14)).foregroundStyle(Theme.muted)
                            Button { path.append(.assign(split.id)) } label: {
                                HStack(spacing: 4) { Image(systemName: "arrow.uturn.backward").font(.system(size: 11, weight: .bold)); Text("Change who had what") }
                                    .font(Theme.text(13, .extrabold)).foregroundStyle(Theme.pink)
                            }.padding(.top, 4)
                        }
                        Spacer()
                        if bills.filter({ $0.person.id != payer?.id && !$0.person.settled }).count > 1 {
                            Button { shareAll = true } label: {
                                HStack(spacing: 6) { Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .bold)); Text("Share all").font(Theme.disp(14)) }
                                    .foregroundStyle(.white).padding(.horizontal, 14).frame(height: 38)
                                    .raised(Capsule(), fill: Theme.pink, shadow: Theme.pinkShadow, depth: 3)
                            }.buttonStyle(PressStyle())
                        }
                    }
                    VStack(spacing: 12) {
                        ForEach(bills.filter { $0.person.id != payer?.id }) { bill in
                            Button { sharing = bill } label: { BillCard(bill: bill) }.buttonStyle(PressStyle())
                        }
                        if let payer, let mine = bills.first(where: { $0.person.id == payer.id }) {
                            HStack(spacing: 12) {
                                Avatar(payer, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(payer.name).font(Theme.disp(18)).foregroundStyle(Theme.ink)
                                    Text("your share · \(mine.totalCents.money(split.currencyCode))").font(Theme.text(12)).foregroundStyle(Theme.muted)
                                }
                                Spacer()
                                Text("—").font(Theme.disp(18)).foregroundStyle(Theme.muted)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(style: StrokeStyle(lineWidth: 2, dash: [6, 5])).foregroundStyle(Theme.sand))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 32)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Analytics.screen(.bill) }
        // A sheet closing fires no onAppear beneath it, so without these the bill would stay
        // "on" /share and marking someone paid would be filed there.
        .sheet(item: $sharing, onDismiss: { Analytics.screen(.bill) }, content: { bill in
            ShareSheetView(split: split, bills: [bill]).presentationDetents([.large])
        })
        .sheet(isPresented: $shareAll, onDismiss: { Analytics.screen(.bill) }, content: {
            ShareSheetView(split: split, bills: bills.filter { $0.person.id != payer?.id }).presentationDetents([.large])
        })
    }
}

struct BillCard: View {
    let bill: PersonBill
    var body: some View {
        let color = Theme.avatarColor(bill.person.colorIndex)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Avatar(bill.person, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(bill.person.name).font(Theme.disp(18)).foregroundStyle(Theme.ink)
                    Text(bill.person.settled ? "settled ✓" : "money pls").font(Theme.text(12)).foregroundStyle(bill.person.settled ? Theme.green : Theme.muted)
                }
                Spacer()
                Text(bill.totalCents.money(bill.currency)).font(Theme.disp(22, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    .strikethrough(bill.person.settled, color: Theme.green)
                Button {
                    bill.person.settled.toggle()
                    if bill.person.settled { Analytics.track("person_settled") }
                } label: {
                    Image(systemName: bill.person.settled ? "checkmark.circle.fill" : "circle").font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(bill.person.settled ? Theme.green : Theme.sand)
                }
                .accessibilityLabel(bill.person.settled ? "Mark as not settled" : "Mark as settled")
            }
            .padding(.horizontal, 16).padding(.vertical, 14).background(color.opacity(0.13))
            VStack(spacing: 4) {
                ForEach(bill.lines) { l in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(l.label)
                            if let t = l.sublabel { Text(t).font(Theme.text(11)).foregroundStyle(Theme.muted) }
                        }
                        Spacer(); Text(l.cents.money(bill.currency)).monospacedDigit()
                    }
                }
            }
            .font(Theme.text(13)).foregroundStyle(Theme.body)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .card()
    }
}
