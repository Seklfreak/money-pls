import SwiftUI
import SwiftData

/// The Friends tab: where you stand with everyone, and the ways to start a split.
struct FriendsView: View {
    @Binding var path: [Route]
    let onScan: () -> Void
    let onPickPhotos: () -> Void
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @Query private var payments: [Payment]
    // A query rather than a fetch: on a fresh install nobody is "me" yet, and the header has to
    // redraw the moment the You sheet decides.
    @Query(filter: #Predicate<Friend> { $0.isMe }) private var meRows: [Friend]
    @State private var showYou = false
    @State private var showAdd = false

    private var me: Friend? { meRows.first }
    private var balances: [FriendBalance] {
        guard let me else { return [] }
        return Money.balances(splits: splits, payments: payments, me: me)
    }

    var body: some View {
        let balances = balances
        ZStack {
            PageBackground(stop: 0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if balances.isEmpty {
                        Text("Scan the receipt, tap who had what,\nsend everyone their share.")
                            .font(Theme.text(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity).padding(.top, 16)
                    } else {
                        totals(for: balances)
                    }
                    buttons
                    if !balances.isEmpty { friends(balances) }
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Analytics.screen(.friends) }
        // Nothing under a sheet fires onAppear, so say where we landed or the next event files itself
        // against whatever screen was reported last.
        .sheet(isPresented: $showYou, onDismiss: { Analytics.screen(.friends) }, content: { YouSheet() })
        .sheet(isPresented: $showAdd, onDismiss: { if path.isEmpty { Analytics.screen(.friends) } }, content: {
            AddExpenseSheet { split in
                showAdd = false
                if let split { path.append(.bill(split.id)) }
            }
        })
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) { Logo(size: 28); Text("Money pls").font(Theme.disp(18)).foregroundStyle(Theme.ink) }
            Spacer()
            Button { showYou = true } label: {
                ZStack {
                    Circle().fill(.white)
                    if let me {
                        Avatar(initial: me.initial, color: Theme.avatarColor(me.colorIndex), size: 36)
                    } else {
                        Image(systemName: "person.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(width: 44, height: 44)
                .raised(Circle(), fill: .white, shadow: Theme.line, depth: 3)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(me.map { "You, \($0.name)" } ?? "Set up who you are")
        }
        .frame(height: 44)
    }

    private func totals(for balances: [FriendBalance]) -> some View {
        let (owedToMe, iOwe) = Money.overall(balances)
        var net = owedToMe
        for (code, cents) in iOwe { net[code, default: 0] -= cents }
        net = net.filter { $0.value != 0 }
        // Currencies never convert, so "which way round" can only be a judgement call: the sum decides
        // the headline, and a lone currency pointing the other way still shows on its friend's row.
        let owing = net.values.reduce(0, +) < 0
        let headline = Money.formatByCurrency(net.filter { owing ? $0.value < 0 : $0.value > 0 }.mapValues { abs($0) })

        return VStack(alignment: .leading, spacing: 6) {
            Text(net.isEmpty ? "Overall" : (owing ? "Overall, you owe" : "Overall, you are owed"))
                .font(Theme.text(14)).foregroundStyle(Theme.muted)
            if net.isEmpty {
                Text("All square").font(Theme.disp(40, .bold)).foregroundStyle(Theme.ink)
            } else {
                stacked(headline).monospacedDigit()
            }
            if !owedToMe.isEmpty || !iOwe.isEmpty {
                HStack(spacing: 8) {
                    if !owedToMe.isEmpty {
                        Pill(bg: Theme.green.opacity(0.12), fg: Theme.green, shadow: false) { Text("owed to you · \(Money.formatByCurrency(owedToMe))") }
                    }
                    if !iOwe.isEmpty {
                        Pill(bg: Theme.amber.opacity(0.12), fg: Theme.amber, shadow: false) { Text("you owe · \(Money.formatByCurrency(iOwe))") }
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Scan a receipt", icon: "camera.fill", height: 68, fontSize: 20, action: onScan)
            Button(action: onPickPhotos) { PickPhotosLabel() }.buttonStyle(PressStyle())
            SecondaryButton(title: "Add an expense", icon: "plus") { showAdd = true }
        }
    }

    private func friends(_ balances: [FriendBalance]) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text("Friends").font(Theme.disp(18)).foregroundStyle(Theme.ink)
                Spacer()
                Text("from your splits").font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted)
            }.padding(.horizontal, 4)
            ForEach(balances) { balance in
                Button { path.append(.friend(balance.friend.id)) } label: { row(balance) }.buttonStyle(PressStyle())
            }
        }
    }

    private func row(_ balance: FriendBalance) -> some View {
        let net = balance.byCurrency.values.reduce(0, +)
        let amounts = Money.formatByCurrency(balance.byCurrency.mapValues { abs($0) }).components(separatedBy: " + ")
        return HStack(spacing: 12) {
            Avatar(initial: balance.friend.initial, color: Theme.avatarColor(balance.friend.colorIndex), size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(balance.friend.name).font(Theme.disp(17)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(subtitle(for: balance)).font(Theme.text(12)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                if !balance.isClear {
                    Text(amounts[0]).font(Theme.disp(18)).foregroundStyle(Theme.ink).monospacedDigit()
                    ForEach(amounts.dropFirst(), id: \.self) { Text("+ \($0)").font(Theme.disp(13)).foregroundStyle(Theme.muted).monospacedDigit() }
                }
                if balance.isClear {
                    StatusTag(text: "all square", color: Theme.muted)
                } else if net < 0 {
                    StatusTag(text: "you owe", color: Theme.amber)
                } else {
                    StatusTag(text: "owes you", color: Theme.green)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .card()
        .padding(.bottom, 4)   // room for the raised edge, as the history rows do
        .contentShape(Rectangle())
    }

    /// What is still open with this friend, in the words of the bills themselves.
    private func subtitle(for balance: FriendBalance) -> String {
        guard let me else { return "" }
        let open = Money.ledger(for: balance.friend, splits: splits, payments: payments, me: me)
            .compactMap { entry -> String? in
                if case .split(let split, _, let settled) = entry, !settled { return split.displayTitle }
                return nil
            }
        return open.isEmpty ? "all settled up" : open.prefix(3).joined(separator: ", ")
    }

    /// "$74.40 + €18.00" with the extra currencies stepped down, the way the design has them.
    private func stacked(_ amount: String) -> some View {
        let parts = amount.components(separatedBy: " + ")
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(parts[0]).font(Theme.disp(40, .bold)).foregroundStyle(Theme.ink)
            if parts.count > 1 {
                Text(parts.dropFirst().map { "+ \($0)" }.joined(separator: " ")).font(Theme.disp(22)).foregroundStyle(Theme.muted)
            }
        }
        .lineLimit(1).minimumScaleFactor(0.6)   // a third currency, or an accessibility text size, still fits the line
    }
}
