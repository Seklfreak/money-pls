import SwiftUI
import SwiftData
import UIKit

/// "Money pls, Carmen" for a running balance rather than one bill — the same card as
/// `ShareSheetView`, but the lines are every open split between you two plus what came back.
///
/// One card per currency, because a euro debt and a dollar debt are two asks, not one sum.
struct BalanceShareSheet: View {
    let friend: Friend
    @Environment(\.modelContext) private var context
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @Query private var payments: [Payment]
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Theme.sand).frame(width: 40, height: 5).padding(.top, 12)
            let cards = Friend.me(in: context).map { openCards(me: $0) } ?? []
            VStack(alignment: .leading, spacing: 2) {
                Text("Money pls, \(friend.name)").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
                Text(cards.count > 1 ? "\(cards.count) cards, one per currency." : "A little card they can read without opening anything.")
                    .font(Theme.text(13)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            // The card starts where the subtitle ends. A pair of spacers would centre it, and one
            // open bill makes a short card — which centres into a band of nothing above and below.
            if cards.isEmpty {
                Text("Nothing to ask \(friend.name) for right now.").font(Theme.text(14)).foregroundStyle(Theme.muted)
            } else if cards.count == 1 {
                BalanceCard(card: cards[0]).padding(.bottom, 20)   // room for the card's own raised edge
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) { ForEach(cards) { BalanceCard(card: $0).frame(width: 320) } }
                        .scrollTargetLayout().padding(.horizontal, 2).padding(.bottom, 20)
                }.scrollTargetBehavior(.viewAligned).scrollClipDisabled()
            }
            Spacer(minLength: 12)
            VStack(spacing: 10) {
                PrimaryButton(title: cards.count > 1 ? "Send the cards" : "Send the card", icon: "square.and.arrow.up") { share(cards) }
                SecondaryButton(title: copied ? "Copied!" : "Copy as text") {
                    Analytics.track("balance_copied", ["cards": String(cards.count)])
                    UIPasteboard.general.string = cards.map(\.text).joined(separator: "\n\n")
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
            }
            .disabled(cards.isEmpty).opacity(cards.isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { Analytics.screen(.share) }
    }

    /// One card per currency the friend is behind in. Currencies where *I* owe are left out —
    /// there is nothing to ask for there, and the balance card only ever asks.
    private func openCards(me: Friend) -> [BalanceCardData] {
        let open = Money.balances(splits: splits, payments: payments, me: me)
            .first { $0.friend.id == friend.id }?.byCurrency ?? [:]
        let entries = Money.ledger(for: friend, splits: splits, payments: payments, me: me)
        let mine = Currency.default
        return open.filter { $0.value > 0 }
            .sorted { ($0.key == mine) != ($1.key == mine) ? $0.key == mine : $0.key < $1.key }
            .map { code, total in
                var lines: [ShareLine] = []
                var bills = 0
                // Same rules the balance itself follows, so the lines add up to the total exactly:
                // a settled split is already paid for, and split-linked payments never reach the ledger.
                for entry in entries {
                    switch entry {
                    case .split(let split, let cents, let settled):
                        guard split.currencyCode == code, !settled else { continue }
                        bills += 1
                        lines.append(ShareLine(label: split.displayTitle, cents: cents))
                    case .payment(let payment):
                        guard payment.currencyCode == code else { continue }
                        let incoming = payment.toFriend?.id == me.id
                        lines.append(ShareLine(label: incoming ? "paid \(payment.date.formatted(.dateTime.month(.abbreviated).day()))"
                                                              : "you sent \(payment.date.formatted(.dateTime.month(.abbreviated).day()))",
                                               cents: incoming ? -payment.cents : payment.cents))
                    }
                }
                return BalanceCardData(currency: code, total: total, bills: bills, lines: lines,
                                       friendName: friend.name, myName: me.name)
            }
    }

    private func share(_ cards: [BalanceCardData]) {
        Analytics.track("balance_shared", ["cards": String(cards.count)])
        let images: [UIImage] = cards.compactMap { card in
            let renderer = ImageRenderer(content: BalanceCard(card: card).frame(width: 320))
            renderer.scale = 3
            return renderer.uiImage
        }
        let items: [Any] = images + [cards.map(\.text).joined(separator: "\n\n")]
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.rootViewController?
            .topMost.present(controller, animated: true)
    }
}

/// Everything one card shows, resolved off the models so `ImageRenderer` never touches SwiftData.
struct BalanceCardData: Identifiable {
    let currency: String
    let total: Int
    let bills: Int
    let lines: [ShareLine]
    let friendName: String
    let myName: String
    var id: String { currency }

    var text: String {
        let body = lines.map { "\($0.label) \($0.cents.money(currency))" }.joined(separator: " · ")
        return "\(friendName) — \(total.money(currency)) pls (to \(myName))\n\(body)"
    }
}

struct BalanceCard: View {
    let card: BalanceCardData
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MONEY PLS").font(Theme.disp(13)).foregroundStyle(Theme.trayDark).kerning(0.5)
                    Text("\(card.friendName),\n\(card.total.money(card.currency)) pls").font(Theme.disp(26, .bold)).foregroundStyle(Theme.ink).lineSpacing(2)
                    Text("\(card.bills) bill\(card.bills == 1 ? "" : "s") · to \(card.myName)").font(Theme.text(12)).foregroundStyle(Theme.muted)
                }.padding(.bottom, 16)
                Spacer()
                Logo(size: 88)
            }
            .padding(EdgeInsets(top: 18, leading: 20, bottom: 0, trailing: 20))
            .background(LinearGradient(colors: [Color(hex: 0xffe0cf), Color(hex: 0xffd0d8)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 4) {
                ForEach(card.lines) { line in
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label)
                        Spacer()
                        Text(line.cents.money(card.currency)).monospacedDigit()
                    }
                }
                DottedRule().padding(.vertical, 4)
                HStack(alignment: .firstTextBaseline) {
                    Text("Still open").font(Theme.text(13, .extrabold))
                    Spacer()
                    Text(card.total.money(card.currency)).font(Theme.text(13, .extrabold)).monospacedDigit()
                }.foregroundStyle(Theme.ink)
            }
            .font(Theme.text(13)).foregroundStyle(Theme.body)
            .padding(EdgeInsets(top: 14, leading: 20, bottom: 18, trailing: 20))
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.line).offset(y: 6))
        .shadow(color: Color(hex: 0x785028).opacity(0.15), radius: 15, y: 16)
    }
}

#if DEBUG
#Preview {
    if let sample = FriendPreviewData.sample {
        Color.clear.sheet(isPresented: .constant(true)) {
            BalanceShareSheet(friend: sample.friend).presentationDetents([.large])
        }
        .modelContainer(sample.container)
    }
}
#endif
