import SwiftUI
import SwiftData

/// One line of the feed. Cards aren't recorded anywhere yet, so this is bills and settle-ups.
private enum ActivityEntry: Identifiable {
    case split(Split)
    case payment(Payment)

    var date: Date {
        switch self {
        case .split(let split): split.createdAt
        case .payment(let payment): payment.date
        }
    }
    var id: UUID {
        switch self {
        case .split(let split): split.id
        case .payment(let payment): payment.id
        }
    }
}

/// The Activity tab: every bill and payment, newest first, one card per day.
struct ActivityView: View {
    @Binding var path: [Route]
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @Query private var payments: [Payment]
    @Query(filter: #Predicate<Friend> { $0.isMe }) private var meRows: [Friend]

    private var me: Friend? { meRows.first }

    /// Newest first, grouped by the day it happened on.
    private var days: [(day: Date, entries: [ActivityEntry])] {
        var all: [ActivityEntry] = splits.map { .split($0) }
        if let me {
            // Split-linked payments are the per-bill toggle writing itself down; the split's own row
            // already says that. Only a real settle-up is news.
            all += payments
                .filter { $0.split == nil && ($0.fromFriend?.id == me.id || $0.toFriend?.id == me.id) }
                .map { .payment($0) }
        }
        let calendar = Calendar.current
        return Dictionary(grouping: all.sorted { $0.date > $1.date }) { calendar.startOfDay(for: $0.date) }
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, entries: $0.value) }
    }

    var body: some View {
        ZStack {
            PageBackground(stop: 0.45)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    BrandHeader()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Activity").font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink)
                        Text("Every bill, payment and card, newest first.").font(Theme.text(14)).foregroundStyle(Theme.muted)
                    }
                    let days = days
                    if days.isEmpty {
                        Text("Nothing has happened yet. Scan a receipt and it shows up here.")
                            .font(Theme.text(14)).foregroundStyle(Theme.muted).padding(.top, 12)
                    }
                    ForEach(days, id: \.day) { day in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(caption(day.day)).font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted).kerning(0.5).padding(.horizontal, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                                    if index > 0 { DottedRule() }
                                    switch entry {
                                    case .split(let split):
                                        Button { path.append(.bill(split.id)) } label: { row(for: split).contentShape(Rectangle()) }
                                            .buttonStyle(PressStyle())
                                    case .payment(let payment):
                                        row(for: payment)
                                    }
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 4)
                            .card()
                            .padding(.bottom, 4)   // room for the raised edge
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { Analytics.screen(.activity) }
    }

    private func caption(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "TODAY" }
        if calendar.isDateInYesterday(day) { return "YESTERDAY" }
        return day.formatted(.dateTime.month(.abbreviated).day()).uppercased()
    }

    private func row(for split: Split) -> ActivityRow {
        let scanned = split.splitKind == .scanned
        let payer = split.payer
        let iPaid = me != nil && payer?.friend?.id == me?.id
        let total = split.totalCents.money(split.currencyCode)
        var sub = total
        if let payer, split.people.count >= 2 {
            sub += iPaid
                ? " · " + split.sortedPeople.map { $0.friend?.isMe == true ? "you" : $0.name }.joined(separator: ", ")
                : " · \(payer.name) paid"
        }
        var tag: String?, amount: String?, color = Theme.green
        if let me, split.people.count >= 2 {
            if iPaid {
                let lent = Money.outstanding(for: split)
                if lent > 0 { tag = "you lent"; amount = lent.money(split.currencyCode) }
            } else if let mine = Money.bills(for: split).first(where: { $0.person.friend?.id == me.id }), !mine.person.settled {
                tag = "you owe"; amount = mine.totalCents.money(split.currencyCode); color = Theme.amber
            }
        }
        return ActivityRow(
            icon: scanned ? "doc.plaintext" : "plus",
            tint: scanned ? Theme.amber : Theme.muted,
            background: scanned ? Theme.amberBg : Theme.line,
            label: "You \(scanned ? "scanned" : "added") \(split.displayTitle)",
            sub: sub, tag: tag, amount: amount, amountColor: color
        )
    }

    private func row(for payment: Payment) -> ActivityRow {
        let toMe = payment.toFriend?.id == me?.id
        let other = (toMe ? payment.fromFriend : payment.toFriend)?.name ?? "a friend"
        return ActivityRow(
            icon: "arrow.right", tint: Theme.green, background: Theme.green.opacity(0.12),
            label: toMe ? "\(other) paid you back" : "You paid \(other) back",
            sub: payment.note, tag: "payment", amount: payment.cents.money(payment.currencyCode), amountColor: Theme.muted
        )
    }
}

/// A feed row: tinted icon, what happened, and which way the money went.
private struct ActivityRow: View {
    let icon: String
    let tint: Color
    let background: Color
    let label: String
    let sub: String
    var tag: String?
    var amount: String?
    var amountColor: Color = Theme.muted

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(background)
                Image(systemName: icon).font(.system(size: 17, weight: .bold)).foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(Theme.disp(16)).foregroundStyle(Theme.ink).lineLimit(2)
                if !sub.isEmpty { Text(sub).font(Theme.text(12)).foregroundStyle(Theme.muted).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if let tag, let amount {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(tag).font(Theme.text(11, .extrabold)).foregroundStyle(amountColor)
                    Text(amount).font(Theme.disp(16)).foregroundStyle(amountColor).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 12)
    }
}
