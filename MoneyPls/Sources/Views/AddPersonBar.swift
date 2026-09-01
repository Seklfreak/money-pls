import SwiftUI

/// The two ways to name somebody: straight out of the address book, or typed in.
///
/// Lives on its own because both sheets that make people need it — "Who's splitting?" and
/// "Add an expense", where without it a fresh install has nobody to split with and no way to say so.
/// It only hands names back; what a name *becomes* (a `Person` on this split, or a `Friend` on the
/// tray) is the caller's business.
struct AddPersonBar: View {
    /// Placeholder on the typed-name field — "Your name" when the first person named is you.
    var placeholder = "or type a name"
    /// The caller's focus state, so it can put the keyboard back where it wants it after an add.
    var focus: FocusState<Bool>.Binding
    /// One person: a first name, plus the address-book id when that is where it came from.
    let onAdd: (String, String?) -> Void

    @State private var name = ""
    @State private var showContacts = false

    var body: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Pick from Contacts", icon: "person.2.fill", height: 52, fontSize: 17) { showContacts = true }
            HStack(spacing: 8) {
                TextField(placeholder, text: $name).focused(focus)
                    .font(Theme.text(16)).foregroundStyle(Theme.ink).submitLabel(.done).onSubmit(addTyped)
                    .padding(.horizontal, 16).frame(height: 52).frame(maxWidth: .infinity)
                    .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
                // Quiet next to the pink Contacts button — two shouting buttons on one row read as a choice you have to make.
                Button(action: addTyped) {
                    Text("Add").font(Theme.disp(16)).foregroundStyle(typed.isEmpty ? Theme.faint : Theme.ink)
                        .padding(.horizontal, 20).frame(height: 52)
                        .raised(Capsule(), fill: .white, shadow: Theme.line, depth: 3)
                }.buttonStyle(PressStyle()).disabled(typed.isEmpty)
            }
        }
        // The picker is presented from here rather than wrapped in a `.sheet` — see `ContactPicker`.
        .background(ContactPicker(presented: $showContacts, onPick: picked))
    }

    private var typed: String { name.trimmingCharacters(in: .whitespaces) }

    private func addTyped() {
        guard !typed.isEmpty else { return }
        onAdd(typed, nil)
        name = ""
    }

    /// The one place the pick is counted, however many sheets end up showing this bar.
    private func picked(_ contacts: [PickedContact]) {
        Analytics.track("contacts_picked", ["count": String(contacts.count)])
        for contact in contacts { onAdd(contact.name, contact.identifier) }
    }
}
