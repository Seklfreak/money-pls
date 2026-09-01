import SwiftUI
import SwiftData

/// "All square with Carmen?" — writes down money that already changed hands.
///
/// Nothing is sent anywhere and nobody is asked to confirm: this is a note to yourself that moves
/// the balance. Direction follows the balance, so you never pick "who paid whom" by hand.
struct SettleUpSheet: View {
    let friend: Friend
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]
    @Query private var payments: [Payment]
    @State private var currency = Currency.default
    @State private var part = false
    @State private var partText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var started = false
    @FocusState private var amountFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.sand).frame(width: 40, height: 5).padding(.top, 12)
            if let me = Friend.me(in: context) { form(me: me) } else { unknownMe }
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear { Analytics.screen(.settle) }
    }

    private func form(me: Friend) -> some View {
        let open = balance(me: me)
        // No open line (or the last one just closed) leaves only a free-typed amount to record.
        let owed = open[currency] ?? 0
        let cents = part ? Currency.minorUnits(from: partText, code: currency) : abs(owed)
        return VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("All square with \(friend.name)?").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
                Text(owed < 0 ? "Record what you paid back." : "Record what came back. Nothing is sent anywhere.")
                    .font(Theme.text(13)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 18)
            directionCard(open: open, owed: owed, cents: cents, me: me)
            whenAndNote
            Text("This only updates the balance on your phone. Want \(friend.name) to know? Send the card afterwards, like always.")
                .font(Theme.text(13)).foregroundStyle(Theme.muted).lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            Spacer(minLength: 8)
            PrimaryButton(title: "Record payment", icon: "checkmark") { record(cents: cents, owed: owed, me: me) }
                .disabled(!isValid(cents: cents, owed: owed)).opacity(isValid(cents: cents, owed: owed) ? 1 : 0.5)
            Button("Not yet") { dismiss() }
                .font(Theme.text(13, .extrabold)).foregroundStyle(Theme.muted).padding(.top, 14)
        }
        .onAppear {
            guard !started else { return }   // re-running on every keystroke would fight the chips
            started = true
            let codes = openCurrencies(open)
            currency = codes.first ?? Currency.default
            part = codes.isEmpty
        }
    }

    private func directionCard(open: [String: Int], owed: Int, cents: Int, me: Friend) -> some View {
        // They owe me → the money comes from them; I owe → it goes the other way. A zero balance
        // reads as "they pay me", which is what a settle-up out of nowhere almost always is.
        let payer = owed < 0 ? me : friend
        let payee = owed < 0 ? friend : me
        return VStack(spacing: 18) {
            HStack(spacing: 18) {
                avatar(payer, isMe: payer.id == me.id)
                Image(systemName: "arrow.right").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.sand)
                avatar(payee, isMe: payee.id == me.id)
            }
            Text(cents.money(currency)).font(Theme.disp(48, .bold)).foregroundStyle(Theme.ink)
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
            FlowLayout(spacing: 8) {
                ForEach(openCurrencies(open), id: \.self) { code in
                    chip(label: code == currency && !part ? "\(abs(open[code] ?? 0).money(code)) · all of it" : abs(open[code] ?? 0).money(code),
                         on: code == currency) {
                        currency = code
                    }
                }
                chip(label: "Part", on: part) {
                    part.toggle()
                    amountFocused = part
                }
            }
            if part {
                TextField("0", text: $partText).focused($amountFocused)
                    .keyboardType(.decimalPad).multilineTextAlignment(.center)
                    .font(Theme.disp(20)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 16).frame(height: 48).frame(maxWidth: 180)
                    .raised(Capsule(), fill: Theme.bg, shadow: Theme.line, depth: 3)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 20)
        .card()
    }

    private var whenAndNote: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.muted)
                Text("When").font(Theme.text(15, .extrabold)).foregroundStyle(Theme.ink)
                Spacer()
                DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date).labelsHidden()
            }.padding(.vertical, 10)
            DottedRule()
            HStack(spacing: 12) {
                Image(systemName: "doc.text").font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.muted)
                Text("Note").font(Theme.text(15, .extrabold)).foregroundStyle(Theme.ink)
                TextField("cash at brunch", text: $note)
                    .font(Theme.text(14)).foregroundStyle(Theme.body).multilineTextAlignment(.trailing)
            }.padding(.vertical, 14)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
        .card()
    }

    private var unknownMe: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("Who are you?").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
            Text("A payment is always between you and someone else, and Money pls doesn't know which name is yours yet.")
                .font(Theme.text(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
            SecondaryButton(title: "Not yet") { dismiss() }
        }
    }

    private func avatar(_ who: Friend, isMe: Bool) -> some View {
        VStack(spacing: 6) {
            Avatar(initial: who.initial, color: Theme.avatarColor(who.colorIndex), size: 56)
            Text(isMe ? "you" : who.name).font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted).lineLimit(1)
        }
    }

    private func chip(label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(Theme.disp(13)).foregroundStyle(on ? Theme.bg : Theme.body).monospacedDigit()
                .padding(.horizontal, 14).padding(.vertical, 8)
                .raised(Capsule(), fill: on ? Theme.ink : .white, shadow: on ? Theme.inkDeep : Theme.line, depth: 2)
        }.buttonStyle(PressStyle())
    }

    private func balance(me: Friend) -> [String: Int] {
        Money.balances(splits: splits, payments: payments, me: me)
            .first { $0.friend.id == friend.id }?.byCurrency.filter { $0.value != 0 } ?? [:]
    }

    /// The phone's own currency first, same order the balance is printed in.
    private func openCurrencies(_ open: [String: Int]) -> [String] {
        let mine = Currency.default
        return open.keys.sorted { ($0 == mine) != ($1 == mine) ? $0 == mine : $0 < $1 }
    }

    /// "All of it" can only ever be the open balance; a part may be anything positive — paying
    /// more than the balance is how you go from owing to being owed, and that is allowed.
    private func isValid(cents: Int, owed: Int) -> Bool {
        cents > 0 && (part || cents <= abs(owed))
    }

    private func record(cents: Int, owed: Int, me: Friend) {
        guard isValid(cents: cents, owed: owed) else { return }
        let payment = owed < 0
            ? Payment(from: me, to: friend, cents: cents, currencyCode: currency, date: date, note: cleanNote)
            : Payment(from: friend, to: me, cents: cents, currencyCode: currency, date: date, note: cleanNote)
        context.insert(payment)
        Analytics.track("payment_recorded")
        dismiss()
    }

    private var cleanNote: String { String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)) }
}

#if DEBUG
#Preview {
    if let sample = FriendPreviewData.sample {
        Color.clear.sheet(isPresented: .constant(true)) {
            SettleUpSheet(friend: sample.friend).presentationDetents([.large])
        }
        .modelContainer(sample.container)
    }
}
#endif
