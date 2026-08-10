import SwiftUI

@MainActor
enum DashboardWidgetsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .dashboardWidgets,
                name: "Dashboard Widgets",
                summary: "See the time, month, next event, and local AI usage above launcher results.",
                systemImage: "rectangle.3.group",
                tint: .purple),
            defaultEnabled: true,
            permissions: [.calendar],
            launcherDashboard: PluginLauncherDashboardRegistration {
                AnyView(DashboardWidgetsView(store: core.dashboardWidgets))
            },
            onDisable: { [weak core] in core?.dashboardWidgets.stop() },
            settingsView: {
                AnyView(DashboardWidgetsSettingsView(store: core.dashboardWidgets))
            })
    }
}
