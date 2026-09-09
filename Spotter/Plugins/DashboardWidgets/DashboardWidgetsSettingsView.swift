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
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(title: "Widgets") {
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

    /// The pane's opening section carries no header — a pane's first group is not named. The clock
    /// and the weather complications are one face on one place, and that place is this Mac's own:
    /// there is nothing to pick, so the row reports where the reading is taken and what the clock is
    /// running on. Until the question is answered the row offers the question instead, and the clock
    /// runs on whatever zone it already had — nothing is contacted to keep the time.
    private var clockAndWeatherCard: some View {
        Section {
            if weather.isEnabled {
                SettingsRow(
                    title: "Location", subtitle: locationStatus, statusDot: locationStatusDot
                ) {
                    locationAction
                }

                SettingsRow(title: "Units") {
                    // No width of its own: the row's own trailing alignment is what places it, the
                    // way every other control in a grouped `Form` row is placed.
                    Picker("Units", selection: unitBinding) {
                        ForEach(WeatherUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                }

                SettingsRow(title: "Conditions", subtitle: readingStatus) {
                    Button("Update Now") {
                        refreshing = true
                        Task {
                            let landed = await weather.refreshNow()
                            refreshFailed = !landed
                            refreshing = false
                        }
                    }
                    .controlSize(.small)
                    // Nothing to update without a place: the Location row above states why, and a
                    // button that could only fail is worse than one that is plainly unavailable.
                    .disabled(
                        refreshing || !DashboardWeatherEngine.isLocated(weather.locationState))
                }
            } else {
                // Consent is asked once at first launch; this is the way back for someone who
                // declined it, and the only thing that can ever turn weather on.
                SettingsRow(title: "Weather", subtitle: locationStatus) {
                    Button("Turn On Weather…") { askingWeatherConsent = true }
                        .controlSize(.small)
                }
            }
        }
    }

    /// A failure the user can act on gets the way to act on it; a policy-restricted Mac gets the
    /// sentence alone, since there is nothing there for it to open.
    @ViewBuilder
    private var locationAction: some View {
        if DashboardWeatherEngine.opensLocationSettings(for: weather.locationState) {
            Button("Open Location Settings") { Permissions.openLocationSettings() }
                .controlSize(.small)
        } else if case .restricted = weather.locationState {
            Text("Restricted")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var musicCard: some View {
        Section("Music") {
            SettingsRow(
                title: "Apple Music",
                subtitle: music.snapshot.track.map {
                    "\($0.title) — \(DashboardMusicEngine.subtitle(for: $0))"
                } ?? DashboardMusicEngine.restingLine(isRunning: music.snapshot.isRunning)
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
        Section("Calendar") {
            SettingsRow(title: "Calendar") {
                Button("Open Calendar Settings") {
                    AppCore.shared.showSettings(plugin: .calendarSchedule)
                }
                .controlSize(.small)
            }
        }
    }

    private var locationStatus: String {
        guard weather.isEnabled else {
            return DashboardWidgetsEngine.clockSummary(
                clockTimeZoneIdentifier: store.preferences.clockTimeZoneIdentifier,
                systemTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier)
                + " · the clock keeps time offline; no service is contacted."
        }
        return DashboardWeatherEngine.locationSummary(
            state: weather.locationState,
            clockTimeZoneIdentifier: store.preferences.clockTimeZoneIdentifier,
            systemTimeZoneIdentifier: TimeZone.autoupdatingCurrent.identifier)
    }

    /// Green once a fix is in, orange for every state that has no weather to show — the row's own
    /// sentence says which.
    private var locationStatusDot: Color? {
        guard weather.isEnabled else { return nil }
        switch weather.locationState {
        case .located: return .green
        case .waiting: return nil
        case .denied, .restricted, .unavailable: return .orange
        }
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
