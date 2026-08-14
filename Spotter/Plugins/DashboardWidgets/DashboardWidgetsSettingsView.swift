import SwiftUI

struct DashboardWidgetsSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    private static let timeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    @State private var askingWeatherConsent = false
    @State private var citySearch = ""
    @State private var refreshingWeather = false
    @State private var weatherRefreshFailed = false

    var body: some View {
        SettingsPane(
            title: "Dashboard Widgets",
            subtitle: "At-a-glance information above launcher results when the search is empty."
        ) {
            SettingsCard(header: "Widgets") {
                SettingsRow(
                    title: "Clock",
                    subtitle: "An analog clock face in the selected time zone.",
                    systemImage: "clock", tint: .orange
                ) {
                    widgetToggle(.clock)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Weather",
                    subtitle: weatherStatus,
                    systemImage: "cloud.sun", tint: .cyan
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { weather.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingWeatherConsent = true
                                } else {
                                    weather.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                SettingsDivider()
                SettingsRow(
                    title: "Next Event",
                    subtitle: "The next event from the selected calendar account.",
                    systemImage: "calendar.badge.clock", tint: .blue
                ) {
                    widgetToggle(.nextEvent)
                }
            }

            if weather.isEnabled {
                weatherDetailsCard
            }

            SettingsCard(header: "Clock Details") {
                SettingsRow(
                    title: "Time Zone",
                    subtitle: "System Default follows changes made in macOS Settings.",
                    systemImage: "globe", tint: .orange
                ) {
                    Picker("", selection: clockTimeZoneBinding) {
                        Text("System Default (\(TimeZone.autoupdatingCurrent.identifier))")
                            .tag("")
                        ForEach(Self.timeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier.replacingOccurrences(of: "_", with: " "))
                                .tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }
            }

            SettingsCard(header: "Calendar Details") {
                SettingsRow(
                    title: "Calendar Access",
                    subtitle: calendarSubtitle,
                    systemImage: "lock.open", tint: .blue
                ) {
                    switch store.calendarAccess {
                    case .notDetermined, .writeOnly:
                        if store.isRequestingCalendarAccess {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Allow…") { store.requestCalendarAccess() }
                                .controlSize(.small)
                        }
                    case .denied:
                        Button("Open Settings…") { Permissions.openCalendarSettings() }
                            .controlSize(.small)
                    case .restricted:
                        Text("Restricted")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    case .fullAccess:
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }

                if store.calendarAccess == .fullAccess {
                    SettingsDivider()
                    SettingsRow(
                        title: "Account",
                        subtitle: "All Accounts includes every event calendar available to macOS.",
                        systemImage: "person.crop.circle", tint: .blue
                    ) {
                        Picker("", selection: calendarSourceBinding) {
                            Text("All Accounts").tag("")
                            ForEach(store.calendarAccounts) { account in
                                Text(account.title).tag(account.id)
                            }
                            if let selected = store.preferences.calendarSourceIdentifier,
                                !store.calendarAccounts.contains(where: { $0.id == selected })
                            {
                                Text("Unavailable Account").tag(selected)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }

                SettingsDivider()
                SettingsRow(
                    title: "All-Day Events",
                    subtitle: "Include all-day entries when choosing the next event.",
                    systemImage: "sun.max", tint: .blue
                ) {
                    Toggle("", isOn: includesAllDayEventsBinding)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }

        }
        .task { store.refresh() }
        .sheet(isPresented: $askingWeatherConsent) {
            WeatherConsentSheet(
                onCancel: { askingWeatherConsent = false },
                onAccept: {
                    askingWeatherConsent = false
                    weather.setEnabled(true)
                })
        }
    }

    private var weatherDetailsCard: some View {
        SettingsCard(header: "Weather Details") {
            SettingsRow(
                title: "City",
                subtitle: selectedCitySubtitle,
                systemImage: "mappin.and.ellipse", tint: .cyan
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    if weather.isSearching { ProgressView().controlSize(.small) }
                    TextField("Search a city", text: $citySearch)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                        .onChange(of: citySearch) { _, query in weather.search(query) }
                }
            }

            // Results replace the list in place; picking one clears the field so the card settles back.
            ForEach(weather.searchResults) { result in
                SettingsDivider()
                SettingsRow(
                    title: result.name, subtitle: result.detailLabel.isEmpty ? nil : result.detailLabel,
                    systemImage: "location", tint: .secondary
                ) {
                    Button(weather.city.id == result.id ? "Selected" : "Choose") {
                        weather.setCity(result)
                        citySearch = ""
                        weather.clearSearch()
                    }
                    .controlSize(.small)
                    .disabled(weather.city.id == result.id)
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
                subtitle: weatherReadingStatus,
                systemImage: "arrow.clockwise", tint: .secondary
            ) {
                Button("Update Now") {
                    refreshingWeather = true
                    Task {
                        let landed = await weather.refreshNow()
                        weatherRefreshFailed = !landed
                        refreshingWeather = false
                    }
                }
                .controlSize(.small)
                .disabled(refreshingWeather)
            }
        }
    }

    private var weatherStatus: String {
        let summary = "Current conditions for a city you choose."
        return weather.isEnabled ? summary : "\(summary) Off — no service is contacted."
    }

    private var selectedCitySubtitle: String {
        let city = weather.city
        let detail = city.detailLabel
        let place = detail.isEmpty ? city.name : "\(city.name), \(detail)"
        return city == .default ? "\(place) — the default until you choose another." : place
    }

    private var weatherReadingStatus: String {
        if refreshingWeather { return "Updating…" }
        if weatherRefreshFailed { return "Couldn't reach \(DashboardWeatherStore.provider). Try again." }
        guard let fetched = weather.reading?.fetchedAt else {
            return "\(DashboardWeatherStore.provider) · not downloaded yet."
        }
        let stamp = fetched.formatted(date: .abbreviated, time: .shortened)
        return "\(DashboardWeatherStore.provider) · updated \(stamp). Refreshes every 30 minutes."
    }

    private var unitBinding: Binding<WeatherUnit> {
        Binding(get: { weather.unit }, set: { weather.setUnit($0) })
    }

    private var calendarSubtitle: String {
        switch store.calendarAccess {
        case .notDetermined: return "Allow read access to show the next event."
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly: return "Write-only access cannot show events; grant full access to continue."
        case .fullAccess: return "Spotter can read upcoming events from your macOS calendars."
        }
    }

    private func widgetToggle(_ widget: DashboardWidgetKind) -> some View {
        Toggle("", isOn: widgetBinding(widget))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }

    private func widgetBinding(_ widget: DashboardWidgetKind) -> Binding<Bool> {
        Binding(
            get: { store.isWidgetEnabled(widget) },
            set: { store.setWidgetEnabled(widget, enabled: $0) })
    }

    private var calendarSourceBinding: Binding<String> {
        Binding(
            get: { store.preferences.calendarSourceIdentifier ?? "" },
            set: { store.setCalendarSourceIdentifier($0) })
    }

    private var includesAllDayEventsBinding: Binding<Bool> {
        Binding(
            get: { store.preferences.includesAllDayEvents },
            set: { store.setIncludesAllDayEvents($0) })
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
                Text("Turn on the weather widget?")
                    .font(.headline)
            }

            Text(
                "Spotter asks \(DashboardWeatherStore.provider) for the current conditions of the "
                    + "city you choose, every 30 minutes while Spotter is running, and keeps the "
                    + "latest reading on your Mac. Searching sends what you type in the city field. "
                    + "No account, no identifiers, and your Mac's location is never read. "
                    + "Turning it off deletes the cached reading."
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
