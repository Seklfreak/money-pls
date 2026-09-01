import SwiftUI
import SwiftData

/// One friend's page: where you stand with them, and everything you two ever split.
///
/// Every number on here is derived — `Money.balances` and `Money.ledger` over the live `@Query`
/// results — so nothing can drift out of sync with the splits themselves.
struct FriendDetailView: View {
    let friend: Friend
    @Binding var path: [Route]
    @Environment(\.modelContext) private var context
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @Query private var payments: [Payment]
    @State private var settling = false
    @State private var sharing = false

    var body: some View {
        ZStack {
            PageBackground(stop: 0.45)
            // `me` is nil until the backfill or the You sheet has picked someone — a fresh install
            // that lands here shouldn't crash, it should say what's missing.
            if let me = Friend.me(in: context) { page(me: me) } else { unknownMe }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Analytics.screen(.friend) }
        // A sheet closing fires no onAppear underneath it, so both of these have to say where you landed.
        .sheet(isPresented: $settling, onDismiss: { Analytics.screen(.friend) }, content: {
            SettleUpSheet(friend: friend).presentationDetents([.large])
        })
        .sheet(isPresented: $sharing, onDismiss: { Analytics.screen(.friend) }, content: {
            BalanceShareSheet(friend: friend).presentationDetents([.large])
        })
    }

    private func page(me: Friend) -> some View {
        let open = Money.balances(splits: splits, payments: payments, me: me)
            .first { $0.friend.id == friend.id }?.byCurrency.filter { $0.value != 0 } ?? [:]
        let entries = Money.ledger(for: friend, splits: splits, payments: payments, me: me)
        let bills = entries.filter { entry in
            if case .split = entry { return true }
            return false
        }
        return ScrollView {
            VStack(spacing: 16) {
                BrandHeader { if !path.isEmpty { path.removeLast() } }
                header(bills: bills)
                balanceCard(open)
                HStack {
                    Text("Between you two").font(Theme.disp(18)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(count(bills.count, "bill")) · \(count(entries.count - bills.count, "payment"))")
                        .font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted)
                }.padding(.horizontal, 4)
                ledgerCard(entries, me: me)
            }
            .padding(.horizontal, 16).padding(.bottom, 32)
        }
    }

    private func header(bills: [LedgerEntry]) -> some View {
        HStack(spacing: 14) {
            Avatar(initial: friend.initial, color: Theme.avatarColor(friend.colorIndex), size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.6)
                Text(bills.isEmpty
                     ? "nothing split together yet"
                     : "in \(count(bills.count, "split")) since \((bills.map(\.date).min() ?? friend.createdAt).formatted(.dateTime.month(.wide).year()))")
                    .font(Theme.text(14)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
    }

    /// Where you stand. Two directions can be open at once — a euro debt of mine and a dollar debt
    /// of theirs never cancel — so each gets its own line rather than one misleading number.
    private func balanceCard(_ open: [String: Int]) -> some View {
        let theirs = open.filter { $0.value > 0 }
        let mine = open.filter { $0.value < 0 }.mapValues { -$0 }
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                if open.isEmpty {
                    Text("All square").font(Theme.disp(32, .bold)).foregroundStyle(Theme.muted)
                    Text("nothing open between you").font(Theme.text(13)).foregroundStyle(Theme.faint)
                } else {
                    if !theirs.isEmpty { amountLine("\(friend.name) owes you", theirs, Theme.green) }
                    if !mine.isEmpty { amountLine("You owe \(friend.name)", mine, Theme.amber) }
                    if open.count > 1 {
                        Text("kept apart — nothing gets converted").font(Theme.text(12)).foregroundStyle(Theme.faint)
                    }
                }
            }
            HStack(spacing: 10) {
                PrimaryButton(title: "Settle up", icon: "checkmark", height: 48, fontSize: 16) { settling = true }
                SecondaryButton(title: "Money pls", icon: "square.and.arrow.up") { sharing = true }
                    .disabled(theirs.isEmpty).opacity(theirs.isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 16)
        .card()
    }

    private func amountLine(_ label: String, _ byCurrency: [String: Int], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.text(14)).foregroundStyle(Theme.muted)
            Text(Money.formatByCurrency(byCurrency)).font(Theme.disp(32, .bold)).foregroundStyle(color).monospacedDigit()
        }
    }

    @ViewBuilder
    private func ledgerCard(_ entries: [LedgerEntry], me: Friend) -> some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text("Nothing here yet. Split a receipt with \(friend.name) and it shows up.")
                    .font(Theme.text(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
            }
            ForEach(entries.indices, id: \.self) { index in
                if index > 0 { DottedRule().padding(.vertical, 10) }
                switch entries[index] {
                case .split(let split, let cents, let settled):
                    Button { path.append(.bill(split.id)) } label: {
                        LedgerSplitRow(split: split, cents: cents, settled: settled, me: me)
                    }.buttonStyle(PressStyle())
                case .payment(let payment):
                    LedgerPaymentRow(payment: payment, friend: friend, me: me)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 6)
        .card()
    }

    private var unknownMe: some View {
        VStack(spacing: 16) {
            BrandHeader { if !path.isEmpty { path.removeLast() } }
            Spacer()
            Text("Who are you?").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
            Text("Balances are always \"them versus you\", so Money pls needs to know which name is yours before it can add up \(friend.name)'s.")
                .font(Theme.text(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.bottom, 32)
    }

    private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

/// A split you were both on. The right-hand label is what it did to the balance, not what it cost.
private struct LedgerSplitRow: View {
    let split: Split
    let cents: Int
    let settled: Bool
    let me: Friend
    var body: some View {
        let scanned = split.splitKind == .scanned
        let payerIsMe = split.payer?.friend?.id == me.id
        HStack(spacing: 12) {
            LedgerIcon(system: scanned ? "doc.text" : "plus",
                       fg: scanned ? Theme.amber : Theme.muted, bg: scanned ? Theme.amberBg : Theme.sand)
            VStack(alignment: .leading, spacing: 2) {
                Text(split.displayTitle).font(Theme.disp(16)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(ledgerDate(split.createdAt)) · \(payerIsMe ? "you" : split.payer?.name ?? "they") paid \(split.totalCents.money(split.currencyCode))")
                    .font(Theme.text(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                let color = settled ? Theme.muted : (cents > 0 ? Theme.green : Theme.amber)
                Text(settled ? "settled" : (cents > 0 ? "you lent" : "you owe"))
                    .font(Theme.text(11, .extrabold)).foregroundStyle(color)
                Text(abs(cents).money(split.currencyCode)).font(Theme.disp(16)).foregroundStyle(color).monospacedDigit()
            }
        }
        .padding(.vertical, 12).contentShape(Rectangle())
    }
}

/// A settle-up. Split-linked payments never reach here — see `Money.ledger`.
private struct LedgerPaymentRow: View {
    let payment: Payment
    let friend: Friend
    let me: Friend
    var body: some View {
        let incoming = payment.toFriend?.id == me.id
        HStack(spacing: 12) {
            LedgerIcon(system: "arrow.right", fg: incoming ? Theme.green : Theme.muted,
                       bg: incoming ? Theme.green.opacity(0.12) : Theme.sand)
            VStack(alignment: .leading, spacing: 2) {
                Text(incoming ? "\(friend.name) paid you" : "You paid \(friend.name)").font(Theme.disp(16)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("\(ledgerDate(payment.date)) · payment").font(Theme.text(12)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 8)
            Text(payment.cents.money(payment.currencyCode)).font(Theme.disp(16)).foregroundStyle(Theme.muted).monospacedDigit()
        }
        .padding(.vertical, 12)
    }
}

private struct LedgerIcon: View {
    let system: String
    let fg: Color
    let bg: Color
    var body: some View {
        Image(systemName: system).font(.system(size: 17, weight: .bold)).foregroundStyle(fg)
            .frame(width: 40, height: 40).background(Circle().fill(bg))
    }
}

/// "today" beats "Aug 31" for the row you just made; everything older gets a date.
private func ledgerDate(_ date: Date) -> String {
    Calendar.current.isDateInToday(date) ? "today" : date.formatted(.dateTime.month(.abbreviated).day())
}

#if DEBUG
/// Sample store shared by the three friend previews: me, Carmen, two splits in two currencies,
/// and a settle-up — enough for every row these screens can draw.
@MainActor
enum FriendPreviewData {
    static let sample: (container: ModelContainer, friend: Friend)? = {
        guard let container = try? ModelStore.container(inMemory: true) else { return nil }
        let context = container.mainContext
        let me = Friend(name: "Seb", colorIndex: 5)
        me.isMe = true
        let carmen = Friend(name: "Carmen", colorIndex: 0, createdAt: Date(timeIntervalSinceNow: -86_400 * 150))
        context.insert(me)
        context.insert(carmen)

        /// One evenly split item, paid by me — the shape every ledger row is drawn from.
        func make(_ title: String, cents: Int, currency: String, daysAgo: Double, kind: SplitKind) {
            let split = Split(title: title)
            split.currencyCode = currency
            split.splitKind = kind
            split.createdAt = Date(timeIntervalSinceNow: -86_400 * daysAgo)
            context.insert(split)
            for (i, friend) in [me, carmen].enumerated() {
                let person = Person(name: friend.name, colorIndex: friend.colorIndex, order: i)
                person.friend = friend
                split.people.append(person)
            }
            split.payerID = split.sortedPeople.first?.id
            split.items.append(LineItem(name: "Dinner", quantity: 1, priceCents: cents, order: 0))
        }
        make("Hot pot at Haidilao", cents: 8640, currency: "USD", daysAgo: 2, kind: .scanned)
        make("Groceries", cents: 5400, currency: "USD", daysAgo: 0, kind: .typed)
        make("Currywurst in Berlin", cents: 3600, currency: "EUR", daysAgo: 16, kind: .scanned)
        context.insert(Payment(from: carmen, to: me, cents: 2000, currencyCode: "USD",
                               date: Date(timeIntervalSinceNow: -86_400 * 11), note: "cash at brunch"))
        return (container, carmen)
    }()
}

#Preview {
    if let sample = FriendPreviewData.sample {
        NavigationStack { FriendDetailView(friend: sample.friend, path: .constant([])) }
            .modelContainer(sample.container)
    }
}
#endif
