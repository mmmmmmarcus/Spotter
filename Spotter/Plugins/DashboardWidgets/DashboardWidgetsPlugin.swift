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
                settingsPlacement: .widgets),
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
            // Arrangement first — which cards show and in what order is settled in one place, so no
            // card's own pane carries a switch. The rest are the cards, in the order they draw.
            widgets: [
                PluginWidgetRegistration(
                    id: "arrangement", name: "Arrangement", systemImage: "square.grid.2x2",
                    tint: .purple,
                    settingsView: {
                        AnyView(
                            WidgetArrangementSettingsView(
                                store: core.dashboardWidgets, uptime: core.dashboardUptime))
                    }),
                PluginWidgetRegistration(
                    id: "clock", name: "Clock", systemImage: "clock", tint: .orange,
                    settingsView: {
                        AnyView(
                            ClockWidgetSettingsView(
                                store: core.dashboardWidgets, weather: core.dashboardWeather))
                    }),
                PluginWidgetRegistration(
                    id: "uptime", name: "Uptime", systemImage: "timer", tint: .green,
                    settingsView: { AnyView(UptimeWidgetSettingsView(uptime: core.dashboardUptime)) }),
                PluginWidgetRegistration(
                    id: "device-battery", name: "Device Battery",
                    systemImage: "battery.100percent", tint: .yellow,
                    settingsView: {
                        AnyView(DeviceBatteryWidgetSettingsView(battery: core.dashboardDeviceBattery))
                    }),
                PluginWidgetRegistration(
                    id: "calendar", name: "Calendar", systemImage: "calendar", tint: .blue,
                    settingsView: {
                        AnyView(CalendarWidgetSettingsView(store: core.dashboardWidgets))
                    }),
                PluginWidgetRegistration(
                    id: "file-info", name: "File Info", systemImage: "info.circle", tint: .teal,
                    settingsView: { AnyView(FileInfoWidgetSettingsView()) }),
            ],
            readEnabled: { true })
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
