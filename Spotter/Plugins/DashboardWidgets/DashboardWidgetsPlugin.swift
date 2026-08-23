import SwiftUI

@MainActor
enum DashboardWidgetsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .dashboardWidgets,
                name: "Widgets",
                summary:
                    "See the time, weather, uptime, device batteries, next event and the Finder "
                    + "selection above launcher results.",
                systemImage: "rectangle.3.group",
                tint: .purple,
                settingsPlacement: .system),
            defaultEnabled: true,
            canDisable: false,
            exportsEnabledState: false,
            // Accessibility belongs to the uptime card's key counting; clicks need no grant.
            // Automation is the File Info card asking the Finder what is selected.
            permissions: [.calendar, .accessibility, .automation],
            launcherDashboard: PluginLauncherDashboardRegistration {
                AnyView(
                    DashboardWidgetsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        uptime: core.dashboardUptime, battery: core.dashboardDeviceBattery,
                        fileInfo: core.dashboardFileInfo))
            },
            readEnabled: { true },
            settingsView: {
                AnyView(
                    DashboardWidgetsSettingsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        uptime: core.dashboardUptime, battery: core.dashboardDeviceBattery))
            })
    }
}

extension AppCore {
    /// Read once per summon, from `showPalette`, so the File Info card is current without anything
    /// watching the Finder between summons.
    func refreshDashboardFileInfo() {
        guard dashboardWidgets.isWidgetEnabled(.fileInfo) else {
            dashboardFileInfo.clear()
            return
        }
        dashboardFileInfo.refresh(frontmost: previousApplication)
    }
}
