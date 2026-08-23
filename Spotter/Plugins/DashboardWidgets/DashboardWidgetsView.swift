import AppKit
import SwiftUI

struct DashboardWidgetsView: View {
    @ObservedObject var store: DashboardWidgetsStore
    @ObservedObject var weather: DashboardWeatherStore
    @ObservedObject var uptime: DashboardUptimeStore
    @ObservedObject var battery: DashboardDeviceBatteryStore
    @ObservedObject var fileInfo: DashboardFileInfoStore

    /// Which cards are drawable right now. Order is the user's arrangement; a card that owns its
    /// enable state answers from preferences, a consent-gated one from its own store, and two more
    /// withhold themselves when they have nothing to report.
    private func isVisible(_ kind: DashboardWidgetKind) -> Bool {
        switch kind {
        case .clock, .nextEvent:
            return store.isWidgetEnabled(kind)
        // Consent to count input *is* this card's enable state, so there is no second switch to
        // drift out of sync with the monitor.
        case .uptime:
            return uptime.isEnabled
        // Switched on with nothing connected that reports a level, the card would be an empty square
        // claiming a reading it doesn't have — a Mac with only its built-in keyboard is the normal case.
        case .deviceBattery:
            return store.isWidgetEnabled(kind) && !battery.devices.isEmpty
        // Deliberately not conditioned on there being a selection: the card has a resting state, so
        // it holds its place in the row instead of shuffling the strip every time the Finder loses
        // focus.
        case .fileInfo:
            return store.isWidgetEnabled(kind)
        }
    }

    @ViewBuilder
    var body: some View {
        let visible = store.orderedWidgets.filter(isVisible)
        if !visible.isEmpty {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: Theme.Spacing.md) {
                    ForEach(visible, id: \.self) { kind in
                        card(kind, now: context.date)
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

    @ViewBuilder
    private func card(_ kind: DashboardWidgetKind, now: Date) -> some View {
        switch kind {
        case .clock: clockCard(now: now)
        case .uptime: uptimeCard(now: now)
        case .deviceBattery: batteryCard()
        case .nextEvent: eventCard(now: now)
        case .fileInfo: DashboardFileInfoCard(snapshot: fileInfo.snapshot)
        }
    }

    private func cardTitle(_ text: String) -> some View { DashboardCardTitle(text) }

    /// The headline every card shares, one step below the title in the same rhythm. The widest
    /// realistic string is uptime's "23h 59m", which just fits the square's 96-point interior —
    /// the scale floor is the guard for the outliers rather than the normal case.
    private func cardHeadline(_ text: String) -> some View {
        Text(text)
            .font(.largeTitle)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
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

    /// Weather draws on the clock only once there is something real to draw: consent alone would put
    /// three empty corners on the face while the first reading is still in flight.
    private var showsWeather: Bool { weather.isEnabled && weather.reading != nil }

    /// Today's low and high, the pair a watch face carries under the current reading.
    private var temperatureRangeText: String? {
        guard let ends = barEnds else { return nil }
        return "\(ends.low)–\(ends.high)"
    }

    /// The day, in the clock's own time zone — a face abroad must not date itself from home.
    private func shortDate(_ date: Date) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        style.timeZone = store.clockTimeZone
        return date.formatted(style)
    }

    private func clockAccessibilityLabel(_ now: Date) -> String {
        var parts = [formattedTime(now), formattedDate(now)]
        if showsWeather {
            parts.append(temperatureText)
            if let range = temperatureRangeText { parts.append("range \(range)") }
            if let condition { parts.append(condition.description) }
        }
        return parts.joined(separator: ", ")
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

    /// How far the dial is held off the card's edge, leaving the lane the complications ride in.
    /// Every other card keeps a uniform `md` margin; this one spends its whole square, because the
    /// complications *are* its bezel and the dial is what the margin would otherwise shrink.
    private static let clockFaceInset: CGFloat = 13

    /// A watch face: the analog dial with its complications set along the bezel — the day top-right,
    /// and, when weather is on and a reading has landed, the temperature top-left, today's range
    /// bottom-left and the condition glyph bottom-right. A corner with nothing known stays empty
    /// rather than drawing a placeholder, so the clock alone is still a clock.
    private func clockCard(now: Date) -> some View {
        ZStack {
            AnalogClockFace(timeZone: store.clockTimeZone)
                .padding(Self.clockFaceInset)
            ClockComplicationRing(
                topLeft: showsWeather ? temperatureText : nil,
                topRight: shortDate(now),
                bottomLeft: showsWeather ? temperatureRangeText : nil,
                bottomRightSymbol: showsWeather ? condition?.symbolName : nil,
                color: Theme.Colors.textSecondary)
        }
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(clockAccessibilityLabel(now))
    }

    /// Only what is next. The date left this card for the clock's own corner, so a second copy of it
    /// here would be the strip repeating itself. Without calendar access the access state takes the
    /// same slot, rather than the card going missing.
    private func eventCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            cardTitle("Up Next")
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
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
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

/// The one title style every card shares, so the strip reads as one row rather than five designs.
/// Uppercased here rather than at each call site — a file's kind arrives as the Finder words it.
private struct DashboardCardTitle: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.localizedUppercase)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// Square like every other card: the kind in the title slot, the item's own Finder icon as the
/// middle, then what it is called and how big it is. With nothing selected it rests on a generic
/// glyph rather than leaving the strip — a card that came and went couldn't be relied on to be there.
private struct DashboardFileInfoCard: View {
    let snapshot: DashboardFileInfoSnapshot

    private static let iconSize: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            DashboardCardTitle(snapshot.kindLine)
            Spacer(minLength: 0)
            icon
                .frame(width: Self.iconSize, height: Self.iconSize)
            Spacer(minLength: 0)
            // Truncated in the middle: the extension is half of what the card is reporting.
            Text(snapshot.nameLine)
                .font(.caption2.weight(.medium))
                .foregroundStyle(snapshot.isEmpty ? Theme.Colors.textSecondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !snapshot.sizeLine.isEmpty {
                Text(snapshot.sizeLine)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(
            width: Theme.Size.launcherDashboardHeight,
            height: Theme.Size.launcherDashboardHeight)
        .dashboardCardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(snapshot.accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        if let path = snapshot.iconPath {
            DashboardFileIcon(path: path)
        } else {
            Image(systemName: "doc")
                .font(.system(size: Self.iconSize * 0.8, weight: .light))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

/// The selected item's own Finder icon, warm from `IconCache` when the launcher has drawn it before.
private struct DashboardFileIcon: View {
    let path: String
    @State private var image: NSImage?

    init(path: String) {
        self.path = path
        _image = State(initialValue: IconCache.cached(forFile: path))
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable()
            } else {
                RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            }
        }
        // Reloaded on every path change rather than only when empty: the selection moves from file to
        // file, and a `nil`-guard would pin the first icon to every later one.
        .task(id: path) {
            if let cached = IconCache.cached(forFile: path) {
                image = cached
                return
            }
            image = await IconCache.loadAsync(forFile: path)
        }
    }
}

/// The clock's corner complications, set along the bezel the way a watch face carries them: each
/// label is laid out character by character around one circle, so it curves with the dial instead of
/// sitting square in a corner. The two bottom labels run the other way round and are turned over, or
/// they would read upside down. The condition glyph stays level — a tilted icon reads as a mistake,
/// and watch faces keep theirs upright too.
private struct ClockComplicationRing: View {
    var topLeft: String?
    var topRight: String?
    var bottomLeft: String?
    var bottomRightSymbol: String?
    let color: Color

    /// Degrees clockwise from 12 o'clock, matching the face's own angle convention.
    private static let topLeftAngle = 315.0
    private static let topRightAngle = 45.0
    private static let bottomLeftAngle = 225.0
    private static let bottomRightAngle = 135.0
    /// Small enough that a range ("18°–26°") still spans well under its quadrant at this diameter.
    private static let font = Font.system(size: 9, weight: .medium)
    private static let symbolSize: CGFloat = 11
    /// Half a cap height and a hair, so the arc sits inside the card rather than on its edge.
    private static let ringInset: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            let radius = min(geometry.size.width, geometry.size.height) / 2 - Self.ringInset
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    draw(topLeft, at: Self.topLeftAngle, flipped: false,
                        context: &context, center: center, radius: radius)
                    draw(topRight, at: Self.topRightAngle, flipped: false,
                        context: &context, center: center, radius: radius)
                    draw(bottomLeft, at: Self.bottomLeftAngle, flipped: true,
                        context: &context, center: center, radius: radius)
                }
                if let bottomRightSymbol {
                    Image(systemName: bottomRightSymbol)
                        // Monochrome, like every other glyph on the strip — multicolor was the one
                        // card that pulled Apple's own palette in instead of the app's.
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: Self.symbolSize))
                        .foregroundStyle(color)
                        .offset(
                            x: radius * sin(Self.bottomRightAngle * .pi / 180),
                            y: -radius * cos(Self.bottomRightAngle * .pi / 180))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    /// Sets one string on the arc, centred on `centerAngle`. Each glyph is placed at the angle its
    /// own width has reached and turned to stand on the tangent there; resolving per character is
    /// what costs the string its kerning, which is the usual trade for type on a curve.
    private func draw(
        _ text: String?, at centerAngle: Double, flipped: Bool,
        context: inout GraphicsContext, center: CGPoint, radius: CGFloat
    ) {
        guard let text, !text.isEmpty, radius > 0 else { return }
        let glyphs = text.map { character -> (text: GraphicsContext.ResolvedText, width: CGFloat) in
            let resolved = context.resolve(
                Text(String(character)).font(Self.font).foregroundStyle(color))
            return (resolved, resolved.measure(in: CGSize(width: 200, height: 200)).width)
        }
        // Arc length over radius is the angle it subtends, so the whole string spans `span` degrees.
        let span = degrees(glyphs.reduce(0) { $0 + $1.width }, radius: radius)
        var travelled: CGFloat = 0
        for glyph in glyphs {
            let reached = degrees(travelled + glyph.width / 2, radius: radius)
            // Flipped labels run anticlockwise, which is what keeps them reading left to right along
            // the bottom of the circle.
            let angle = flipped
                ? centerAngle + span / 2 - reached
                : centerAngle - span / 2 + reached
            let radians = angle * .pi / 180
            context.drawLayer { layer in
                layer.translateBy(
                    x: center.x + radius * sin(radians), y: center.y - radius * cos(radians))
                layer.rotate(by: .degrees(flipped ? angle + 180 : angle))
                layer.draw(glyph.text, at: .zero, anchor: .center)
            }
            travelled += glyph.width
        }
    }

    private func degrees(_ arcLength: CGFloat, radius: CGFloat) -> Double {
        Double(arcLength / radius) * 180 / .pi
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
