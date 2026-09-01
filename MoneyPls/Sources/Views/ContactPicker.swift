import ContactsUI
import SwiftUI

/// One person picked out of the address book: a first name and the id it came from. Nothing else —
/// no number, no photo, nothing that would have to be kept in step with Contacts later.
struct PickedContact {
    let name: String
    let identifier: String
}

/// The address-book picker, hung off an invisible view and presented the UIKit way on purpose:
/// `CNContactPickerViewController` dismisses *itself* once you are done with it, and a SwiftUI
/// `.sheet` dismissing it a second time takes the sheet underneath down with it.
///
/// It runs out of process and hands back only what was tapped, so it needs no contacts permission
/// and no usage-description key.
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var presented: Bool
    /// Everyone picked in one go. Not called when the picker was cancelled.
    let onPick: ([PickedContact]) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.isUserInteractionEnabled = false   // an anchor to present from, not a view
        return host
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        context.coordinator.onPick = onPick
        context.coordinator.done = { presented = false }
        guard presented, !context.coordinator.showing, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        // Swiping the picker away is neither "select" nor "cancel" as far as CNContactPicker is
        // concerned, so the adaptive delegate is what puts the binding back.
        picker.presentationController?.delegate = context.coordinator
        context.coordinator.showing = true
        host.present(picker, animated: true)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Implementing the *plural* `didSelect` is what puts the picker into multi-select mode.
    /// Nested in a `View`, so the class is main-actor isolated and the two UIKit delegates — which
    /// only ever call it on the main thread anyway — need the `@preconcurrency` nod.
    final class Coordinator: NSObject, @preconcurrency CNContactPickerDelegate, @preconcurrency UIAdaptivePresentationControllerDelegate {
        var onPick: ([PickedContact]) -> Void = { _ in }
        var done: () -> Void = {}
        var showing = false

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            finish(contacts.compactMap(Self.picked))
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { finish([]) }
        func presentationControllerDidDismiss(_ controller: UIPresentationController) { finish([]) }

        /// Whichever way the picker goes away, it lands here exactly once.
        private func finish(_ contacts: [PickedContact]) {
            guard showing else { return }
            showing = false
            done()
            if !contacts.isEmpty { onPick(contacts) }
        }

        /// First names are what the app shows, so that is what it takes; a contact filed under a
        /// company or a single name falls back to whatever it does have. `CNContactFormatter` is
        /// avoided on purpose — it wants keys the picker doesn't promise to have fetched.
        private static func picked(_ contact: CNContact) -> PickedContact? {
            let parts = [contact.givenName, contact.familyName, contact.organizationName]
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = parts.first(where: { !$0.isEmpty }) else { return nil }
            return PickedContact(name: name, identifier: contact.identifier)
        }
    }
}
