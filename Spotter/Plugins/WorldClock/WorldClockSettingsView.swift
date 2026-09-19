import SwiftUI

struct WorldClockSettingsView: View {
    @ObservedObject var store: WorldClockStore
    @State private var showsCityPicker = false

    var body: some View {
        SettingsPane(title: "World Clock") {
            Section {
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
            } header: {
                Text("Cities")
            } footer: {
                SettingsListActions {
                    if !store.usesDefaults {
                        Button("Restore Defaults") { store.restoreDefaults() }
                            .controlSize(.small)
                    }
                    Button("Add City…") { showsCityPicker = true }
                        .controlSize(.small)
                        .popover(isPresented: $showsCityPicker, arrowEdge: .bottom) {
                            WorldClockCityPicker(store: store) { showsCityPicker = false }
                        }
                }
            }
        }
    }
}

private struct WorldClockCityPicker: View {
    @ObservedObject var store: WorldClockStore
    let dismiss: () -> Void
    @State private var query = ""
    @State private var hoveredID: String?
    @FocusState private var searchFocused: Bool

    private var candidates: [WorldClockCity] { store.availableCities(matching: query) }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search cities…", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search cities")
                .focused($searchFocused)
                .onSubmit {
                    if let city = candidates.first { add(city) }
                }
                .padding(Theme.Spacing.md)
            Divider()
            if candidates.isEmpty {
                ContentUnavailableView.search(text: query)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xxs) {
                        ForEach(candidates) { city in
                            Button { add(city) } label: {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                    Text(city.name).font(.body).foregroundStyle(.primary)
                                    Text(city.timeZoneIdentifier).font(.caption).foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Theme.Spacing.md)
                                .background(hoveredID == city.id ? Theme.Colors.rowHover : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.row))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Add \(city.name)")
                            .accessibilityLabel("Add \(city.name), \(city.timeZoneIdentifier)")
                            .onHover { hovering in hoveredID = hovering ? city.id : nil }
                        }
                    }
                    .padding(Theme.Spacing.sm)
                }
                .overlayScroller()
            }
        }
        .frame(width: Theme.Size.worldClockCityPickerWidth, height: Theme.Size.worldClockCityPickerHeight)
        .task { searchFocused = true }
        .onExitCommand(perform: dismiss)
    }

    private func add(_ city: WorldClockCity) {
        store.add(city)
        dismiss()
    }
}
