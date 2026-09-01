import SwiftUI
import SwiftData

/// How the amount is carved up. Only the tray differs — every mode ends up as line items, so the
/// bill, the cards and the balances downstream can't tell a typed expense from a scanned one.
enum SplitMode: String, CaseIterable {
    case equally, shares, exact
    var label: String { rawValue.capitalizedFirst }
}

/// "Add an expense" — a split typed in by hand, for when there is no receipt to scan.
struct AddExpenseSheet: View {
    /// The finished split, or nil when the sheet was swiped away.
    let onDone: (Split?) -> Void
    @Environment(\.modelContext) private var context
    @Query private var friends: [Friend]
    @Query(sort: \Split.createdAt, order: .reverse) private var splits: [Split]

    @State private var title = ""
    @State private var amountCents = 0
    @State private var amountText = ""
    @State private var code = Currency.default
    @State private var payerID: UUID?
    @State private var chosen: Set<UUID> = []
    @State private var mode: SplitMode = .equally
    @State private var weights: [UUID: Int] = [:]
    @State private var exact: [UUID: Int] = [:]
    @State private var done = false
    @State private var adding = false
    @FocusState private var amountFocused: Bool
    @FocusState private var nameFocused: Bool

    init(onDone: @escaping (Split?) -> Void) { self.onDone = onDone }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.sand).frame(width: 40, height: 5).padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Add an expense").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
                Text("No receipt? Type it in. Same split, same cards.").font(Theme.text(13)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 18)
            ScrollView {
                VStack(spacing: 22) {
                    TextField("What was it?", text: $title)
                        .font(Theme.text(16)).foregroundStyle(Theme.ink).submitLabel(.done)
                        .padding(.horizontal, 16).frame(height: 52).frame(maxWidth: .infinity)
                        .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
                    tray
                }
                .padding(.top, 18).padding(.bottom, 12)   // room inside the clip for the tray's shadow
            }
            .scrollDismissesKeyboard(.interactively)
            PrimaryButton(title: "Add it", height: 52, fontSize: 17, fill: Theme.ink, shadow: Theme.inkDeep, fg: Theme.bg, action: save)
                .disabled(!canSave).opacity(canSave ? 1 : 0.5)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
        .environment(\.currency, code)
        .onAppear {
            Analytics.screen(.addExpense)
            start()
        }
        // A swipe-down never reaches the button, and nothing else tells the shell the sheet is gone.
        .onDisappear { if !done { onDone(nil) } }
    }

    // MARK: - The tray

    private var tray: some View {
        Tray {
            label("AMOUNT")
            HStack(spacing: 10) {
                // The field holds the plain number while it is being typed into and the formatted
                // amount once it isn't — a currency symbol glued to the text is only in the way.
                TextField(0.moneyPlain(code), text: $amountText)
                    .keyboardType(.decimalPad).focused($amountFocused)
                    .font(Theme.disp(40, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                currencyChip
            }
            DottedRule().padding(.vertical, 10)
            label("PAID BY")
            FlowLayout(spacing: 8) {
                ForEach(everyone) { payerChip($0) }
                // "Never mind" with nobody to go back to would only re-empty the tray.
                if !adding || everyone.count >= 2 { addChip }
            }.padding(.top, 8)
            // Named right here, or the sheet is a dead end on a store with nobody in it yet.
            if adding {
                AddPersonBar(placeholder: me == nil ? "Your name" : "or type a name", focus: $nameFocused, onAdd: addPerson)
                    .padding(.top, 12)
            }
            DottedRule().padding(.vertical, 10)
            HStack(spacing: 8) {
                label("SPLIT")
                // The pills say what they say; the label gives way to them, not the other way round.
                modePicker.fixedSize()
            }
            VStack(spacing: 0) { ForEach(everyone) { row($0) } }.padding(.top, 4)
            if mode == .exact {
                Text(leftover == 0 ? "Every cent assigned"
                     : leftover > 0 ? "\(leftover.money(code)) left to assign" : "\(abs(leftover).money(code)) too much")
                    .font(Theme.text(12, .extrabold)).foregroundStyle(leftover == 0 ? Theme.green : Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 6)
            }
        }
        // Parsed on every keystroke, not on the way out: the shares under it and the Add button both
        // read the amount while it is still being typed, and a field left focused would strand them.
        .onChange(of: amountText) { _, text in if amountFocused { amountCents = Currency.minorUnits(from: text, code: code) } }
        .onChange(of: amountFocused) { _, focused in
            amountText = amountCents > 0 ? (focused ? amountCents.moneyPlain(code) : amountCents.money(code)) : ""
        }
        .onChange(of: code) { _, new in if !amountFocused, amountCents > 0 { amountText = amountCents.money(new) } }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted).kerning(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var currencyChip: some View {
        Menu {
            ForEach(Currency.supported, id: \.self) { c in
                Button { code = c } label: { if c == code { Label(c, systemImage: "checkmark") } else { Text(c) } }
            }
        } label: {
            HStack(spacing: 4) { Text(code); Image(systemName: "chevron.down").font(.system(size: 9, weight: .heavy)) }
                .font(Theme.disp(13)).foregroundStyle(Theme.body).kerning(0.3)
                .padding(.leading, 12).padding(.trailing, 10).frame(height: 32)
                .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 2)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 6) {
            ForEach(SplitMode.allCases, id: \.self) { m in
                let on = m == mode
                Button { mode = m } label: {
                    Text(m.label).font(Theme.disp(13)).foregroundStyle(on ? Theme.bg : Theme.body)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .raised(Capsule(), fill: on ? Theme.ink : .white, shadow: on ? .clear : Theme.line, depth: 2)
                }.buttonStyle(PressStyle())
            }
        }
    }

    private func payerChip(_ friend: Friend) -> some View {
        let on = friend.id == payerID
        // Whoever paid is on the bill too — see `toggle`.
        return Button { payerID = friend.id; chosen.insert(friend.id) } label: {
            HStack(spacing: 6) {
                Avatar(initial: friend.initial, color: Theme.avatarColor(friend.colorIndex), size: 28)
                Text(name(friend)).lineLimit(1)
            }
            .font(Theme.text(14, .extrabold)).foregroundStyle(on ? Theme.bg : Theme.body)
            .padding(.leading, 6).padding(.trailing, 14).frame(height: 40)
            .raised(Capsule(), fill: on ? Theme.ink : .white, shadow: on ? Theme.inkDeep : Theme.line, depth: 2)
        }.buttonStyle(PressStyle())
    }

    /// The way into `AddPersonBar`: dashed, so it reads as the gap at the end of the row rather than
    /// as one more person already on the split.
    private var addChip: some View {
        Button {
            adding.toggle()
            nameFocused = adding
        } label: {
            HStack(spacing: 6) {
                Image(systemName: adding ? "xmark" : "plus").font(.system(size: 12, weight: .heavy))
                Text(adding ? "Never mind" : "Add someone").lineLimit(1)
            }
            .font(Theme.text(14, .extrabold)).foregroundStyle(Theme.muted)
            .padding(.horizontal, 14).frame(height: 40)
            .background(Capsule().strokeBorder(Theme.sand, style: StrokeStyle(lineWidth: 2, dash: [5, 4])))
        }.buttonStyle(PressStyle())
    }

    private func row(_ friend: Friend) -> some View {
        let on = chosen.contains(friend.id)
        return HStack(spacing: 10) {
            Button { toggle(friend) } label: {
                Image(systemName: on ? "checkmark" : "circle")
                    .font(.system(size: on ? 16 : 14, weight: .bold)).foregroundStyle(on ? Theme.green : Theme.sand)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(on ? "\(name(friend)) is splitting" : "\(name(friend)) is not splitting")
            Avatar(initial: friend.initial, color: Theme.avatarColor(friend.colorIndex), size: 28, dim: !on)
            Text(name(friend)).font(Theme.text(14, .extrabold)).foregroundStyle(on ? Theme.body : Theme.faint).lineLimit(1)
            Spacer(minLength: 8)
            if on {
                if mode == .shares { weightStepper(friend) }
                if mode == .exact {
                    ExactField(cents: Binding(get: { exact[friend.id] ?? 0 }, set: { exact[friend.id] = $0 }), code: code)
                        .frame(width: 88, height: 34)
                } else {
                    Text((shares[friend.id] ?? 0).money(code)).font(Theme.disp(15)).foregroundStyle(Theme.ink).monospacedDigit()
                }
            }
        }.padding(.vertical, 8)
    }

    /// ×1 ×2 ×3 … how many shares of the bill this one is worth.
    private func weightStepper(_ friend: Friend) -> some View {
        let weight = weights[friend.id] ?? 1
        // "×2" next to an avatar says everything by sight and nothing out loud, so each button
        // carries who it is about and what it is worth now, and the hint says what it does.
        let spoken = "\(name(friend)), \(weight) share\(weight == 1 ? "" : "s")"
        return HStack(spacing: 2) {
            stepButton("minus", label: spoken, hint: "Remove a share", enabled: weight > 1) { weights[friend.id] = weight - 1 }
            Text("×\(weight)").font(Theme.text(13, .extrabold)).foregroundStyle(Theme.ink).monospacedDigit().frame(width: 24)
                .accessibilityHidden(true)
            stepButton("plus", label: spoken, hint: "Add a share", enabled: weight < 9) { weights[friend.id] = weight + 1 }
        }
        .padding(.horizontal, 4).frame(height: 30)
        .background(Capsule().fill(Theme.bg))
    }

    private func stepButton(_ system: String, label: String, hint: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 11, weight: .heavy)).foregroundStyle(enabled ? Theme.body : Theme.line)
                .frame(width: 24, height: 26)
        }
        .buttonStyle(PressStyle()).disabled(!enabled)
        .accessibilityLabel(label).accessibilityHint(hint)
    }

    // MARK: - What the tray adds up to

    /// Everyone the sheet offers: you first, then whoever was on a split most recently.
    private var everyone: [Friend] {
        friends.sorted {
            $0.isMe == $1.isMe ? ($0.lastUsedAt, $0.createdAt) > ($1.lastUsedAt, $1.createdAt) : $0.isMe
        }
    }
    private var splitting: [Friend] { everyone.filter { chosen.contains($0.id) } }
    private var me: Friend? { friends.first { $0.isMe } }
    private func name(_ friend: Friend) -> String { friend.isMe ? "You" : friend.name }

    /// What each person ends up owing, by mode. Cents, summing to the amount (except in Exact,
    /// which is the user's arithmetic until it does).
    private var shares: [UUID: Int] {
        let ids = splitting.map(\.id)
        guard !ids.isEmpty else { return [:] }
        switch mode {
        case .equally: return Dictionary(uniqueKeysWithValues: zip(ids, Money.divide(amountCents, into: ids.count)))
        case .shares: return Dictionary(uniqueKeysWithValues: zip(ids, Money.allocate(amountCents, weights: ids.map { Double(weights[$0] ?? 1) })))
        case .exact: return Dictionary(uniqueKeysWithValues: ids.map { ($0, exact[$0] ?? 0) })
        }
    }
    private var leftover: Int { amountCents - shares.values.reduce(0, +) }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && amountCents > 0 && splitting.count >= 2
            && (mode != .exact || leftover == 0)
    }

    private func start() {
        guard payerID == nil else { return }   // coming back from the keyboard, not opening
        code = splits.first?.currencyCode ?? Currency.default
        payerID = everyone.first { $0.isMe }?.id ?? everyone.first?.id
        chosen = Set(everyone.map(\.id))
        // Nobody to split with yet: open with the bar out rather than with an empty tray.
        adding = everyone.count < 2
    }

    /// Somebody named in this sheet. Same rules as `PeopleSheet`, because they make the same rows:
    /// one free colour each, the address-book id kept the first time it turns up, and — on a store
    /// that still has no "you" — the first name given is yours, which is why the field asks for it.
    private func addPerson(_ raw: String, contactIdentifier: String?) {
        let clean = String(raw.trimmingCharacters(in: .whitespaces).prefix(24))   // a first name, not a paragraph
        guard !clean.isEmpty else { return }
        let nobodyIsMe = Friend.me(in: context) == nil
        // Two friends sharing a colour would be one blur of avatars on the bill; take a free one.
        let used = Set(friends.map(\.colorIndex))
        let free = (0..<Theme.avatarColors.count).first { !used.contains($0) } ?? friends.count
        let friend = Friend.resolve(name: clean, in: context, preferredColor: free)
        if let contactIdentifier, friend.contactIdentifier == nil { friend.contactIdentifier = contactIdentifier }
        if nobodyIsMe { friend.isMe = true }
        chosen.insert(friend.id)
        if payerID == nil { payerID = friend.id }
        nameFocused = contactIdentifier == nil   // a keyboard over the list you just picked from is only in the way
    }

    private func toggle(_ friend: Friend) {
        // The payer stays in: an "everyone" line item means everyone on the split, so a payer who
        // isn't splitting would quietly take a share anyway. Hand the paying over first.
        guard friend.id != payerID else { return }
        if chosen.contains(friend.id) { chosen.remove(friend.id) } else { chosen.insert(friend.id) }
    }
}

// MARK: - Writing it down

extension AddExpenseSheet {
    fileprivate func save() {
        let people = splitting
        let split = Split(title: title.trimmingCharacters(in: .whitespaces))
        split.splitKind = .typed
        split.currencyCode = code
        context.insert(split)

        // Same de-duplication as PeopleSheet: two friends who share a colour would be one blur of
        // avatars on the bill, so the second one borrows the first free colour instead.
        var used: Set<Int> = []
        var persons: [UUID: Person] = [:]
        for (i, friend) in people.enumerated() {
            var color = friend.colorIndex
            if used.contains(color) { color = (0..<Theme.avatarColors.count).first { !used.contains($0) } ?? i }
            used.insert(color)
            let person = Person(name: friend.name, colorIndex: color, order: i)
            person.friend = friend
            split.people.append(person)
            persons[friend.id] = person
        }
        split.payerID = payerID.flatMap { persons[$0]?.id } ?? persons[people[0].id]?.id

        // Line items chosen so `Money.bills` lands on exactly the shares the tray showed: one line
        // everybody is on when it's an even split, one line each when it isn't.
        if mode == .equally {
            split.items.append(LineItem(name: split.title, quantity: 1, priceCents: amountCents, order: 0))
        } else {
            let shares = self.shares
            for (i, friend) in people.enumerated() {
                guard let person = persons[friend.id] else { continue }
                let item = LineItem(name: split.title, quantity: 1, priceCents: shares[friend.id] ?? 0, order: i)
                item.everyone = false
                item.assigneeIDs = [person.id]
                split.items.append(item)
            }
        }

        Analytics.track("expense_added", ["mode": mode.rawValue, "people": String(people.count)])
        done = true
        onDone(split)
    }
}

/// The Exact column. `CentsField` only commits when it loses focus, which would leave the footer's
/// "left to assign" — and the Add button that waits on it — a keystroke behind the row you are in.
private struct ExactField: View {
    @Binding var cents: Int
    let code: String
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(0.moneyPlain(code), text: $text)
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).focused($focused)
            .font(Theme.text(15)).foregroundStyle(Theme.ink).monospacedDigit()
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
            .onAppear { text = cents > 0 ? cents.moneyPlain(code) : "" }
            .onChange(of: text) { _, typed in cents = Currency.minorUnits(from: typed, code: code) }
            .onChange(of: focused) { _, on in if !on { text = cents > 0 ? cents.moneyPlain(code) : "" } }
    }
}

/// Three friends in an in-memory store, so the preview has chips and rows to show.
@MainActor private func previewStore() -> ModelContainer? {
    guard let store = try? ModelStore.container(inMemory: true) else { return nil }
    for (i, name) in ["Seb", "Carmen", "Jonas"].enumerated() {
        let friend = Friend(name: name, colorIndex: i + 3)
        friend.isMe = i == 0
        store.mainContext.insert(friend)
    }
    return store
}

#Preview {
    if let store = previewStore() {
        AddExpenseSheet { _ in }.modelContainer(store).preferredColorScheme(.light)
    }
}
