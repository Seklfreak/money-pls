import SwiftUI

/// Placeholder — the real friend detail lands with the balances work.
struct FriendDetailView: View {
    let friend: Friend
    @Binding var path: [Route]

    init(friend: Friend, path: Binding<[Route]>) {
        self.friend = friend
        self._path = path
    }

    var body: some View { Text(friend.name) }
}
