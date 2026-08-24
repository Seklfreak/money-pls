import SwiftUI
import SwiftData

@main
struct MoneyPlsApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Theme.pink)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [Split.self, Person.self, LineItem.self])
    }
}
