import SwiftUI

struct CalendarScheduleView: View {
    @EnvironmentObject private var core: AppCore
    @ObservedObject var model: CalendarScheduleStore
    @ObservedObject var dashboard: DashboardWidgetsStore
    let context: PluginPaletteCanvasContext
    @State private var positionedPeriod: TimelinePeriod?

    private struct TimelinePeriod: Equatable {
        let mode: ScheduleViewMode
        let date: Date
    }

    private struct PositionRequest: Equatable {
        let period: TimelinePeriod
        let isLoading: Bool
    }
    private var events: [DashboardEvent] { model.matching(context.query) }
    private var days: [Date] { model.days }
    private let hourHeight = Theme.Size.scheduleHourHeight

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            toolbar
            if let id = model.detailID, let event = model.events.first(where: { rowID($0) == id }) {
                detail(event)
            } else if model.mode == .month {
                month
            } else {
                timeline
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.sm)
        .overlay(alignment: .bottomTrailing) {
            if model.isLoading { ProgressView().controlSize(.small).padding(Theme.Spacing.md) }
        }
        .onAppear { if !model.isLoading { model.refresh() } }
        .onChange(of: model.mode) { core.palette.focusToken = UUID() }
        .onChange(of: model.date) { core.palette.focusToken = UUID() }
        .onChange(of: dashboard.preferences) { model.refresh() }
        .onChange(of: dashboard.calendarAccess) { model.refresh() }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(periodTitle).font(.headline).lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: Theme.Spacing.md)
            Button("Today") { model.today() }.controlSize(.small)
            Button { model.move(-1) } label: { Image(systemName: "chevron.left") }
                .help("Previous \(model.mode.title)")
            Button { model.move(1) } label: { Image(systemName: "chevron.right") }
                .help("Next \(model.mode.title)")
            Picker("Calendar view", selection: Binding(get: { model.mode }, set: model.setMode)) {
                ForEach(ScheduleViewMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()
        }
        .buttonStyle(.plain)
        .focusable(false)
        .frame(height: Theme.Size.scheduleToolbarHeight)
    }

    private var periodTitle: String {
        switch model.mode {
        case .day: model.date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
        case .week:
            (days.first ?? model.date).formatted(.dateTime.month(.abbreviated).day()) + " – "
                + (days.last ?? model.date).formatted(.dateTime.month(.abbreviated).day().year())
        case .month: model.date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func rowID(_ event: DashboardEvent) -> String { CalendarSchedulePlugin.rowID(for: event) }
    private func onDay(_ day: Date) -> [DashboardEvent] {
        events.filter {
            ScheduleLayout.overlaps(start: $0.startDate, end: $0.endDate, day: day, calendar: model.calendar)
        }
    }

    private func accent(_ event: DashboardEvent) -> Color {
        let index = event.calendarTitle.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % NoteTint.selectable.count }
        return Theme.Colors.noteTintAccent(NoteTint.selectable[index])
    }

    private func dayLabel(_ day: Date, weekday: Bool) -> some View {
        Text(day.formatted(weekday ? .dateTime.weekday(.abbreviated).day() : .dateTime.day()))
            .font(.system(size: 11, weight: model.calendar.isDateInToday(day) ? .bold : .medium))
            .foregroundStyle(model.calendar.isDateInToday(day) ? Theme.Colors.noteTintAccent(.red) : .primary)
    }

    private var month: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                ForEach(Array(days.prefix(7)), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geometry in
                VStack(spacing: Theme.Spacing.xxs) {
                    ForEach(0..<6, id: \.self) { week in
                        HStack(spacing: Theme.Spacing.xxs) {
                            ForEach(Array(days.dropFirst(week * 7).prefix(7)), id: \.self) { day in
                                monthCell(day)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: max(0, (geometry.size.height - Theme.Spacing.xxs * 5) / 6))
                            }
                        }
                    }
                }
            }
        }
    }

    private func monthCell(_ day: Date) -> some View {
        let dayEvents = onDay(day)
        let selected = context.selectedID == CalendarSchedulePlugin.dayID(day)
        let inMonth = model.calendar.isDate(day, equalTo: model.date, toGranularity: .month)
        return Button { context.activate(CalendarSchedulePlugin.dayID(day)) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                HStack(spacing: Theme.Spacing.xxs) {
                    dayLabel(day, weekday: false)
                    Spacer(minLength: 0)
                    if dayEvents.count > 1 {
                        Text("+\(dayEvents.count - 1)").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                if let event = dayEvents.first {
                    Text(event.title).font(.system(size: 10)).lineLimit(1)
                        .foregroundStyle(accent(event))
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Spacing.xs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(selected ? Theme.Colors.selection : Theme.Colors.controlSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            .opacity(inMonth ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(day.formatted(date: .complete, time: .omitted) + " · \(dayEvents.count) events — View Day")
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + ", \(dayEvents.count) events")
    }

    private var timeline: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: 0) {
                Text(model.calendar.timeZone.abbreviation() ?? "")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(width: Theme.Size.scheduleTimeGutter)
                ForEach(days, id: \.self) { day in
                    Button { model.showDay(day) } label: { dayLabel(day, weekday: true).frame(maxWidth: .infinity) }
                        .buttonStyle(.plain)
                }
            }
            if events.contains(where: \.isAllDay) { allDayEvents }
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    GeometryReader { geometry in
                        timeGrid(width: geometry.size.width)
                    }
                    .frame(height: hourHeight * 24)
                }
                .task(id: PositionRequest(
                    period: TimelinePeriod(mode: model.mode, date: model.date), isLoading: model.isLoading
                )) {
                    let period = TimelinePeriod(mode: model.mode, date: model.date)
                    guard !model.isLoading, positionedPeriod != period else { return }
                    // Wait for the all-day lane and timeline anchors to settle before positioning.
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    if days.contains(where: { model.calendar.isDateInToday($0) }) {
                        proxy.scrollTo("current-time", anchor: .center)
                    } else {
                        proxy.scrollTo("hour:8", anchor: .top)
                    }
                    positionedPeriod = period
                }
                .onDisappear { positionedPeriod = nil }
                .onChange(of: context.selectedID) {
                    guard !model.isLoading,
                          positionedPeriod == TimelinePeriod(mode: model.mode, date: model.date)
                    else { return }
                    if let selected = context.selectedID { proxy.scrollTo(selected, anchor: .center) }
                }
                .overlayScroller()
            }
            if events.isEmpty, !model.isLoading {
                Text(context.query.isEmpty ? "No events in this period" : "No matching events")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var allDayEvents: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("All day").font(.system(size: 9)).foregroundStyle(.secondary)
                .frame(width: Theme.Size.scheduleTimeGutter)
            ForEach(days, id: \.self) { day in
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: Theme.Spacing.xxs) {
                            ForEach(Array(onDay(day).filter(\.isAllDay).enumerated()), id: \.offset) { _, event in
                                eventButton(event, compact: true).id(rowID(event))
                            }
                        }
                    }
                    .onChange(of: context.selectedID) {
                        if let id = context.selectedID { proxy.scrollTo(id) }
                    }
                }
                .frame(maxWidth: .infinity).frame(height: Theme.Size.scheduleAllDayHeight)
            }
        }
    }

    private func timeGrid(width: CGFloat) -> some View {
        let gutter = Theme.Size.scheduleTimeGutter
        let dayWidth = max(1, (width - gutter) / CGFloat(max(1, days.count)))
        return ZStack(alignment: .topLeading) {
            if days.contains(where: { model.calendar.isDateInToday($0) }) {
                let minute = model.calendar.component(.hour, from: Date()) * 60
                    + model.calendar.component(.minute, from: Date())
                // A layout anchor has a reliable scroll rect; drawing offsets alone do not.
                VStack(spacing: 0) {
                    Color.clear.frame(height: CGFloat(minute) / 60 * hourHeight)
                    Color.clear.frame(height: 1).id("current-time")
                    Spacer(minLength: 0)
                }
                .frame(height: hourHeight * 24)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 0) {
                    Text(hourLabel(hour)).font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: gutter, alignment: .leading)
                    Rectangle().fill(Theme.Colors.separator).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .offset(y: CGFloat(hour) * hourHeight).id("hour:\(hour)")
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Rectangle().fill(Theme.Colors.separator).frame(width: 1, height: hourHeight * 24)
                    .offset(x: gutter + CGFloat(index) * dayWidth)
                let timed = onDay(day).filter { !$0.isAllDay }
                let blocks = ScheduleLayout.columns(timed.compactMap {
                    ScheduleLayout.block(id: rowID($0), start: $0.startDate, end: $0.endDate,
                                         day: day, calendar: model.calendar)
                })
                ForEach(blocks) { block in
                    if let event = timed.first(where: { rowID($0) == block.id }) {
                        let columnWidth = dayWidth / CGFloat(block.columnCount)
                        eventButton(event, compact: model.mode == .week)
                            .frame(width: max(1, columnWidth - Theme.Spacing.xxs),
                                   height: max(18, (block.endMinute - block.startMinute) / 60 * hourHeight - 2))
                            .clipped()
                            .offset(x: gutter + CGFloat(index) * dayWidth + CGFloat(block.column) * columnWidth + 1,
                                    y: block.startMinute / 60 * hourHeight)
                            .id(block.id)
                    }
                }
                if model.calendar.isDateInToday(day) {
                    let minute = model.calendar.component(.hour, from: Date()) * 60
                        + model.calendar.component(.minute, from: Date())
                    Rectangle().fill(Theme.Colors.noteTintAccent(.red)).frame(width: dayWidth, height: 1)
                        .offset(x: gutter + CGFloat(index) * dayWidth, y: CGFloat(minute) / 60 * hourHeight)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func hourLabel(_ hour: Int) -> String {
        let value = Date(timeIntervalSinceReferenceDate: Double(hour) * 3600)
        var format = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        format.timeZone = TimeZone(secondsFromGMT: 0)!
        return value.formatted(format)
    }

    private func eventButton(_ event: DashboardEvent, compact: Bool) -> some View {
        Button { context.activate(rowID(event)) } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(event.title).font(.system(size: compact ? 10 : 12, weight: .medium)).lineLimit(compact ? 2 : 3)
                if !compact, !event.isAllDay {
                    Text(event.startDate.formatted(date: .omitted, time: .shortened))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(accent(event).opacity(0.16))
            .overlay(alignment: .leading) { Rectangle().fill(accent(event)).frame(width: 2) }
            .overlay {
                if context.selectedID == rowID(event) {
                    RoundedRectangle(cornerRadius: Theme.Radius.menu).strokeBorder(accent(event), lineWidth: 1.5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(event.title + " · " + event.calendarTitle)
        .accessibilityLabel(event.title + ", " + CalendarScheduleEngine.timeLabel(
            start: event.startDate, end: event.endDate, isAllDay: event.isAllDay, calendar: model.calendar))
    }

    private func detail(_ event: DashboardEvent) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                Button { model.detailID = nil } label: { Label("Back to Schedule", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Text(event.title).font(.title2).textSelection(.enabled)
                Label(event.calendarTitle, systemImage: "calendar").foregroundStyle(accent(event))
                Text(event.startDate.formatted(date: .complete, time: .omitted))
                Text(CalendarScheduleEngine.timeLabel(start: event.startDate, end: event.endDate,
                                                     isAllDay: event.isAllDay, calendar: model.calendar))
                if let location = event.location, !location.isEmpty { Label(location, systemImage: "mappin") }
                if let link = CalendarScheduleEngine.meetingLink(
                    urlString: event.urlString, location: event.location, notes: event.notes) {
                    Button("Join \(link.provider)") { core.openCalendarMeetingLink(link.urlString) }
                }
                if let notes = event.notes, !notes.isEmpty { Text(notes).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.xl)
        }
        .overlayScroller()
    }
}
