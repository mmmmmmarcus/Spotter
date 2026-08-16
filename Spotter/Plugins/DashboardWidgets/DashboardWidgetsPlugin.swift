import SwiftUI

@MainActor
enum DashboardWidgetsPlugin {
    static func registration(core: AppCore) -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .dashboardWidgets,
                name: "Widgets",
                summary:
                    "See the time, weather, uptime, device batteries and next event above launcher "
                    + "results.",
                systemImage: "rectangle.3.group",
                tint: .purple,
                settingsPlacement: .widgets),
            defaultEnabled: true,
            canDisable: false,
            exportsEnabledState: false,
            // Accessibility belongs to the uptime card's key counting; clicks need no grant.
            permissions: [.calendar, .accessibility],
            launcherDashboard: PluginLauncherDashboardRegistration {
                AnyView(
                    DashboardWidgetsView(
                        store: core.dashboardWidgets, weather: core.dashboardWeather,
                        uptime: core.dashboardUptime, battery: core.dashboardDeviceBattery))
            },
            // One Settings row per card, in the order the strip draws them.
            widgets: [
                PluginWidgetRegistration(
                    id: "clock", name: "Clock", systemImage: "clock", tint: .orange,
                    settingsView: { AnyView(ClockWidgetSettingsView(store: core.dashboardWidgets)) }),
                PluginWidgetRegistration(
                    id: "weather", name: "Weather", systemImage: "cloud.sun", tint: .cyan,
                    settingsView: {
                        AnyView(WeatherWidgetSettingsView(weather: core.dashboardWeather))
                    }),
                PluginWidgetRegistration(
                    id: "uptime", name: "Uptime", systemImage: "timer", tint: .green,
                    settingsView: { AnyView(UptimeWidgetSettingsView(uptime: core.dashboardUptime)) }),
                PluginWidgetRegistration(
                    id: "device-battery", name: "Device Battery",
                    systemImage: "battery.100percent", tint: .yellow,
                    settingsView: {
                        AnyView(
                            DeviceBatteryWidgetSettingsView(
                                store: core.dashboardWidgets, battery: core.dashboardDeviceBattery))
                    }),
                PluginWidgetRegistration(
                    id: "calendar", name: "Calendar", systemImage: "calendar", tint: .blue,
                    settingsView: {
                        AnyView(CalendarWidgetSettingsView(store: core.dashboardWidgets))
                    }),
            ],
            readEnabled: { true })
    }
}
