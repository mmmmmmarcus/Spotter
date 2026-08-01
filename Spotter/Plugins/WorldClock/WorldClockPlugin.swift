import SwiftUI

@MainActor
enum WorldClockPlugin {
    static func registration() -> PluginRegistration {
        PluginRegistration(
            metadata: PluginMetadata(
                id: .worldClock,
                name: "World Clock",
                summary: "Show the current time in cities around the world.",
                systemImage: "globe.americas",
                tint: .blue),
            defaultEnabled: true,
            queryProvider: WorldClockQueryProvider(),
            settingsView: { AnyView(WorldClockSettingsView()) })
    }
}
