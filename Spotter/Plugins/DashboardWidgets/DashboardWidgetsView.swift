import SwiftUI

struct DashboardWidgetsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    @ObservedObject var uptime: DashboardUptimeStore

    /// The weather cards have no widget-kind flag of their own: consent *is* their enable state, so
    /// there is no second switch to drift out of sync with the network gate. Both the condition and
    /// the temperature square are drawn from one reading and one request, so they share that single
    /// switch. The city always resolves — `WeatherCity.default` stands in until the user picks one —
    /// so it never gates them.
    private var showsWeather: Bool { weather.isEnabled }

    /// The uptime card works the same way: consent to count input *is* its enable state.
    private var showsUptime: Bool { uptime.isEnabled }

    @ViewBuilder
    var body: some View {
        if store.hasEnabledWidgets || showsWeather || showsUptime {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Theme.Spacing.md) {
                    if store.isWidgetEnabled(.clock) {
                        clockCard(now: context.date)
                    }
                    if showsWeather {
                        conditionCard()
                        temperatureCard()
                    }
                    if showsUptime {
                        uptimeCard(now: context.date)
                    }
                    if store.isWidgetEnabled(.nextEvent) {
                        eventCard(now: context.date)
                    }
                }
                .frame(height: Theme.Size.launcherDashboardHeight)
                // Every card is a square that hugs its width, so pin the strip to the list's leading edge.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { store.start() }
            .onDisappear { store.stop() }
        }
    }

    private static let conditionSymbolSize: CGFloat = 32
    private static let temperatureBarHeight: CGFloat = 5
    private static let temperatureBarMarker: CGFloat = 9

    /// The one title style every card shares, so the strip reads as one row rather than four
    /// designs. Uppercased here rather than at each call site — a city name arrives as typed.
    private func cardTitle(_ text: String) -> some View {
        Text(text.localizedUppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The headline every card shares, one step below the title in the same rhythm. The widest
    /// realistic string is uptime's "23h 59m", which just fits the square's 96-point interior —
    /// the scale floor is the guard for the outliers rather than the normal case.
    private func cardHeadline(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    /// The first of the two weather squares, centered rather than ranged left: the city, the symbol
    /// as the card's whole middle, and the phrase it stands for underneath.
    private func conditionCard() -> some View {
        VStack(spacing: 0) {
            cardTitle(weather.snapshot?.cityName ?? weather.city.name)
            // No floor on either gap: the phrase may wrap to two lines, and the air is what should give.
            Spacer(minLength: 0)
            // Monochrome, like every other glyph on the strip — multicolor was the one card that
            // pulled Apple's own palette in instead of the app's.
            Image(systemName: condition?.symbolName ?? "cloud.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: Self.conditionSymbolSize))
            Spacer(minLength: 0)
            Text(condition?.description ?? "Updating…")
                .font(.caption2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
    }

    /// The second weather square: today's range up top, the current reading as the headline, and the
    /// scale bar under it placing that reading between freezing and blazing.
    private func temperatureCard() -> some View {
        VStack(spacing: 0) {
            cardTitle(rangeText ?? "Today")
            Spacer(minLength: 0)
            cardHeadline(temperatureText)
            Spacer(minLength: 0)
            // No reading, no marker — an empty track would still imply a temperature somewhere on it.
            if let reading = weather.reading {
                temperatureBar(celsius: reading.temperatureCelsius)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
    }

    /// The scale itself: a cold-to-hot ramp with the reading marked on it. The ends and the green
    /// midpoint come from `DashboardWeatherEngine`, so the stops can't drift from the math that
    /// places the marker.
    private func temperatureBar(celsius: Double) -> some View {
        let position = DashboardWeatherEngine.temperatureBarPosition(celsius: celsius)
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .blue, location: 0),
                                .init(
                                    color: .green,
                                    location: DashboardWeatherEngine.temperatureBarMiddlePosition),
                                .init(color: .red, location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: Self.temperatureBarHeight)
                    .frame(maxHeight: .infinity)
                // Deliberately a literal white rather than a theme token: it sits on a track whose
                // colors are the same in both appearances, so a marker that flipped with the system
                // would be the part that looked wrong. The ring keeps it legible over the warm middle.
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 0.5))
                    .frame(width: Self.temperatureBarMarker, height: Self.temperatureBarMarker)
                    // Inset by its own width so the marker stays on the track at both extremes.
                    .offset(x: (geometry.size.width - Self.temperatureBarMarker) * position)
            }
        }
        .frame(height: Self.temperatureBarMarker)
        // The one child that claims the full interior width, which is what the rest centers against.
        .frame(maxWidth: .infinity)
    }

    /// Nil until a reading carrying a daily block lands; the card titles itself "Today" until then.
    private var rangeText: String? {
        guard let reading = weather.reading else { return nil }
        return DashboardWeatherEngine.formattedRange(
            lowCelsius: reading.lowCelsius, highCelsius: reading.highCelsius, unit: weather.unit)
    }

    private var condition: WeatherCondition? {
        weather.reading.map {
            DashboardWeatherEngine.condition(forWeatherCode: $0.weatherCode, isDay: $0.isDay)
        }
    }

    /// An em dash until the first reading lands, so the card never implies a temperature it doesn't have.
    private var temperatureText: String {
        guard let reading = weather.reading else { return "—" }
        return DashboardWeatherEngine.formattedTemperature(
            celsius: reading.temperatureCelsius, unit: weather.unit)
    }

    /// Square, like the clock and weather: today's elapsed time as the headline, then the day's key
    /// and click tallies.
    private func uptimeCard(now: Date) -> some View {
        let snapshot = uptime.snapshot(now: now)
        return VStack(alignment: .leading, spacing: 0) {
            cardTitle("Uptime")
            // An em dash until the day's first activity, so the card never claims a session it can't date.
            cardHeadline(
                snapshot.sessionStart
                    .map { DashboardUptimeEngine.formattedElapsed(from: $0, to: now) } ?? "—")
            Spacer(minLength: 0)
            if uptime.needsAccessibility {
                // Clicks count without the grant, keys can't — offer it rather than showing a zero.
                Button("Allow keys") { Permissions.ensureAccessibility() }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .font(.caption2)
            } else {
                countLine(DashboardUptimeEngine.keysLabel(snapshot.counts.keys))
            }
            countLine(DashboardUptimeEngine.clicksLabel(snapshot.counts.clicks))
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.launcherDashboardHeight, alignment: .topLeading)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(uptimeAccessibilityLabel(snapshot, now: now))
    }

    /// A spelled-out tally. The longest realistic line ("123,456 mouse clicks") overruns the square's
    /// 96 points, so it shrinks rather than truncating the word that says what was counted.
    private func countLine(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
    }

    private func uptimeAccessibilityLabel(_ snapshot: DashboardUptimeSnapshot, now: Date) -> String {
        let elapsed =
            snapshot.sessionStart
            .map { "Up \(DashboardUptimeEngine.formattedElapsed(from: $0, to: now))" }
            ?? "Session not started"
        let keys =
            uptime.needsAccessibility
            ? "keyboard counting needs Accessibility"
            : DashboardUptimeEngine.keysLabel(snapshot.counts.keys)
        return "\(elapsed), \(keys), \(DashboardUptimeEngine.clicksLabel(snapshot.counts.clicks))"
    }

    /// The clock is a square, title-free analog face; VoiceOver still reads the exact time and date.
    private func clockCard(now: Date) -> some View {
        AnalogClockFace(timeZone: store.clockTimeZone)
            .padding(Theme.Spacing.md)
            .frame(width: Theme.Size.launcherDashboardHeight)
            .dashboardCardSurface()
            .accessibilityLabel("\(formattedTime(now)), \(formattedDate(now))")
    }

    /// Structured like a calendar app's own widget: today's date at the top, the next event pinned to
    /// the bottom. The date comes from the clock rather than EventKit, so it stays correct even
    /// without calendar access — the bottom row carries the access state instead of the whole card.
    private func eventCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle(now.formatted(.dateTime.weekday(.wide)))
            cardHeadline(now.formatted(.dateTime.day()))
            Spacer(minLength: Theme.Spacing.xs)
            eventFooter(now: now)
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.launcherDashboardHeight, alignment: .topLeading)
        .dashboardCardSurface()
    }

    @ViewBuilder
    private func eventFooter(now: Date) -> some View {
        switch store.calendarAccess {
        case .fullAccess:
            if let event = store.nextEvent {
                Text(event.title)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(eventTime(event, now: now))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else {
                footerNote("No events ahead")
            }
        case .notDetermined, .writeOnly:
            if store.isRequestingCalendarAccess {
                footerNote("Waiting…")
            } else {
                footerButton("Allow Calendar") { store.requestCalendarAccess() }
            }
        case .denied:
            footerButton("Open Settings") { Permissions.openCalendarSettings() }
        case .restricted:
            footerNote("Calendar restricted")
        }
    }

    private func footerNote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(2)
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.link)
            .controlSize(.small)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    /// The card already shows today's date, so a same-day event needs only its time.
    private func eventTime(_ event: DashboardEvent, now: Date) -> String {
        if event.isAllDay { return "All day" }
        let time = event.startDate.formatted(.dateTime.hour().minute())
        guard !Calendar.current.isDate(event.startDate, inSameDayAs: now) else { return time }
        return "\(event.startDate.formatted(.dateTime.weekday(.abbreviated))) · \(time)"
    }

    private func formattedTime(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }

    private func formattedDate(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime
            .weekday(.abbreviated).month(.abbreviated).day()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }
}

/// A Clock-app-style face drawn in the palette's alpha ramp: ramp ticks, numerals and hands over the card fill, with an orange second hand — no opaque dial.
private struct AnalogClockFace: View {
    let timeZone: TimeZone

    var body: some View {
        // Its own timeline, at the display's refresh rate: the strip's one-second tick would step the
        // second hand instead of sweeping it, and raising that cadence would redraw every other card too.
        TimelineView(.animation) { context in
            face(
                angles: DashboardWidgetsEngine.clockHandAngles(
                    for: context.date, timeZone: timeZone))
        }
    }

    private func face(angles: ClockHandAngles) -> some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for tick in 0..<60 {
                let isHour = tick.isMultiple(of: 5)
                context.stroke(
                    radial(
                        center: center, angle: .degrees(Double(tick) * 6),
                        from: radius * (isHour ? 0.87 : 0.93), to: radius * 0.99),
                    with: .color(isHour ? .primary : Theme.Colors.textTertiary),
                    style: StrokeStyle(lineWidth: isHour ? 2 : 1, lineCap: .round))
            }

            for hour in 1...12 {
                context.draw(
                    context.resolve(Text("\(hour)").font(.caption2.weight(.semibold))),
                    at: point(center: center, angle: .degrees(Double(hour) * 30), radius: radius * 0.70))
            }

            context.stroke(
                radial(center: center, angle: .degrees(angles.hour), from: -radius * 0.12, to: radius * 0.50),
                with: .color(.primary), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            context.stroke(
                radial(center: center, angle: .degrees(angles.minute), from: -radius * 0.12, to: radius * 0.74),
                with: .color(.primary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            context.stroke(
                radial(center: center, angle: .degrees(angles.second), from: -radius * 0.20, to: radius * 0.80),
                with: .color(.orange), style: StrokeStyle(lineWidth: 1.25, lineCap: .round))

            // Same orange as the hand it caps — the two read as one element, so they can't diverge.
            let hub = radius * 0.06
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2)),
                with: .color(.orange))
        }
    }

    /// A stroke segment along `angle` (degrees clockwise from 12), spanning `from`→`to` out of `center`; a negative `from` is the hand's counterweight tail.
    private func radial(center: CGPoint, angle: Angle, from: CGFloat, to: CGFloat) -> Path {
        var path = Path()
        path.move(to: point(center: center, angle: angle, radius: from))
        path.addLine(to: point(center: center, angle: angle, radius: to))
        return path
    }

    private func point(center: CGPoint, angle: Angle, radius: CGFloat) -> CGPoint {
        CGPoint(
            x: center.x + radius * sin(angle.radians),
            y: center.y - radius * cos(angle.radians))
    }
}

extension View {
    /// The dashboard cards' shared surface — the same `cardFill`/`cardStroke` language as calculator cards.
    fileprivate func dashboardCardSurface() -> some View {
        background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}
