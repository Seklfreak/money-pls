import Sentry
import SwiftData
import SwiftUI

@main
struct MoneyPlsApp: App {
    init() {
        // Debug builds stay quiet — local runs would drown real crash reports, and the placeholder
        // xcconfig has no DSN anyway. Receipts never leave the phone: no breadcrumbs of user data,
        // just crashes.
        #if !DEBUG
        if let dsn = AppConfig.sentryDSN {
            SentrySDK.start { options in
                options.dsn = dsn
                options.sendDefaultPii = false
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Theme.pink)
                .preferredColorScheme(.light)
        }
        .modelContainer(for: [Split.self, Person.self, LineItem.self])
    }
}
