import SwiftUI

struct WorldClockSettingsView: View {
    @ObservedObject var store: WorldClockStore
    @State private var cityQuery = ""

    private var suggestions: [WorldClockCity] {
        guard !cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return Array(store.availableCities(matching: cityQuery).prefix(6))
    }

    var body: some View {
        SettingsPane(title: "World Clock") {
            Section("Cities") {
                if store.cities.isEmpty {
                    SettingsRow(title: "No Cities") { EmptyView() }
                } else {
                    ForEach(store.cities) { city in
                        SettingsRow(title: city.name, subtitle: city.timeZoneIdentifier) {
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

                SettingsRow(title: "Add City") {
                    TextField("London", text: $cityQuery)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 210)
                        .onSubmit(addFirstSuggestion)
                }

                ForEach(suggestions) { city in
                    SettingsRow(title: city.name, subtitle: city.timeZoneIdentifier) {
                        Button("Add") { add(city) }
                            .controlSize(.small)
                    }
                }

                if !store.usesDefaults {
                    SettingsRow(title: "Default Cities") {
                        Button("Restore") { store.restoreDefaults() }
                            .controlSize(.small)
                    }
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
