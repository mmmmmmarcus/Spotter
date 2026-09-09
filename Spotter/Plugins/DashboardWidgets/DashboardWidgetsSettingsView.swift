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
            WeatherConsentContent(
                onDecline: {
                    askingWeatherConsent = false
                    weather.recordConsent(granted: false)
                },
                onAccept: {
                    askingWeatherConsent = false
                    weather.recordConsent(granted: true)
                }
            )
            .frame(width: 460)
        }
    }

    /// The clock and the weather complications are one face on one place, so choosing a city is the
    /// only location control there is: it sets where the weather is read and hands the clock that
    /// city's own zone. Until the question is answered the row offers the question instead, and the
    /// clock runs on whatever zone it already had — nothing is contacted to keep the time.
    private var clockAndWeatherCard: some View {
        SettingsCard(header: "Clock & Weather") {
            SettingsRow(
                title: "Location",
                subtitle: locationStatus,
                systemImage: "mappin.and.ellipse", tint: .orange
            ) {
                if weather.isEnabled {
                    HStack(spacing: Theme.Spacing.sm) {
                        if weather.isSearching { ProgressView().controlSize(.small) }
                        TextField("Search a city", text: $citySearch)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: citySearch) { _, query in weather.search(query) }
                    }
                } else {
                    // Consent is asked once at first launch; this is the way back for someone who
                    // declined it, and the only thing that can ever turn weather on.
                    Button("Turn On Weather…") { askingWeatherConsent = true }
                        .controlSize(.small)
                }
            }

            if weather.isEnabled {
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

    private var locationStatus: String {
        let summary = DashboardWidgetsEngine.locationSummary(
            cityLabel: weather.isEnabled ? cityLabel : nil,
            cityTimeZoneIdentifier: DashboardWeatherEngine.clockTimeZoneIdentifier(
                for: weather.city),
            clockTimeZoneIdentifier: store.preferences.clockTimeZoneIdentifier,
            systemTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier)
        guard weather.isEnabled else {
            return summary + " · the clock keeps time offline; no service is contacted."
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
}
