import SwiftUI

@MainActor
enum DashboardWidgetsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .dashboardWidgets,
                name: "Dashboard Widgets",
                summary: "See the time, weather, uptime and next event above launcher results.",
                systemImage: "rectangle.3.group",
                tint: .purple,
                settingsPlacement: .system),
            defaultEnabled: true,
            canDisable: false,
            exportsEnabledState: false,
            // Accessibility belongs to the uptime card's key counting; clicks need no grant.
            permissions: [.calendar, .accessibility],
            launcherDashboard: PluginLauncherDashboardRegistration {
                AnyView(
                    DashboardWidgetsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        uptime: core.dashboardUptime))
            },
            readEnabled: { true },
            settingsView: {
                AnyView(
                    DashboardWidgetsSettingsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        uptime: core.dashboardUptime))
            })
    }
}
