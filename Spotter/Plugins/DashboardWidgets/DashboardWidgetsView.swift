import SwiftUI

struct DashboardWidgetsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    @ObservedObject var uptime: DashboardUptimeStore
    @ObservedObject var battery: DashboardDeviceBatteryStore

    /// The weather card has no widget-kind flag of its own: consent *is* its enable state, so there
    /// is no second switch to drift out of sync with the network gate. The city always resolves —
    /// `WeatherCity.default` stands in until the user picks one — so it never gates the card.
    private var showsWeather: Bool { weather.isEnabled }

    /// The uptime card works the same way: consent to count input *is* its enable state.
    private var showsUptime: Bool { uptime.isEnabled }

    /// Switched on but with nothing connected that reports a level, the card would be an empty square
    /// claiming a reading it doesn't have — a Mac with only its built-in keyboard is the normal case.
    private var showsBattery: Bool {
        store.isWidgetEnabled(.deviceBattery) && !battery.devices.isEmpty
    }

    @ViewBuilder
    var body: some View {
        if store.isWidgetEnabled(.clock) || showsWeather || showsUptime || showsBattery
            || store.isWidgetEnabled(.nextEvent)
        {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Theme.Spacing.md) {
                    if store.isWidgetEnabled(.clock) {
                        clockCard(now: context.date)
                    }
                    if showsWeather {
                        weatherCard()
                    }
                    if showsUptime {
                        uptimeCard(now: context.date)
                    }
                    if showsBattery {
                        batteryCard()
                    }
                    if store.isWidgetEnabled(.nextEvent) {
                        eventCard(now: context.date)
                    }
                }
                .frame(height: Theme.Size.launcherDashboardHeight)
                // Every card is a square that hugs its width, so pin the strip to the list's leading edge.
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                store.start()
                battery.start()
            }
            .onDisappear {
                store.stop()
                battery.stop()
            }
        }
    }

    /// Back to its original size once the city title came off the merged card and gave the row back.
    private static let conditionSymbolSize: CGFloat = 32
    private static let temperatureBarHeight: CGFloat = 8
    /// Rides inside the track rather than straddling it, so the bar reads as one object.
    private static let temperatureBarMarker: CGFloat = 4.5

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

    /// One square, centered rather than ranged left: the reading in the title slot, the condition
    /// symbol as the card's whole middle, and the scale bar along the bottom placing that reading
    /// between freezing and blazing. The reading takes the title's style rather than the headline's
    /// so it sits level with `UPTIME` and `SUNDAY` across the strip — the symbol is what this card
    /// leads with. Both the city and the condition's phrase are carried by the accessibility label
    /// rather than by a line of their own: the card shows one city's weather and Settings names it,
    /// so a title spent a row repeating something already settled.
    private func weatherCard() -> some View {
        VStack(spacing: 0) {
            cardTitle(temperatureText)
            Spacer(minLength: 0)
            // Monochrome, like every other glyph on the strip — multicolor was the one card that
            // pulled Apple's own palette in instead of the app's.
            Image(systemName: condition?.symbolName ?? "cloud.fill")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: Self.conditionSymbolSize))
            Spacer(minLength: 0)
            // The track spans today's low to high, so without them there is nothing to span: no
            // reading or no daily block means no bar rather than one drawn on a borrowed scale.
            if let reading = weather.reading, let low = reading.lowCelsius,
                let high = reading.highCelsius
            {
                temperatureBar(
                    celsius: reading.temperatureCelsius, low: min(low, high), high: max(low, high))
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(weatherAccessibilityLabel)
    }

    private var weatherAccessibilityLabel: String {
        let city = weather.snapshot?.cityName ?? weather.city.name
        guard let condition, weather.reading != nil else { return "\(city), updating" }
        let range = barEnds.map { ", low \($0.low), high \($0.high)" } ?? ""
        return "\(city), \(temperatureText), \(condition.description)\(range)"
    }

    /// The scale itself: today's range end to end, painted with the slice of the fixed ramp that range
    /// covers, and captioned by the two temperatures it runs between. Both the slice and the marker
    /// come from `DashboardWeatherEngine`, so the colours can't drift from the position.
    private func temperatureBar(celsius: Double, low: Double, high: Double) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            barEndLabel(
                DashboardWeatherEngine.formattedTemperature(celsius: low, unit: weather.unit))
            temperatureTrack(celsius: celsius, low: low, high: high)
            barEndLabel(
                DashboardWeatherEngine.formattedTemperature(celsius: high, unit: weather.unit))
        }
    }

    /// Today's range, captioning the ends of the scale rather than titling the card. Deliberately not
    /// shrinkable: a degree that shrank to fit would be the thing the eye reads as the temperature.
    private func barEndLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
    }

    private func temperatureTrack(celsius: Double, low: Double, high: Double) -> some View {
        let position = DashboardWeatherEngine.markerPosition(
            celsius: celsius, lowCelsius: low, highCelsius: high)
        // Start and end sit outside the track on purpose — that is what crops the ramp to today's slice.
        let window = DashboardWeatherEngine.rampWindow(lowCelsius: low, highCelsius: high)
        // Keeps the marker clear of the capsule's rounded caps, so it never breaks the track's edge.
        let capInset = (Self.temperatureBarHeight - Self.temperatureBarMarker) / 2
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .blue, location: 0),
                                .init(
                                    color: .green,
                                    location: DashboardWeatherEngine.temperatureRampMiddleLocation),
                                .init(color: .red, location: 1),
                            ],
                            startPoint: UnitPoint(x: window.start, y: 0.5),
                            endPoint: UnitPoint(x: window.end, y: 0.5))
                    )
                // Deliberately a literal white rather than a theme token: it sits on a track whose
                // colors are the same in both appearances, so a marker that flipped with the system
                // would be the part that looked wrong.
                Circle()
                    .fill(.white)
                    .frame(width: Self.temperatureBarMarker, height: Self.temperatureBarMarker)
                    .offset(
                        x: capInset
                            + (geometry.size.width - Self.temperatureBarMarker - capInset * 2)
                            * position)
            }
        }
        .frame(height: Self.temperatureBarHeight)
        // Takes whatever the two end captions leave, so the row spans the card's full interior width
        // — which is what the headline and glyph above it center against.
        .frame(maxWidth: .infinity)
    }

    /// Nil until a reading carrying a daily block lands; until then the bar runs uncaptioned rather
    /// than claiming a range it doesn't have.
    private var barEnds: (low: String, high: String)? {
        guard let reading = weather.reading else { return nil }
        return DashboardWeatherEngine.formattedBarEnds(
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

    private static let batteryGaugeSpacing = Theme.Spacing.md
    /// Ring thickness and glyph size as fractions of the gauge, so a lone full-square gauge and four
    /// quarter-square ones read as the same object at different scales.
    private static let batteryGaugeStrokeRatio: CGFloat = 0.1
    private static let batteryGaugeIconRatio: CGFloat = 0.34

    /// Title-free and filled edge to edge, like the clock: the grid of rings *is* the card, and a
    /// heading would cost a row of gauge. Exact levels live in Settings and the accessibility label —
    /// at this size a ring answers "does anything need charging" better than four small numbers.
    private func batteryCard() -> some View {
        let slots = DashboardDeviceBatteryEngine.gaugeSlots(
            for: battery.devices, limit: DashboardDeviceBatteryEngine.gaugeSlotLimit)
        let interior = Theme.Size.launcherDashboardHeight - 2 * Theme.Spacing.lg
        let diameter = DashboardDeviceBatteryEngine.gaugeDiameter(
            slotCount: slots.count, interior: interior, spacing: Self.batteryGaugeSpacing)
        let columns = DashboardDeviceBatteryEngine.gaugeColumns(slotCount: slots.count)
        return VStack(spacing: Self.batteryGaugeSpacing) {
            // Keyed by position: a row is a group of gauges, not an identity of its own.
            ForEach(
                Array(
                    DashboardDeviceBatteryEngine.gaugeRows(for: slots, columns: columns)
                        .enumerated()), id: \.offset
            ) { _, row in
                HStack(spacing: Self.batteryGaugeSpacing) {
                    ForEach(row) { slot in
                        batteryGauge(slot, diameter: diameter)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        // Square like every other card. Without the explicit height a grid shorter than the strip —
        // one row of gauges — would hug its content and sit as a stub between full-height neighbors.
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(DashboardDeviceBatteryEngine.accessibilityLabel(for: battery.devices))
    }

    /// One ring: a faint full track with the level swept clockwise from twelve over it, the device's
    /// SF Symbol in the middle. Red under the low threshold, which is the whole point of the glance.
    /// A charging device breaks the ring at twelve for a bolt to sit in.
    private func batteryGauge(_ slot: DeviceBatterySlot, diameter: CGFloat) -> some View {
        let stroke = diameter * Self.batteryGaugeStrokeRatio
        let isCharging = slot.isCharging
        return ZStack {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.controlSurface, lineWidth: stroke)
                if case .device(let device) = slot {
                    Circle()
                        .trim(
                            from: 0, to: DashboardDeviceBatteryEngine.gaugeFraction(device.percent)
                        )
                        .stroke(
                            DashboardDeviceBatteryEngine.isLow(device.percent) ? Color.red : .green,
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        // `trim` starts at three o'clock; a level reads from the top.
                        .rotationEffect(.degrees(-90))
                }
            }
            // Punched rather than drawn over: the bolt sits on the arc it reports, and a translucent
            // card fill behind it would let the green through instead of clearing a notch for it.
            .compositingGroup()
            .overlay(alignment: .top) {
                if isCharging {
                    Circle()
                        .frame(width: stroke * 2.6, height: stroke * 2.6)
                        .offset(y: -stroke * 1.3)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()

            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: stroke * 1.9))
                    .frame(width: stroke * 2.6, height: stroke * 2.6)
                    .offset(y: -diameter / 2)
            }

            switch slot {
            case .device(let device):
                Image(systemName: device.kind.systemImage)
                    .font(.system(size: diameter * Self.batteryGaugeIconRatio))
            case .overflow(let count):
                Text("+\(count)")
                    .font(.system(size: diameter * Self.batteryGaugeIconRatio, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .frame(width: diameter, height: diameter)
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
