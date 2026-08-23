import SwiftUI

/// One page for the whole strip: which cards show, then a section per card. There is deliberately no
/// arrangement pane and no per-card pane — order is set by dragging the cards in the palette itself,
/// which is the thing being arranged, and five panes for five cards was four more places to look.
struct DashboardWidgetsSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    @ObservedObject var uptime: DashboardUptimeStore
    @ObservedObject var battery: DashboardDeviceBatteryStore

    @State private var askingUptimeConsent = false
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
            showCard
            clockCard
            weatherCard
            if weather.isEnabled { weatherDetailsCard }
            if uptime.isEnabled { uptimeCard }
            batteryCard
            calendarCard
            fileInfoCard
        }
        .sheet(isPresented: $askingUptimeConsent) {
            UptimeConsentSheet(
                onCancel: { askingUptimeConsent = false },
                onAccept: {
                    askingUptimeConsent = false
                    uptime.setEnabled(true)
                })
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

    /// The one place a card is switched on or off. Order isn't here: the strip is draggable, and a
    /// list of names is a worse way to arrange something you can see.
    private var showCard: some View {
        SettingsCard(header: "Show") {
            ForEach(Array(store.orderedWidgets.enumerated()), id: \.element) { index, kind in
                if index > 0 { SettingsDivider() }
                SettingsRow(
                    title: kind.title, subtitle: kind.summary, systemImage: kind.systemImage,
                    tint: tint(kind)
                ) {
                    Toggle("", isOn: enabled(kind))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
        }
    }

    private var clockCard: some View {
        SettingsCard(header: "Clock") {
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

    /// Weather has no switch of its own: it is three complications on the clock face, and choosing a
    /// city is what turns it on. That keeps one control instead of two while leaving the network
    /// consent explicit — the dialog still names the provider, the cadence and what leaves the Mac
    /// before anything is contacted, and removing the city is how it goes off again.
    private var weatherCard: some View {
        SettingsCard(header: "Weather") {
            SettingsRow(
                title: "City",
                subtitle: cityStatus,
                systemImage: "mappin.and.ellipse", tint: .cyan
            ) {
                if weather.isEnabled {
                    Button("Turn Off") { weather.setEnabled(false) }
                        .controlSize(.small)
                } else {
                    Button("Choose City…") { askingWeatherConsent = true }
                        .controlSize(.small)
                }
            }
        }
    }

    private var weatherDetailsCard: some View {
        SettingsCard(header: "Weather Details") {
            SettingsRow(
                title: "Change City",
                subtitle: "The clock shows this city's temperature, today's range and condition.",
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

            // Results replace the list in place; picking one clears the field so the card settles back.
            ForEach(weather.searchResults) { result in
                SettingsDivider()
                SettingsRow(
                    title: result.name,
                    subtitle: result.detailLabel.isEmpty ? nil : result.detailLabel,
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

    private var uptimeCard: some View {
        SettingsCard(header: "Uptime") {
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

    /// A read-out rather than a setting: what was found and at what level, so a Mac showing empty
    /// rings says why.
    private var batteryCard: some View {
        SettingsCard(header: "Device Battery") {
            if battery.devices.isEmpty {
                SettingsRow(
                    title: "No Devices",
                    subtitle:
                        "Nothing connected reports a battery level, so the card stays hidden. "
                        + "Built-in keyboards and trackpads have none, and AirPods report theirs "
                        + "somewhere Spotter doesn't read.",
                    systemImage: "questionmark.circle", tint: .secondary
                ) {
                    EmptyView()
                }
            } else {
                ForEach(Array(battery.devices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(
                        title: DashboardDeviceBatteryEngine.label(for: device),
                        subtitle: device.productName.isEmpty ? nil : device.productName,
                        systemImage: device.kind.systemImage, tint: .yellow
                    ) {
                        Text(DashboardDeviceBatteryEngine.percentLabel(device.percent))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(
                                DashboardDeviceBatteryEngine.isLow(device.percent)
                                    ? Color.red : .secondary)
                    }
                }
            }
        }
        .task { battery.refresh() }
    }

    private var calendarCard: some View {
        SettingsCard(header: "Calendar") {
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
        .task { store.refresh() }
    }

    private var fileInfoCard: some View {
        SettingsCard(header: "File Info") {
            SettingsRow(
                title: "Only From the Finder",
                subtitle:
                    "Spotter asks the Finder what is selected, and only when the Finder is the app "
                    + "you summoned the launcher from. macOS asks for Automation access the first "
                    + "time.",
                systemImage: "folder", tint: .teal
            ) { EmptyView() }
            SettingsDivider()
            SettingsRow(
                title: "Nothing Is Opened or Stored",
                subtitle:
                    "Only the name, kind and size are read. File contents are never opened, and "
                    + "nothing about the selection is saved or sent anywhere.",
                systemImage: "lock", tint: .teal
            ) { EmptyView() }
            SettingsDivider()
            SettingsRow(
                title: "Folders Are Counted, Not Weighed",
                subtitle:
                    "A folder shows how many items it holds. A package such as an app shows its "
                    + "total size, since it is one item to you.",
                systemImage: "shippingbox", tint: .teal
            ) { EmptyView() }
        }
    }

    private func isEnabled(_ kind: DashboardWidgetKind) -> Bool {
        kind.ownsEnabledState ? store.isWidgetEnabled(kind) : uptime.isEnabled
    }

    private func enabled(_ kind: DashboardWidgetKind) -> Binding<Bool> {
        Binding(
            get: { isEnabled(kind) },
            set: { wantsOn in
                guard kind.ownsEnabledState else {
                    // Uptime's switch is a consent act, so switching it on asks before anything counts.
                    if wantsOn {
                        askingUptimeConsent = true
                    } else {
                        uptime.setEnabled(false)
                    }
                    return
                }
                store.setWidgetEnabled(kind, enabled: wantsOn)
            })
    }

    /// The tint each card carries on the strip, so a row matches the card it governs.
    private func tint(_ kind: DashboardWidgetKind) -> Color {
        switch kind {
        case .clock: return .orange
        case .uptime: return .green
        case .deviceBattery: return .yellow
        case .nextEvent: return .blue
        case .fileInfo: return .teal
        }
    }

    private var cityStatus: String {
        guard weather.isEnabled else {
            return "Off — no service is contacted. Choose a city to show the weather on the clock."
        }
        let city = weather.city
        let detail = city.detailLabel
        return detail.isEmpty ? city.name : "\(city.name), \(detail)"
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

    private var accessSubtitle: String {
        switch store.calendarAccess {
        case .notDetermined: return "Allow read access to show the next event."
        case .denied: return "Calendar access was denied. You can change it in System Settings."
        case .restricted: return "Calendar access is restricted on this Mac."
        case .writeOnly: return "Write-only access cannot show events; grant full access to continue."
        case .fullAccess: return "Spotter can read upcoming events from your macOS calendars."
        }
    }

    private var unitBinding: Binding<WeatherUnit> {
        Binding(get: { weather.unit }, set: { weather.setUnit($0) })
    }

    private var clockTimeZoneBinding: Binding<String> {
        Binding(
            get: { store.preferences.clockTimeZoneIdentifier ?? "" },
            set: { store.setClockTimeZoneIdentifier($0) })
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
