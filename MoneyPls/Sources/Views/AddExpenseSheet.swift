import SwiftUI

/// Placeholder — the real typed-expense sheet lands with the balances work.
struct AddExpenseSheet: View {
    let onDone: (Split?) -> Void

    init(onDone: @escaping (Split?) -> Void) {
        self.onDone = onDone
    }

    var body: some View { Text("Add an expense") }
}
