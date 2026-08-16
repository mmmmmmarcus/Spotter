import SwiftUI

/// Each widget configures itself in its own pane under Settings → Widgets. There is deliberately no
/// combined pane: a single list of every widget's switches was the thing these replaced.
struct ClockWidgetSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    private static let timeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        SettingsPane(
            title: "Clock",
            subtitle: "An analog clock face above launcher results when the search is empty."
        ) {
            SettingsCard(header: "Widget") {
                SettingsRow(
                    title: "Show Clock",
                    subtitle: "A live analog face in the selected time zone.",
                    systemImage: "clock", tint: .orange
                ) {
                    widgetToggle(store: store, widget: .clock)
                }
                SettingsDivider()
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
        }
    }

    private var clockTimeZoneBinding: Binding<String> {
        Binding(
            get: { store.preferences.clockTimeZoneIdentifier ?? "" },
            set: { store.setClockTimeZoneIdentifier($0) })
    }
}

struct WeatherWidgetSettingsView: View {
    @ObservedObject var weather: DashboardWeatherStore

    @State private var askingConsent = false
    @State private var citySearch = ""
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(
            title: "Weather",
            subtitle: "Current conditions for a city you choose, above launcher results."
        ) {
            SettingsCard(header: "Widget") {
                SettingsRow(
                    title: "Show Weather",
                    subtitle: status,
                    systemImage: "cloud.sun", tint: .cyan
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { weather.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    weather.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if weather.isEnabled { detailsCard }
        }
        .sheet(isPresented: $askingConsent) {
            WeatherConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    weather.setEnabled(true)
                })
        }
    }

    private var detailsCard: some View {
        SettingsCard(header: "Details") {
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

    private var status: String {
        let summary = "Current conditions for a city you choose."
        return weather.isEnabled ? summary : "\(summary) Off — no service is contacted."
    }

    private var selectedCitySubtitle: String {
        let city = weather.city
        let detail = city.detailLabel
        let place = detail.isEmpty ? city.name : "\(city.name), \(detail)"
        return city == .default ? "\(place) — the default until you choose another." : place
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

struct UptimeWidgetSettingsView: View {
    @ObservedObject var uptime: DashboardUptimeStore

    @State private var askingConsent = false

    var body: some View {
        SettingsPane(
            title: "Uptime",
            subtitle: "How long today's session has run, with key and click counts."
        ) {
            SettingsCard(header: "Widget") {
                SettingsRow(
                    title: "Show Uptime",
                    subtitle: status,
                    systemImage: "timer", tint: .green
                ) {
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { uptime.isEnabled },
                            set: { wantsOn in
                                if wantsOn {
                                    askingConsent = true
                                } else {
                                    uptime.setEnabled(false)
                                }
                            })
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }

            if uptime.isEnabled {
                SettingsCard(header: "Details") {
                    SettingsRow(
                        title: "Keyboard Counting",
                        subtitle: uptime.needsAccessibility
                            ? "Clicks are counted. Counting keys needs the Accessibility permission."
                            : "Spotter counts that a key was pressed — never which one.",
                        systemImage: "keyboard", tint: .green
                    ) {
                        if uptime.needsAccessibility {
                            Button("Allow…") { Permissions.ensureAccessibility() }
                                .controlSize(.small)
                        } else {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }

                    SettingsDivider()
                    SettingsRow(
                        title: "Today's Counts",
                        subtitle: "Tallies clear on their own at midnight.",
                        systemImage: "arrow.counterclockwise", tint: .secondary
                    ) {
                        Button("Reset Today") { uptime.resetCounts() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .sheet(isPresented: $askingConsent) {
            UptimeConsentSheet(
                onCancel: { askingConsent = false },
                onAccept: {
                    askingConsent = false
                    uptime.setEnabled(true)
                })
        }
    }

    private var status: String {
        let summary = "Hours since the screen first came on today, with key and click counts."
        return uptime.isEnabled ? summary : "\(summary) Off — no input is counted."
    }
}

struct CalendarWidgetSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore

    var body: some View {
        SettingsPane(
            title: "Calendar",
            subtitle: "Today's date and the next event, above launcher results."
        ) {
            SettingsCard(header: "Widget") {
                SettingsRow(
                    title: "Show Calendar",
                    subtitle: "Today's date, over the next event from the selected account.",
                    systemImage: "calendar", tint: .blue
                ) {
                    widgetToggle(store: store, widget: .nextEvent)
                }
            }

            SettingsCard(header: "Details") {
                SettingsRow(
                    title: "Calendar Access",
                    subtitle: accessSubtitle,
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
    }

    private var accessSubtitle: String {
        switch store.calendarAccess {
        case .notDetermined: return "Allow read access to show the next event."
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly: return "Write-only access cannot show events; grant full access to continue."
        case .fullAccess: return "Spotter can read upcoming events from your macOS calendars."
        }
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
}

private func widgetToggle(store: DashboardWidgetsStore, widget: DashboardWidgetKind) -> some View {
    Toggle(
        "",
        isOn: Binding(
            get: { store.isWidgetEnabled(widget) },
            set: { store.setWidgetEnabled(widget, enabled: $0) })
    )
    .labelsHidden()
    .toggleStyle(.switch)
    .controlSize(.small)
}

/// Nothing here reaches the network, but a system-wide input counter is asked for as plainly as one
/// that does — the user should turn this on knowing exactly what is and isn't recorded.
private struct UptimeConsentSheet: View {
    let onCancel: () -> Void
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "timer")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.green)
                Text("Turn on the uptime widget?")
                    .font(.headline)
            }

            Text(
                "Spotter counts how many keys you press and how many times you click, everywhere on "
                    + "this Mac, and shows the totals next to how long the screen has been on today. "
                    + "It records only that a key was pressed — never which key, what you typed, or "
                    + "where you clicked. The totals stay on this Mac, clear at midnight, and are "
                    + "deleted when you turn this off. Counting keys needs the Accessibility "
                    + "permission; clicks are counted without it."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
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
