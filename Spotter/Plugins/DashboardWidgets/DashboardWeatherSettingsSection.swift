import SwiftUI

struct DashboardWeatherSettingsSection: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore

    @State private var askingWeatherConsent = false
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        weatherSection
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

    private var weatherSection: some View {
        Section("Weather") {
            if weather.isEnabled {
                SettingsRow(
                    title: "Location", subtitle: locationStatus + "\n" + readingStatus,
                    statusDot: locationStatusDot, containsMultipleControls: true
                ) {
                    locationAction
                    Button(refreshing ? "Updating…" : "Update Now") {
                        refreshing = true
                        Task {
                            let landed = await weather.refreshNow()
                            refreshFailed = !landed
                            refreshing = false
                        }
                    }
                    .controlSize(.small)
                    .disabled(refreshing || !DashboardWeatherEngine.isLocated(weather.locationState))
                }

                SettingsRow(title: "Units") {
                    Picker("Units", selection: unitBinding) {
                        ForEach(WeatherUnit.allCases, id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                }
            } else {
                // A previous decline keeps weather off until the user accepts the same consent prompt.
                SettingsRow(title: "Weather", subtitle: locationStatus) {
                    Button("Turn On Weather…") { askingWeatherConsent = true }
                        .controlSize(.small)
                }
            }
        }
    }

    // Only an actionable location failure offers the system settings shortcut.
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
