import SwiftUI
import SwiftData

/// "Who's splitting?" — first names only; first person added is you (the payer).
struct PeopleSheet: View {
    @Bindable var split: Split
    let done: () -> Void
    @Environment(\.modelContext) private var context
    @Query private var friends: [Friend]
    @State private var name = ""
    @FocusState private var focused: Bool

    /// Friends from earlier splits, most recently used first, minus whoever is already here.
    private var suspects: [Friend] {
        let here = Set(split.people.map { $0.name.lowercased() })
        return friends.filter { !here.contains($0.name.lowercased()) }
            .sorted { ($0.lastUsedAt, $0.createdAt) > ($1.lastUsedAt, $1.createdAt) }
            .prefix(8).map { $0 }
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule().fill(Theme.sand).frame(width: 40, height: 5).padding(.top, 12)
            VStack(alignment: .leading, spacing: 2) {
                Text("Who's splitting?").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink)
                Text(split.people.isEmpty ? "Start with yourself — you paid. First names are fine." : "First names are fine. No accounts, no fuss.")
                    .font(Theme.text(13)).foregroundStyle(Theme.muted)
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                TextField(split.people.isEmpty ? "Your name" : "Add a friend", text: $name).focused($focused)
                    .font(Theme.text(16)).foregroundStyle(Theme.ink).submitLabel(.done).onSubmit(add)
                    .padding(.horizontal, 16).frame(height: 52).frame(maxWidth: .infinity)
                    .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
                Button(action: add) {
                    Text("Add").font(Theme.disp(16)).foregroundStyle(.white).padding(.horizontal, 20).frame(height: 52)
                        .raised(Capsule(), fill: Theme.pink, shadow: Theme.pinkShadow, depth: 4)
                }.buttonStyle(PressStyle()).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                VStack(spacing: 18) {
                    if !split.people.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(split.sortedPeople) { p in
                                HStack(spacing: 12) {
                                    Avatar(p, size: 44)
                                    Text(p.name).font(Theme.disp(17)).foregroundStyle(Theme.ink).lineLimit(1)
                                    Spacer()
                                    if p.id == split.payer?.id { Pill(bg: Theme.amberBg, fg: Theme.amber, shadow: false) { Text("you paid") } }
                                    Button { remove(p) } label: {
                                        Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(Theme.faint)
                                            .frame(width: 36, height: 36).background(Circle().fill(Theme.bg))
                                    }
                                }.padding(.vertical, 10)
                            }
                        }.padding(.horizontal, 16).padding(.vertical, 4).card()
                    }
                    if !suspects.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("USUAL SUSPECTS").font(Theme.text(12, .extrabold)).foregroundStyle(Theme.muted).kerning(0.5)
                            FlowLayout(spacing: 8) {
                                ForEach(suspects) { s in
                                    Button { add(s.name, preferredColor: s.colorIndex) } label: {
                                        HStack(spacing: 6) { Avatar(initial: s.initial, color: Theme.avatarColor(s.colorIndex), size: 28); Text(s.name).lineLimit(1) }
                                            .font(Theme.text(14, .extrabold)).foregroundStyle(Theme.body)
                                            .padding(.leading, 6).padding(.trailing, 14).frame(height: 40)
                                            .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 2)
                                    }.buttonStyle(PressStyle())
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            PrimaryButton(title: "Done", height: 52, fontSize: 17, fill: Theme.ink, shadow: Theme.inkDeep, fg: Theme.bg) {
                Analytics.track("people_done", ["count": String(split.people.count)])
                done()
            }
                .disabled(split.people.count < 2).opacity(split.people.count < 2 ? 0.5 : 1)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            Analytics.screen(.people)
            if split.people.isEmpty { focused = true }
        }
    }

    private func add() { add(name, preferredColor: nil); name = "" }
    private func add(_ raw: String, preferredColor: Int?) {
        let n = String(raw.trimmingCharacters(in: .whitespaces).prefix(24))   // a first name, not a paragraph
        guard !n.isEmpty, !split.people.contains(where: { $0.name.lowercased() == n.lowercased() }) else { return }
        let used = Set(split.people.map(\.colorIndex))
        let friend = Friend.resolve(name: n, in: context, preferredColor: preferredColor ?? split.people.count)
        // The Person keeps its own copy of the name and colour, so an old split still reads the
        // way it did — but a new one starts from whatever the friend is called now.
        var color = friend.colorIndex
        if used.contains(color) { color = (0..<Theme.avatarColors.count).first { !used.contains($0) } ?? split.people.count }
        let p = Person(name: friend.name, colorIndex: color, order: (split.people.map(\.order).max() ?? -1) + 1)
        p.friend = friend
        split.people.append(p)
        if split.payerID == nil { split.payerID = p.id }
        focused = true
    }
    private func remove(_ p: Person) {
        for item in split.items { item.assigneeIDs.removeAll { $0 == p.id } }
        if split.payerID == p.id { split.payerID = nil }
        context.delete(p)
        if split.payerID == nil { split.payerID = split.sortedPeople.first?.id }
    }
}

/// Simple wrapping HStack. Items are offered at most the full row width, so an overlong chip truncates
/// instead of running off the edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    private func size(_ s: LayoutSubview, maxWidth w: CGFloat) -> CGSize {
        let sz = s.sizeThatFits(.unspecified)
        return sz.width <= w ? sz : s.sizeThatFits(ProposedViewSize(width: w, height: nil))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity; var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews { let sz = size(s, maxWidth: w)
            if x + sz.width > w, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing; rowH = max(rowH, sz.height) }
        return CGSize(width: w == .infinity ? x : w, height: y + rowH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, rowH: CGFloat = 0
        for s in subviews { let sz = size(s, maxWidth: b.width)
            if x + sz.width > b.maxX, x > b.minX { x = b.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: sz.width, height: sz.height)); x += sz.width + spacing; rowH = max(rowH, sz.height) }
    }
}
