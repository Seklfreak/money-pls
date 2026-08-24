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
                    HStack {
                        RoundIconButton(system: "chevron.left") { path.removeLast() }
                        Spacer()
                        Button { shareAll = true } label: {
                            HStack(spacing: 6) { Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .bold)); Text("Share all").font(Theme.disp(15)) }
                                .foregroundStyle(.white).padding(.horizontal, 18).frame(height: 44)
                                .raised(Capsule(), fill: Theme.pink, shadow: Theme.pinkShadow, depth: 4)
                        }.buttonStyle(PressStyle())
                    }
                    HStack(spacing: 14) {
                        Logo(size: 72)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Money pls").font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink)
                            Text("\(split.title) · \(payer?.name ?? "You") paid \(split.totalCents.money)").font(Theme.text(14)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
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
                                    Text("paid · keeps \(mine.totalCents.money) worth").font(Theme.text(12)).foregroundStyle(Theme.muted)
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
        .sheet(item: $sharing) { bill in ShareSheetView(split: split, bills: [bill]).presentationDetents([.large]) }
        .sheet(isPresented: $shareAll) { ShareSheetView(split: split, bills: bills.filter { $0.person.id != payer?.id }).presentationDetents([.large]) }
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
                    Text(bill.person.paid ? "paid ✓" : "money pls").font(Theme.text(12)).foregroundStyle(bill.person.paid ? Theme.green : Theme.muted)
                }
                Spacer()
                Text(bill.totalCents.money).font(Theme.disp(22, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    .strikethrough(bill.person.paid, color: Theme.green)
                Button { bill.person.paid.toggle() } label: {
                    Image(systemName: bill.person.paid ? "checkmark.circle.fill" : "circle").font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(bill.person.paid ? Theme.green : Theme.sand)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14).background(color.opacity(0.13))
            VStack(spacing: 4) {
                ForEach(bill.lines) { l in
                    HStack { Text(l.label); Spacer(); Text(l.cents.money).monospacedDigit() }
                }
            }
            .font(Theme.text(13)).foregroundStyle(Theme.body)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 14)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .card()
    }
}
