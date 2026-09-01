import SwiftUI
import SwiftData

/// "You" — the one friend every balance is measured against. Nothing here leaves the phone, so
/// there is not much to say: your name, how many people you split with, and Done.
struct YouSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var friends: [Friend]
    @State private var name = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    init() {}

    private var me: Friend? { friends.first { $0.isMe } }
    /// Everyone but you — "Friends · 6" counts the other side of the table.
    private var others: Int { friends.filter { !$0.isMe }.count }
    /// Nobody has claimed the `isMe` row yet (a fresh install), so the sheet asks instead of showing.
    private var naming: Bool { me == nil || editing }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.sand).frame(width: 40, height: 5).padding(.top, 12)
            HStack(spacing: 14) {
                Avatar(initial: me?.initial ?? "?", color: Theme.avatarColor(me?.colorIndex ?? 0), size: 56, dim: me == nil)
                VStack(alignment: .leading, spacing: 2) {
                    if naming {
                        TextField("Your name", text: $name).focused($focused)
                            .font(Theme.text(16)).foregroundStyle(Theme.ink).submitLabel(.done).onSubmit(save)
                            .padding(.horizontal, 16).frame(height: 48).frame(maxWidth: .infinity)
                            .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
                    } else {
                        Button { name = me?.name ?? ""; editing = true; focused = true } label: {
                            HStack(spacing: 6) {
                                Text(me?.name ?? "").font(Theme.disp(24, .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                                Image(systemName: "pencil").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.faint)
                            }
                        }.buttonStyle(PressStyle()).accessibilityLabel("Change your name")
                        Text("you").font(Theme.text(13)).foregroundStyle(Theme.muted)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 18)
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.muted).frame(width: 20)
                Text("Friends").font(Theme.text(15, .extrabold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(others) · all on this phone").font(Theme.text(14)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .card().padding(.top, 18)
            Text("Receipts, names and balances live on this phone and nowhere else.")
                .font(Theme.text(12)).foregroundStyle(Theme.faint).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4).padding(.top, 16)
            Spacer(minLength: 16)
            PrimaryButton(title: "Done", height: 52, fontSize: 17, fill: Theme.ink, shadow: Theme.inkDeep, fg: Theme.bg) {
                save()
                dismiss()
            }
            .disabled(!canDone).opacity(canDone ? 1 : 0.5)
        }
        .padding(.horizontal, 16).padding(.bottom, 16)
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            Analytics.screen(.you)
            if me == nil { focused = true }
        }
    }

    /// Done can't finish a sheet that still doesn't know who you are.
    private var canDone: Bool { me != nil || !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func save() {
        let clean = String(name.trimmingCharacters(in: .whitespaces).prefix(24))
        guard naming, !clean.isEmpty else { return }
        if let me {
            me.name = clean
        } else {
            // `resolve` on purpose: if you have been on splits under this name all along, that row
            // is you — minting a second one would split your own history in two.
            Friend.resolve(name: clean, in: context, preferredColor: friends.count).isMe = true
        }
        editing = false
    }
}

#Preview {
    if let store = try? ModelStore.container(inMemory: true) {
        YouSheet().modelContainer(store).preferredColorScheme(.light)
    }
}
