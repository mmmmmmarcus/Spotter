import SwiftUI

struct CalendarEventDetailView: View {
    let event: DashboardEvent
    let calendar: Calendar
    @ObservedObject var worldClock: WorldClockStore
    let accent: Color
    let joinMeeting: (String) -> Void
    @State private var notes = ScheduleNotes(runs: [], fields: [])

    private var primaryTime: ScheduleEventTime? {
        CalendarScheduleEngine.detailTimes(
            start: event.startDate, end: event.endDate, isAllDay: event.isAllDay,
            eventTimeZoneIdentifier: event.timeZoneIdentifier,
            cities: [], calendar: calendar).first
    }

    private var details: [DashboardEventDetail] {
        let nativeNames = Set(event.details.map(\.name))
        let all = event.details + notes.fields.filter { !nativeNames.contains($0.name) }
            .map { DashboardEventDetail(name: $0.name, value: $0.value) }
        let leading = ["Organizer", "Participants"]
        return leading.flatMap { name in all.filter { $0.name == name } }
            + all.filter { !leading.contains($0.name) && !["Meeting ID", "Alerts", "Availability"].contains($0.name) }
    }

    private var attributedNotes: AttributedString {
        notes.runs.reduce(into: AttributedString()) { result, run in
            var part = AttributedString(run.text)
            part.link = run.url
            result.append(part)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let columnsWidth = max(0, geometry.size.width - Theme.Spacing.xxl * 2 - 1)
            let informationWidth = columnsWidth * Theme.Size.scheduleDetailInformationFraction
            let notesWidth = columnsWidth - informationWidth
            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                ScrollView {
                    information
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Theme.Spacing.xl)
                }
                .overlayScroller()
                .frame(width: informationWidth)
                Rectangle().fill(Theme.Colors.separator).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        WorldClockMapContent(store: worldClock, instant: event.startDate, compactLabels: true)
                            .frame(height: min(geometry.size.height * 0.45, notesWidth / 2) / 2)
                            .help("World Clock cities at the start of this event")
                        Group {
                            if notes.runs.isEmpty {
                                Text("No notes").foregroundStyle(.secondary)
                            } else {
                                Text(attributedNotes).textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .tint(.accentColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, Theme.Spacing.xl)
                    }
                }
                .overlayScroller()
                .frame(width: notesWidth, alignment: .leading)
            }
        }
        .padding(Theme.Spacing.xl)
        .environment(\.openURL, OpenURLAction { url in
            guard let safe = ScheduleNotes.safeURL(url.absoluteString) else { return .discarded }
            joinMeeting(safe.absoluteString)
            return .handled
        })
        .task(id: event.notes) {
            let raw = event.notes ?? ""
            let parsed = await Task.detached(priority: .userInitiated) { ScheduleNotes.parse(raw) }.value
            guard !Task.isCancelled else { return }
            notes = parsed
        }
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(event.title)
                .font(.system(size: Theme.Size.scheduleDetailTitle, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                informationRow("Calendar", symbol: "calendar") {
                    Text(event.calendarTitle).foregroundStyle(accent)
                }
                if let primary = primaryTime {
                    informationRow("Date and Time", symbol: "clock") {
                        Text(primary.date + " · " + primary.time + (event.isAllDay ? "" : " · " + primary.name))
                            .monospacedDigit()
                    }
                }
                if let location = event.location, !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    informationRow("Location", symbol: "mappin.and.ellipse") { Text(location) }
                }
                if let link = CalendarScheduleEngine.meetingLink(
                    urlString: event.urlString, location: event.location, notes: event.notes) {
                    informationRow("Meeting", symbol: "video") {
                        Button("Join \(link.provider)") { joinMeeting(link.urlString) }.buttonStyle(.link)
                    }
                }
                if let address = event.urlString, let url = ScheduleNotes.safeURL(address) {
                    informationRow("Event Link", symbol: "link") { Link(url.host ?? "Event Link", destination: url) }
                }
                ForEach(Array(details.enumerated()), id: \.offset) { _, field in
                    informationRow(field.name, symbol: symbol(for: field.name)) {
                        if ["Organizer", "Participants"].contains(field.name) {
                            CalendarEventPeopleView(people: field.displayPeople)
                        } else { Text(field.value) }
                    }
                }
            }
            .font(.subheadline)
        }
        .multilineTextAlignment(.leading)
    }

    private func informationRow<Content: View>(
        _ title: String, symbol: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: Theme.Size.headerIconSlot)
                .help(title)
                .accessibilityHidden(true)
            content()
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func symbol(for field: String) -> String {
        switch field {
        case "Organizer": "person"
        case "Participants": "person.2"
        case "Repeats": "repeat"
        case "Status": "checkmark.circle"
        default: "info.circle"
        }
    }
}
