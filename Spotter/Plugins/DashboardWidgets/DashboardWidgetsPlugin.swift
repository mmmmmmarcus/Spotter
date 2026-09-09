import SwiftUI

@MainActor
enum DashboardWidgetsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .dashboardWidgets,
                name: "Widgets",
                summary:
                    "See the time, weather, the music playing, device batteries, next event "
                    + "and the Finder selection above launcher results.",
                systemImage: "rectangle.3.group",
                tint: .purple,
                settingsPlacement: .system),
            // Automation covers both cards that ask another app a question: File Info asking
            // the Finder what is selected, and Music asking Music what is playing.
            permissions: [.calendar, .automation],
            launcherDashboard: PluginLauncherDashboardRegistration {
                AnyView(
                    DashboardWidgetsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        music: core.dashboardMusic, battery: core.dashboardDeviceBattery,
                        fileInfo: core.dashboardFileInfo))
            },
            settingsView: {
                AnyView(
                    DashboardWidgetsSettingsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        music: core.dashboardMusic))
            })
    }
}

extension AppCore {
    private static let weatherConsentWindowID = "weather-consent"

    /// Raises the one weather question, for someone who has never answered it. Returns whether it
    /// was actually put on screen, so the caller can hold back whatever would sit on top of it.
    @discardableResult
    func presentWeatherConsentIfNeeded(thenShowLauncher: Bool = false) -> Bool {
        guard dashboardWeather.needsConsentPrompt else { return false }
        showPluginWindow(
            id: Self.weatherConsentWindowID, title: "Weather",
            size: WeatherConsentWindow.windowSize
        ) {
            WeatherConsentWindow(opensLauncher: thenShowLauncher)
        }
        return true
    }

    /// Both answers land here. A decline is recorded as an answer, so the question is never asked
    /// again; a grant is permanent, since weather has no off switch.
    func answerWeatherConsent(granted: Bool, opensLauncher: Bool) {
        dashboardWeather.recordConsent(granted: granted)
        closePluginWindow(id: Self.weatherConsentWindowID)
        if opensLauncher { showPalette(mode: .launcher) }
    }

    /// Read once per summon, from `showPalette`, so the File Info card is current without anything
    /// watching the Finder between summons.
    func refreshDashboardFileInfo() {
        dashboardFileInfo.refresh(frontmost: previousApplication)
    }
}
