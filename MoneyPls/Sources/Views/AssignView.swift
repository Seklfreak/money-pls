import SwiftUI
import SwiftData

/// "Who had what?" — tap a receipt line, pick people in the tray below. Everything is shared unless you say so.
struct AssignView: View {
    @Bindable var split: Split
    @Binding var path: [Route]
    @State private var selected: LineItem?

    private var stats: (all: Int, solo: Int, shared: Int, nobody: Int) {
        var a = 0, s = 0, sh = 0, n = 0
        for i in split.items { if i.everyone { a += 1 } else if i.assigneeIDs.count == 1 { s += 1 } else if i.assigneeIDs.isEmpty { n += 1 } else { sh += 1 } }
        return (a, s, sh, n)
    }

    var body: some View {
        ZStack {
            PageBackground()
            VStack(spacing: 14) {
                BrandHeader { path.removeLast() }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Who had what?").font(Theme.disp(30, .bold)).foregroundStyle(Theme.ink)
                    Text("Everything's shared unless you tap it").font(Theme.text(14)).foregroundStyle(Theme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                // Pills never wrap: when the amber "nobody" pill appears the row scrolls instead of reflowing and shoving the tray.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        let st = stats
                        Pill { Image(systemName: "person.2.fill").font(.system(size: 11)); Text("\(st.all) for all") }
                        Pill { Circle().fill(Theme.avatarColor(1)).frame(width: 10, height: 10); Text("\(st.solo) solo") }
                        Pill { Circle().fill(Theme.mint).frame(width: 10, height: 10); Text("\(st.shared) shared") }
                        if st.nobody > 0 { Pill(bg: Theme.amberBg, fg: Theme.amber, shadow: false) { Text("\(st.nobody) nobody") } }
                    }
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 2).padding(.bottom, 3)
                }
                .padding(.horizontal, -2).frame(height: 34)
                TrayScroll {
                    Tray {
                        Text(split.displayTitle).font(Theme.disp(16, .bold)).foregroundStyle(Theme.ink)
                        Text("\(split.people.count) hungry people").font(Theme.text(12)).foregroundStyle(Theme.muted).padding(.bottom, 8)
                        DottedRule().padding(.bottom, 6)
                        ForEach(split.sortedItems) { item in
                            ReceiptLine(item: item, people: split.sortedPeople, selected: selected?.id == item.id)
                                .contentShape(Rectangle())
                                .onTapGesture { tap(item) }
                                .onLongPressGesture { quickAssignToMe(item) }
                        }
                        DottedRule().padding(.vertical, 6)
                        HStack { Text(split.tipCents > 0 ? "Tax + tip" : "Tax"); Spacer(); Text((split.taxCents + split.tipCents).moneyPlain(split.currencyCode)).monospacedDigit() }
                            .font(Theme.text(13)).foregroundStyle(Theme.muted)
                        HStack { Text("Total"); Spacer(); Text(split.totalCents.money(split.currencyCode)).monospacedDigit() }
                            .font(Theme.disp(17, .bold)).foregroundStyle(Theme.ink)
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 16)
            .safeAreaInset(edge: .bottom) {
                Footer {
                    if let item = selected {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(item.displayName).lineLimit(1)
                                    Text("· \(item.priceCents.money(split.currencyCode))").monospacedDigit().fixedSize().layoutPriority(1)
                                }.font(Theme.disp(18)).foregroundStyle(Theme.ink)
                                if let t = item.subtitle { Text(t).font(Theme.text(12)).foregroundStyle(Theme.muted).lineLimit(1) }
                                Text(shareText(item)).font(Theme.text(13)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Button { withAnimation { item.everyone = true; item.assigneeIDs = [] } } label: {
                                Pill(bg: item.everyone ? Theme.ink : .white, fg: item.everyone ? Theme.bg : Theme.body) { Image(systemName: "person.2.fill").font(.system(size: 11)); Text("Everyone") }
                            }
                        }
                        // Up to five people share the width; beyond that, cells are 2/11 wide so the sixth peeks
                        // in half-cut — the only hint that the row scrolls.
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(split.sortedPeople) { p in
                                    let on = item.everyone || item.assigneeIDs.contains(p.id)
                                    Button { toggle(p, on: item) } label: {
                                        VStack(spacing: 6) {
                                            Avatar(p, size: 56, dim: !on, check: on)
                                                .background(Circle().fill(Theme.avatarColor(p.colorIndex).opacity(on ? 0.6 : 0)).offset(y: 4))
                                                .offset(y: on ? -4 : 0)
                                            Text(p.name).font(Theme.text(12, on ? .extrabold : .bold)).foregroundStyle(on ? Theme.ink : Theme.faint).lineLimit(1)
                                        }
                                        .containerRelativeFrame(.horizontal, count: split.people.count > 5 ? 11 : max(split.people.count, 1),
                                                                span: split.people.count > 5 ? 2 : 1, spacing: 8)
                                    }.buttonStyle(PressStyle())
                                }
                            }
                        }
                        .scrollClipDisabled()
                    } else {
                        Text("Tap a line to change who had it. Long-press to claim it yourself.")
                            .font(Theme.text(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                    }
                    // The bill is the finish line; whether we came from Items or back from the bill, it stands alone.
                    PrimaryButton(title: "Show me the bill") { path = [.bill(split.id)] }
                        .disabled(!split.unassignedItems.isEmpty).opacity(split.unassignedItems.isEmpty ? 1 : 0.5)
                }
                .animation(.snappy, value: selected?.id)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.currency, split.currencyCode)
    }

    private func shareText(_ item: LineItem) -> String {
        let n = item.everyone ? split.people.count : item.assigneeIDs.count
        if n == 0 { return "Nobody yet — pick someone" }
        if n == 1 { return "Just one person" }
        return "\(n) ways · \((item.priceCents / n).money(split.currencyCode)) each"
    }
    private func tap(_ item: LineItem) {
        withAnimation(.snappy) {
            if selected?.id == item.id { item.everyone = true; item.assigneeIDs = []; selected = nil }   // second tap → back to everyone
            else { selected = item }
        }
    }
    private func quickAssignToMe(_ item: LineItem) {
        guard let me = split.payer else { return }
        withAnimation(.snappy) { item.everyone = false; item.assigneeIDs = [me.id]; selected = item }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
    private func toggle(_ p: Person, on item: LineItem) {
        withAnimation(.snappy) {
            if item.everyone {
                item.everyone = false; item.assigneeIDs = [p.id]   // narrowing from everyone: start with just this person
            } else if item.assigneeIDs.contains(p.id) {
                item.assigneeIDs.removeAll { $0 == p.id }
            } else {
                item.assigneeIDs.append(p.id)
                if item.assigneeIDs.count == split.people.count { item.everyone = true; item.assigneeIDs = [] }
            }
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

/// One line on the receipt, styled per the line-state spec: quiet for "everyone", colored rail for one person,
/// stacked avatars for a few, amber for nobody, dark outline when selected.
struct ReceiptLine: View {
    @Environment(\.currency) private var currency
    let item: LineItem
    let people: [Person]
    let selected: Bool
    var body: some View {
        let who = people.filter { item.assigneeIDs.contains($0.id) }
        let rail: Color = item.everyone ? .clear : who.count == 1 ? Theme.avatarColor(who[0].colorIndex) : who.isEmpty ? Theme.amber : Theme.sand
        let tint: Color = selected ? Theme.amberBg : item.everyone ? .clear : who.count == 1 ? Theme.avatarColor(who[0].colorIndex).opacity(0.12) : who.isEmpty ? Theme.amberBg : Color(hex: 0xfaf3ea)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName).font(Theme.text(14)).foregroundStyle(Theme.ink).lineLimit(2).multilineTextAlignment(.leading)
                if let t = item.subtitle { Text(t).font(Theme.text(11)).foregroundStyle(Theme.muted).lineLimit(1) }
            }
            Spacer(minLength: 4)
            if item.everyone {
                HStack(spacing: 4) { Image(systemName: "person.2.fill").font(.system(size: 10)); Text("ALL").kerning(0.6) }
                    .font(Theme.text(10, .extrabold)).foregroundStyle(Theme.faint)
            } else if who.isEmpty {
                Text("NOBODY").font(Theme.text(10, .extrabold)).kerning(0.6).foregroundStyle(Theme.amber)
            } else {
                AvatarStack(people: who)
            }
            Text(item.priceCents.moneyPlain(currency)).font(Theme.text(14)).foregroundStyle(Theme.ink).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 10).padding(.vertical, 4).frame(minHeight: 42)
        .background(
            // The rail lives inside the rounded tint and gives way to the outline while selected.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10).fill(tint)
                if !selected { Rectangle().fill(rail).frame(width: 4) }
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        )
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.pink, lineWidth: selected ? 2.5 : 0))
        .padding(.horizontal, -10)
    }
}
