import SwiftUI

/// Which cards show, and in what order, is settled here for the whole strip — so no card's own pane
/// carries a switch, and there is one place to look when the strip isn't what you expected.
struct WidgetArrangementSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var uptime: DashboardUptimeStore

    @State private var askingUptimeConsent = false

    private static let tileSize: CGFloat = 62

    var body: some View {
        SettingsPane(
            title: "Arrangement",
            subtitle:
                "Choose which cards sit above launcher results when the search is empty, and drag "
                + "them into the order you want them drawn."
        ) {
            SettingsCard(header: "Strip") {
                strip
            }
            SettingsCard(header: "Widgets") {
                rows
            }
        }
        .sheet(isPresented: $askingUptimeConsent) {
            UptimeConsentSheet(
                onCancel: { askingUptimeConsent = false },
                onAccept: {
                    askingUptimeConsent = false
                    uptime.setEnabled(true)
                })
        }
    }

    /// The strip as the launcher draws it, at a size that fits a Settings card: one tile per widget
    /// in arrangement order, the switched-off ones outlined rather than filled. Dragging a tile onto
    /// another puts it in that one's place, which is the whole reordering gesture.
    private var strip: some View {
        HStack(spacing: Theme.Spacing.md) {
            ForEach(store.orderedWidgets, id: \.self) { kind in
                tile(kind)
                    .draggable(kind.rawValue) { tile(kind).opacity(0.85) }
                    .dropDestination(for: String.self) { items, _ in move(items, onto: kind) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private func tile(_ kind: DashboardWidgetKind) -> some View {
        let on = isEnabled(kind)
        return VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(on ? tint(kind) : Theme.Colors.textTertiary)
            Text(kind.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(on ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Theme.Spacing.xs)
        .frame(width: Self.tileSize, height: Self.tileSize)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(on ? Theme.Colors.cardFill : .clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(
                    Theme.Colors.cardStroke,
                    style: StrokeStyle(lineWidth: 1, dash: on ? [] : [3, 3]))
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var rows: some View {
        let order = store.orderedWidgets
        ForEach(Array(order.enumerated()), id: \.element) { index, kind in
            if index > 0 { SettingsDivider() }
            SettingsRow(
                title: kind.title, subtitle: kind.summary, systemImage: kind.systemImage,
                tint: tint(kind)
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    // The keyboard path to the same reordering the tiles offer by drag.
                    Button {
                        store.moveWidget(kind, to: index - 1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(kind.title) earlier")

                    Button {
                        store.moveWidget(kind, to: index + 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == order.count - 1)
                    .accessibilityLabel("Move \(kind.title) later")

                    Toggle("", isOn: enabled(kind))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
    }

    /// A drop carrying anything but a widget's own raw value is simply not a reorder — text dragged
    /// in from elsewhere lands here too.
    private func move(_ items: [String], onto target: DashboardWidgetKind) {
        guard let raw = items.first, let moved = DashboardWidgetKind(rawValue: raw),
            let destination = store.orderedWidgets.firstIndex(of: target)
        else { return }
        store.moveWidget(moved, to: destination)
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

    /// The sidebar tint each widget's own pane carries, so a tile matches the row it configures.
    private func tint(_ kind: DashboardWidgetKind) -> Color {
        switch kind {
        case .clock: return .orange
        case .uptime: return .green
        case .deviceBattery: return .yellow
        case .nextEvent: return .blue
        case .fileInfo: return .teal
        }
    }
}

/// Each widget configures itself in its own pane under Settings → Widgets. None of them carries an
/// on/off switch: that, and the strip order, belong to Arrangement.
struct ClockWidgetSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    private static let timeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    @State private var askingConsent = false
    @State private var citySearch = ""
    @State private var refreshing = false
    @State private var refreshFailed = false

    var body: some View {
        SettingsPane(
            title: "Clock",
            subtitle:
                "An analog face above launcher results, with the day and — when weather is on — the "
                + "day's conditions in its corners."
        ) {
            SettingsCard(header: "Face") {
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

            // Weather has no card of its own any more: it is three complications on this face, so it
            // is configured here. Its switch stays a switch because it is the network-consent gate,
            // not a widget's visibility.
            SettingsCard(header: "Weather") {
                SettingsRow(
                    title: "Show Weather",
                    subtitle: weatherStatus,
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

            if weather.isEnabled { weatherDetailsCard }
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

    private var weatherStatus: String {
        let summary = "The temperature, today's range and the condition, on the clock face."
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

    private var clockTimeZoneBinding: Binding<String> {
        Binding(
            get: { store.preferences.clockTimeZoneIdentifier ?? "" },
            set: { store.setClockTimeZoneIdentifier($0) })
    }
}

struct UptimeWidgetSettingsView: View {
    @ObservedObject var uptime: DashboardUptimeStore

    var body: some View {
        SettingsPane(
            title: "Uptime",
            subtitle: "How long today's session has run, with key and click counts."
        ) {
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
            } else {
                // Switching this on is a consent act, so it happens in one place with its dialog.
                SettingsCard(header: "Widget") {
                    SettingsRow(
                        title: "Turned Off",
                        subtitle:
                            "No input is counted. Turn Uptime on in Widgets → Arrangement; Spotter "
                            + "explains exactly what is counted before anything starts.",
                        systemImage: "timer", tint: .green
                    ) {
                        EmptyView()
                    }
                }
            }
        }
    }
}

struct DeviceBatteryWidgetSettingsView: View {
    @ObservedObject var battery: DashboardDeviceBatteryStore

    var body: some View {
        SettingsPane(
            title: "Device Battery",
            subtitle: "Battery levels for connected mice, keyboards and trackpads."
        ) {
            SettingsCard(header: "Detected") {
                if battery.devices.isEmpty {
                    SettingsRow(
                        title: "No Devices",
                        subtitle:
                            "Nothing connected reports a battery level, so the card stays hidden. "
                            + "Built-in keyboards and trackpads have none, and AirPods report "
                            + "theirs somewhere Spotter doesn't read.",
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
        }
        .task { battery.refresh() }
    }
}

struct FileInfoWidgetSettingsView: View {
    var body: some View {
        SettingsPane(
            title: "File Info",
            subtitle:
                "Open the launcher with something selected in the Finder and its kind and size sit "
                + "above the results."
        ) {
            SettingsCard(header: "How It Reads the Selection") {
                SettingsRow(
                    title: "Only From the Finder",
                    subtitle:
                        "Spotter asks the Finder what is selected, and only when the Finder is the "
                        + "app you summoned the launcher from. macOS asks for Automation access the "
                        + "first time.",
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
    }
}

struct CalendarWidgetSettingsView: View {
    @ObservedObject var store: DashboardWidgetsStore

    var body: some View {
        SettingsPane(
            title: "Calendar",
            subtitle: "The next event on your calendar, above launcher results."
        ) {
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
