import SwiftUI

/// One page for the whole strip: a section per card that has something to decide. There is
/// deliberately no arrangement pane and no per-card pane — order is set by dragging the cards in the
/// palette itself, which is the thing being arranged. Device Battery and File Info have no section
/// at all: they are text-only cards with nothing to configure (owner decision, Sep 2026).
struct DashboardWidgetsSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    @ObservedObject var music: DashboardMusicStore

    @State private var askingWeatherConsent = false
    @State private var citySearch = ""
    @State private var refreshing = false
    @State private var refreshFailed = false

    private static let timeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        SettingsPane(
            title: "Widgets",
            subtitle:
                "The cards above launcher results while the search is empty. Drag a card in the "
                + "palette to move it along the row."
        ) {
            clockAndWeatherCard
            musicCard
            calendarCard
        }
        .sheet(isPresented: $askingWeatherConsent) {
            WeatherConsentSheet(
                onCancel: { askingWeatherConsent = false },
                onAccept: {
                    askingWeatherConsent = false
                    weather.setEnabled(true)
                })
        }
    }

    /// The clock and the weather complications are one face, so they are one section on one
    /// location. Weather still has no switch of its own: choosing a city is what turns it on, and
    /// that button is what raises the consent dialog, so setting a location never contacts anything
    /// by itself — the offline time-zone picker is the only location control until consent is given.
    private var clockAndWeatherCard: some View {
        SettingsCard(header: "Clock & Weather") {
            SettingsRow(
                title: "Location",
                subtitle: locationStatus,
                systemImage: "mappin.and.ellipse", tint: .orange
            ) {
                if weather.isEnabled {
                    Button("Turn Off Weather") { weather.setEnabled(false) }
                        .controlSize(.small)
                } else {
                    Button("Choose City…") { askingWeatherConsent = true }
                        .controlSize(.small)
                }
            }

            // The clock keeps its own picker until a chosen city names the zone it is already set
            // to: a city saved before the two shared a location names none, and hiding the picker
            // then would strand a setting nothing else can reach.
            if !clockFollowsCity {
                SettingsDivider()
                SettingsRow(
                    title: "Time Zone",
                    subtitle:
                        "System Default follows changes made in macOS Settings. Choosing a city "
                        + "sets this to that city's own zone.",
                    systemImage: "globe", tint: .orange
                ) {
                    Picker("", selection: clockTimeZoneBinding) {
                        Text("System Default (\(TimeZone.autoupdatingCurrent.identifier))")
                            .tag("")
                        ForEach(Self.timeZoneIdentifiers, id: \.self) { identifier in
                            Text(DashboardWidgetsEngine.readableTimeZone(identifier))
                                .tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
            }

            if weather.isEnabled {
                SettingsDivider()
                SettingsRow(
                    title: "Change City",
                    subtitle:
                        "The clock keeps this city's time and shows its temperature, today's range "
                        + "and condition.",
                    systemImage: "magnifyingglass", tint: .cyan
                ) {
                    HStack(spacing: Theme.Spacing.sm) {
                        if weather.isSearching { ProgressView().controlSize(.small) }
                        TextField("Search a city", text: $citySearch)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: citySearch) { _, query in weather.search(query) }
                    }
                }

                // Results replace the list in place; picking one clears the field so it settles back.
                ForEach(weather.searchResults) { result in
                    SettingsDivider()
                    SettingsRow(
                        title: result.name,
                        subtitle: result.detailLabel.isEmpty ? nil : result.detailLabel,
                        systemImage: "location", tint: .secondary
                    ) {
                        // Whole-record, not id: a city saved before it carried a zone must stay
                        // choosable, since re-picking it is what hands the clock that zone.
                        Button(weather.city == result ? "Selected" : "Choose") {
                            chooseCity(result)
                        }
                        .controlSize(.small)
                        .disabled(weather.city == result)
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "Units",
                    subtitle: "Readings are downloaded in Celsius and converted on this Mac.",
                    systemImage: "thermometer.medium", tint: .cyan
                ) {
                    Picker("", selection: unitBinding) {
                        ForEach(WeatherUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }

                SettingsDivider()
                SettingsRow(
                    title: "Conditions",
                    subtitle: readingStatus,
                    systemImage: "arrow.clockwise", tint: .secondary
                ) {
                    Button("Update Now") {
                        refreshing = true
                        Task {
                            let landed = await weather.refreshNow()
                            refreshFailed = !landed
                            refreshing = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(refreshing)
                }
            }
        }
    }

    /// One act, both halves: the city is the weather's place and its own zone is the clock's, which
    /// is what makes this one location rather than two kept in step by hand. Both writes are local —
    /// whether anything is fetched stays the weather store's own `isEnabled` decision.
    private func chooseCity(_ city: WeatherCity) {
        weather.setCity(city)
        if let identifier = DashboardWeatherEngine.clockTimeZoneIdentifier(for: city) {
            store.setClockTimeZoneIdentifier(identifier)
        }
        citySearch = ""
        weather.clearSearch()
    }

    private var musicCard: some View {
        SettingsCard(header: "Music") {
            SettingsRow(
                title: "Apple Music",
                subtitle: music.snapshot.track.map {
                    "\($0.title) — \(DashboardMusicEngine.subtitle(for: $0))"
                } ?? DashboardMusicEngine.restingLine(isRunning: music.snapshot.isRunning),
                systemImage: "music.note", tint: .pink
            ) {
                Label(
                    music.snapshot.isPlaying ? "Playing" : "Idle",
                    systemImage: music.snapshot.isPlaying ? "speaker.wave.2.fill" : "pause.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(music.snapshot.isPlaying ? .pink : .secondary)
            }

            SettingsDivider()
            SettingsRow(
                title: "Automation Permission",
                subtitle:
                    "The card asks Music what is playing through one Apple Event. macOS asks for "
                    + "Automation access the first time; Music is never launched by Spotter.",
                systemImage: "lock.shield", tint: .secondary
            ) { EmptyView() }
        }
    }

    /// The card's real preferences moved to the Calendar plugin, which shares the same store —
    /// this stub says where they went rather than duplicating them.
    private var calendarCard: some View {
        SettingsCard(header: "Calendar") {
            SettingsRow(
                title: "Calendar",
                subtitle:
                    "The card shows the next event. Its account, access and all-day settings live "
                    + "with the Calendar plugin, which shares them.",
                systemImage: "calendar", tint: .red
            ) {
                Button("Open Calendar Settings") {
                    AppCore.shared.showSettings(plugin: .calendarSchedule)
                }
                .controlSize(.small)
            }
        }
    }

    /// The clock's own picker stays on screen until a chosen city is what the clock is set to.
    private var clockFollowsCity: Bool {
        weather.isEnabled
            && DashboardWidgetsEngine.clockFollowsCity(
                cityTimeZoneIdentifier: DashboardWeatherEngine.clockTimeZoneIdentifier(
                    for: weather.city),
                clockTimeZoneIdentifier: store.preferences.clockTimeZoneIdentifier)
    }

    private var locationStatus: String {
        let summary = DashboardWidgetsEngine.locationSummary(
            cityLabel: weather.isEnabled ? cityLabel : nil,
            cityTimeZoneIdentifier: DashboardWeatherEngine.clockTimeZoneIdentifier(
                for: weather.city),
            clockTimeZoneIdentifier: store.preferences.clockTimeZoneIdentifier,
            systemTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier)
        guard weather.isEnabled else {
            return summary + " · no service is contacted until you choose a city."
        }
        return summary
    }

    private var cityLabel: String {
        let detail = weather.city.detailLabel
        return detail.isEmpty ? weather.city.name : "\(weather.city.name), \(detail)"
    }

    private var readingStatus: String {
        if refreshing { return "Updating…" }
        if refreshFailed { return "Couldn't reach \(DashboardWeatherStore.provider). Try again." }
        guard let fetched = weather.reading?.fetchedAt else {
            return "\(DashboardWeatherStore.provider) · not downloaded yet."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "\(DashboardWeatherStore.provider) · updated \(stamp). Refreshes every 30 minutes."
    }

    private var unitBinding: Binding<WeatherUnit> {
        Binding(get: { weather.unit }, set: { weather.setUnit($0) })
    }

    private var clockTimeZoneBinding: Binding<String> {
        Binding(
            get: { store.preferences.clockTimeZoneIdentifier ?? "" },
            set: { store.setClockTimeZoneIdentifier($0) })
    }

}

private struct WeatherConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "network")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.cyan)
                Text("Show the weather on the clock?")
                    .font(.headline)
            }

            Text(
                "Spotter asks \(DashboardWeatherStore.provider) for the current conditions of the "
                    + "city you choose, every 30 minutes while Spotter is running, and keeps the "
                    + "latest reading on your Mac. Searching sends what you type in the city field. "
                    + "No account, no identifiers, and your Mac's location is never read. The city "
                    + "you pick also sets the clock's time zone, which nothing is contacted for. "
                    + "Turning it off deletes the cached reading and leaves the clock where it is."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: DashboardWeatherStore.providerURL) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(DashboardWeatherStore.providerURL.host() ?? "Provider")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.callout)
                }
                Spacer()
                Button("Not Now", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Enable", action: onAccept)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 420)
    }
}
