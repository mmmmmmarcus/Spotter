import EventKit
import Foundation

// Read native objects only on the event reader's queue and return plain display values.
enum CalendarEventMetadata {
    static func read(_ event: EKEvent) -> [DashboardEventDetail] {
        var fields: [DashboardEventDetail] = []
        if let organizer = event.organizer {
            let person = participant(organizer)
            fields.append(.init(name: "Organizer", value: person.name, people: [person]))
        }
        if let attendees = event.attendees, !attendees.isEmpty {
            let people = attendees.map(participant)
            fields.append(.init(name: "Participants", value: people.map(\.name).joined(separator: "\n"), people: people))
        }
        if let rules = event.recurrenceRules, !rules.isEmpty {
            fields.append(.init(name: "Repeats", value: rules.map { recurrence($0, zone: event.timeZone ?? .current) }.joined(separator: "\n")))
        }
        let status: String? = switch event.status {
        case .confirmed: "Confirmed"
        case .tentative: "Tentative"
        case .canceled: "Canceled"
        default: nil
        }
        if let status { fields.append(.init(name: "Status", value: status)) }
        return fields
    }

    private static func participant(_ person: EKParticipant) -> DashboardEventPerson {
        DashboardEventPerson(name: DashboardEventPerson.displayName(person.name),
                             accepted: person.participantStatus == .accepted)
    }

    private static func recurrence(_ rule: EKRecurrenceRule, zone: TimeZone) -> String {
        let unit: String = switch rule.frequency {
        case .daily: "day"
        case .weekly: "week"
        case .monthly: "month"
        case .yearly: "year"
        @unknown default: "period"
        }
        var parts = [rule.interval == 1 ? "Every \(unit)" : "Every \(rule.interval) \(unit)s"]
        let calendar = Calendar.current
        if let days = rule.daysOfTheWeek, !days.isEmpty {
            parts.append(days.map { day in
                let index = day.dayOfTheWeek.rawValue - 1
                let name = calendar.weekdaySymbols.indices.contains(index) ? calendar.weekdaySymbols[index] : ""
                return day.weekNumber == 0 ? name : "\(day.weekNumber) · \(name)"
            }.joined(separator: ", "))
        }
        for (label, values) in [("Month days", rule.daysOfTheMonth), ("Months", rule.monthsOfTheYear),
                                ("Year days", rule.daysOfTheYear), ("Year weeks", rule.weeksOfTheYear), ("Positions", rule.setPositions)] {
            if let values, !values.isEmpty { parts.append(label + ": " + values.map(\.stringValue).joined(separator: ", ")) }
        }
        if let end = rule.recurrenceEnd {
            if let date = end.endDate {
                var style = Date.FormatStyle(date: .abbreviated, time: .omitted)
                style.timeZone = zone
                parts.append("Until " + date.formatted(style))
            } else if end.occurrenceCount > 0 { parts.append("\(end.occurrenceCount) occurrences") }
        }
        return parts.joined(separator: " · ")
    }
}
