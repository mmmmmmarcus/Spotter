import SwiftUI

struct WorldClockSettingsView: View {
    @EnvironmentObject private var plugins: PluginRegistry
    @ObservedObject var store: WorldClockStore
    @State private var cityQuery = ""

    private var suggestions: [WorldClockCity] {
        guard !cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return Array(store.availableCities(matching: cityQuery).prefix(6))
    }

    var body: some View {
        SettingsPane(
            title: "World Clock",
            subtitle: "Compare local time and keep your important cities in the launcher."
        ) {
            SettingsCard(header: "Plugin") {
                SettingsRow(
                    title: "World Clock",
                    subtitle: "Uses the time-zone data built into macOS. No network access.",
                    systemImage: "globe.americas",
                    tint: .blue,
                    statusDot: plugins.isEnabled(.worldClock) ? .green : nil
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { plugins.isEnabled(.worldClock) },
                            set: { plugins.setEnabled($0, for: .worldClock) })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            SettingsCard(header: "Cities") {
                if store.cities.isEmpty {
                    SettingsRow(
                        title: "No Cities",
                        subtitle: "Search below to add a city to the World Clock palette.",
                        systemImage: "globe", tint: .blue
                    ) { EmptyView() }
                } else {
                    ForEach(Array(store.cities.enumerated()), id: \.element.id) { index, city in
                        if index > 0 { SettingsDivider() }
                        SettingsRow(
                            title: city.name,
                            subtitle: city.timeZoneIdentifier,
                            systemImage: "clock", tint: .blue
                        ) {
                            Button {
                                store.remove(id: city.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove \(city.name)")
                        }
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Add City",
                    subtitle: "Search the IANA time-zone cities built into macOS.",
                    systemImage: "plus.circle", tint: .blue
                ) {
                    TextField("London", text: $cityQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                        .onSubmit(addFirstSuggestion)
                }

                ForEach(suggestions) { city in
                    SettingsDivider()
                    SettingsRow(
                        title: city.name,
                        subtitle: city.timeZoneIdentifier,
                        systemImage: "mappin.and.ellipse", tint: .blue
                    ) {
                        Button("Add") { add(city) }
                            .controlSize(.small)
                    }
                }

                if !store.usesDefaults {
                    SettingsDivider()
                    SettingsRow(
                        title: "Default Cities",
                        subtitle: "London, Shanghai, and San Francisco.",
                        systemImage: "arrow.counterclockwise", tint: .blue
                    ) {
                        Button("Restore") { store.restoreDefaults() }
                            .controlSize(.small)
                    }
                }
            }

            SettingsCard(header: "Query") {
                SettingsRow(
                    title: "time in London",
                    subtitle: "The result compares London with local system time; ↑/↓ adjusts one hour.",
                    systemImage: "text.magnifyingglass",
                    tint: .blue
                ) { EmptyView() }
            }

            SettingsCard(header: "Shortcut") {
                SettingsRow(
                    title: "World Clock",
                    subtitle: "Open your saved cities in the Spotter palette.",
                    systemImage: "keyboard", tint: .blue
                ) {
                    ShortcutRecorder(action: .plugin(.openWorldClock))
                }
            }
        }
    }

    private func addFirstSuggestion() {
        guard let city = suggestions.first else { return }
        add(city)
    }

    private func add(_ city: WorldClockCity) {
        store.add(city)
        cityQuery = ""
    }
}
