import SwiftUI

/// The one weather question, asked once. Shared by the first-launch window and the Settings row that
/// stands in for it afterwards, so both spell out the same provider, cadence and payload.
struct WeatherConsentContent: View {
    let onDecline: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text("Show the weather on the clock?")
                .font(.headline)

            Text(
                "Spotter reads this Mac's approximate location — one coarse fix, accurate to a few "
                    + "kilometres, never a precise one — and asks \(DashboardWeatherStore.provider) "
                    + "for the current conditions there, every 30 minutes while Spotter is running. "
                    + "Only those coordinates leave your Mac: no account, no identifiers, and the "
                    + "latest reading is kept here. The forecast also names that place's time zone, "
                    + "which is what the clock then runs on. macOS will ask for permission to use "
                    + "your location next; say no to either and Spotter shows no weather at all — "
                    + "there is no city to type instead. Spotter asks this once."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: DashboardWeatherStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(DashboardWeatherStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("No Thanks", action: onDecline)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
    }
}

/// The first-launch window. It is its own window rather than a sheet because at that moment Spotter
/// has no window of its own to hang one on.
struct WeatherConsentWindow: View {
    static let windowSize = CGSize(width: 460, height: 300)
    /// True only for the wizard's hand-off, where the launcher is what comes next.
    let opensLauncher: Bool

    var body: some View {
        WeatherConsentContent(
            onDecline: {
                AppCore.shared.answerWeatherConsent(granted: false, opensLauncher: opensLauncher)
            },
            onAccept: {
                AppCore.shared.answerWeatherConsent(granted: true, opensLauncher: opensLauncher)
            }
        )
        .frame(width: Self.windowSize.width)
    }
}
