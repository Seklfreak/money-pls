import Sentry
import SwiftData
import SwiftUI

@main
struct MoneyPlsApp: App {
    private let container: ModelContainer

    init() {
        // Debug builds stay quiet — local runs would drown real crash reports, and the placeholder
        // xcconfig has no DSN anyway. Receipts never leave the phone: no breadcrumbs of user data,
        // just crashes.
        #if !DEBUG
        if let dsn = AppConfig.sentryDSN {
            SentrySDK.start { options in
                options.dsn = dsn
                options.sendDefaultPii = false
                // Off: the SDK never sees a watchdog kill, it infers one on
                // the next launch by elimination — no crash recorded, not
                // backgrounded, no upgrade, no reboot — which is also exactly
                // what swiping the app out of the app switcher looks like.
                // Every report so far has been one event per tester per
                // build, scattered, where a real memory problem repeats for
                // the same person; and the app runs at around 37 MB, which
                // is not a size anything gets killed for. If real numbers
                // are ever wanted they come from MetricKit's
                // MXAppExitMetric, which counts memory-limit exits the OS
                // actually performed, rather than from a guess here.
                options.enableWatchdogTerminationTracking = false
            }
        }
        // Same rule as Sentry: local runs would only muddy the numbers, and the placeholder
        // xcconfig has no Umami credentials anyway.
        Analytics.configure()
        #endif

        // Built by hand so the versioned migration plan runs; the backfill then gives Friends to
        // splits that predate them. A store we can't open is unrecoverable here — nothing to show.
        do {
            container = try ModelStore.container()
        } catch {
            fatalError("Could not open the Money pls store: \(error)")
        }
        FriendsBackfill.run(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .tint(Theme.pink)
                .preferredColorScheme(.light)
                // Fonts scale with Dynamic Type; the tray's fixed columns aren't reflowed for the AX sizes yet, so cap there.
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        }
        .modelContainer(container)
    }
}
