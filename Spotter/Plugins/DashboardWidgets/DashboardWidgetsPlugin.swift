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
            defaultEnabled: true,
            canDisable: false,
            exportsEnabledState: false,
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
            readEnabled: { true },
            settingsView: {
                AnyView(
                    DashboardWidgetsSettingsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        music: core.dashboardMusic, battery: core.dashboardDeviceBattery))
            })
    }
}

extension AppCore {
    /// Read once per summon, from `showPalette`, so the File Info card is current without anything
    /// watching the Finder between summons.
    func refreshDashboardFileInfo() {
        dashboardFileInfo.refresh(frontmost: previousApplication)
    }
}
