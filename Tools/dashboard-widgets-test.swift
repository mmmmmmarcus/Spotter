import Foundation

@main
@MainActor
struct DashboardWidgetsTests {
    private static var failures = 0

    static func main() {
        check(
            DashboardWidgetsEngine.widgetOrder(from: nil) == DashboardWidgetKind.allCases,
            "no saved arrangement should fall back to the catalog order")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["file-info", "clock"]).prefix(2)
                == [.fileInfo, .clock],
            "a saved arrangement should lead with what it named")
        check(
            Set(DashboardWidgetsEngine.widgetOrder(from: ["file-info"]))
                == Set(DashboardWidgetKind.allCases),
            "a partial arrangement should still cover every widget")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["clock", "clock", "nonsense"]).count
                == DashboardWidgetKind.allCases.count,
            "duplicates and unknown identifiers should not change the widget count")
        check(
            DashboardWidgetsEngine.widgetOrder(from: ["clock", "clock"]).filter { $0 == .clock }
                .count == 1,
            "a duplicate should be kept only once")

        let sep = DashboardMusicEngine.fieldSeparator
        let playing = DashboardMusicEngine.snapshot(
            fromScriptOutput: ["playing", "A1B2", "Weightless", "Marconi Union", "Ambient", "486.5"]
                .joined(separator: sep))
        check(playing.state == .playing && playing.isPlaying, "a playing line reads as playing")
        check(playing.track?.title == "Weightless", "the track's name survives the separator")
        check(playing.track?.duration == 486.5, "the duration parses as seconds")
        check(
            DashboardMusicEngine.subtitle(for: playing.track!) == "Marconi Union",
            "the second line is the artist")
        let paused = DashboardMusicEngine.snapshot(
            fromScriptOutput: ["paused", "A1B2", "Weightless", "", "Ambient", "486.5"]
                .joined(separator: sep))
        check(!paused.isPlaying && paused.track != nil, "a paused track is still a track")
        check(
            DashboardMusicEngine.subtitle(for: paused.track!) == "Ambient",
            "a track with no artist falls back to its album")
        check(
            DashboardMusicEngine.snapshot(fromScriptOutput: "stopped").track == nil,
            "a stopped player has no track")
        check(
            DashboardMusicEngine.snapshot(fromScriptOutput: "").track == nil,
            "an empty answer is not a track")
        check(
            DashboardMusicEngine.snapshot(fromScriptOutput: "playing\(sep)id").track == nil,
            "a truncated answer is not a track")
        check(
            DashboardMusicEngine.snapshot(
                fromScriptOutput: ["playing", "A1B2", "   ", "Artist", "Album", "10"]
                    .joined(separator: sep)).track == nil,
            "a nameless track is nothing to draw")

        check(
            DashboardMusicEngine.restingLine(isRunning: false) == "Music is not open"
                && DashboardMusicEngine.restingLine(isRunning: true) == "Nothing playing",
            "a closed player and an idle one say different things")

        let order: [DashboardWidgetKind] = [.clock, .music, .deviceBattery, .nextEvent, .fileInfo]
        check(
            DashboardWidgetsEngine.reorder(order, moving: .fileInfo, to: 0).first == .fileInfo,
            "moving to the front should put the widget first")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 4).last == .clock,
            "moving to the end should put the widget last")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 1)
                == [.music, .clock, .deviceBattery, .nextEvent, .fileInfo],
            "a downward move should land where the dragged row was dropped")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 0) == order,
            "moving onto its own position should change nothing")
        check(
            DashboardWidgetsEngine.reorder(order, moving: .clock, to: 9) == order,
            "an out-of-range destination should change nothing")
        check(
            Set(DashboardWidgetsEngine.reorder(order, moving: .nextEvent, to: 2)) == Set(order),
            "reordering should never add or drop a widget")

        // One shared location: a chosen city carries the zone the clock keeps.
        let berlin = city("Berlin", zone: "Europe/Berlin")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(for: berlin) == "Europe/Berlin",
            "a chosen city should hand the clock its own zone")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(for: city("Nowhere", zone: "Mars/Olympus"))
                == nil,
            "an unresolvable zone should never overwrite the clock's setting")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(for: city("Old", zone: nil)) == nil,
            "a city saved before the two shared a location names no zone")
        check(
            DashboardWeatherEngine.clockTimeZoneIdentifier(for: .default) == nil,
            "the fixed fallback city is a weather stand-in and must never retime the clock")
        check(
            DashboardWidgetsEngine.clockFollowsCity(
                cityTimeZoneIdentifier: "Europe/Berlin", clockTimeZoneIdentifier: "Europe/Berlin"),
            "a clock set to the city's zone is following the city")
        check(
            !DashboardWidgetsEngine.clockFollowsCity(
                cityTimeZoneIdentifier: nil, clockTimeZoneIdentifier: "Europe/Berlin"),
            "a city with no zone leaves the clock on its own setting")
        check(
            !DashboardWidgetsEngine.clockFollowsCity(
                cityTimeZoneIdentifier: "Europe/Berlin", clockTimeZoneIdentifier: nil),
            "a clock on System Default is not following a city")
        // 1_000_000_020 is a whole minute past the reference epoch; 1_000_000_000 is 40s short of it.
        let midMinute = Date(timeIntervalSinceReferenceDate: 1_000_000_000)
        check(
            DashboardWidgetsEngine.nextMinute(after: midMinute)
                == Date(timeIntervalSinceReferenceDate: 1_000_000_020),
            "the strip's tick lands on the next whole minute, not a minute later")
        check(
            DashboardWidgetsEngine.nextMinute(after: midMinute) > midMinute,
            "a tick is always in the future, so the schedule can never stall on one entry")
        check(
            DashboardWidgetsEngine.nextMinute(
                after: Date(timeIntervalSinceReferenceDate: 1_000_000_000.75))
                == Date(timeIntervalSinceReferenceDate: 1_000_000_020),
            "a fractional second is dropped rather than carried into the next tick")
        check(
            DashboardWidgetsEngine.nextMinute(after: midMinute)
                == DashboardWidgetsEngine.nextMinute(
                    after: Date(timeIntervalSinceReferenceDate: 1_000_000_019)),
            "two moments inside one minute tick at the same instant")
        check(
            DashboardWidgetsEngine.nextMinute(
                after: Date(timeIntervalSinceReferenceDate: 1_000_000_020))
                == Date(timeIntervalSinceReferenceDate: 1_000_000_080),
            "a moment already on the minute advances a whole minute rather than repeating itself")
        check(
            DashboardWidgetsEngine.nextMinute(
                after: Date(timeIntervalSinceReferenceDate: -30))
                == Date(timeIntervalSinceReferenceDate: 0),
            "a date before the reference epoch still rounds forward, never back")
        check(
            DashboardWidgetsEngine.locationSummary(
                cityLabel: nil, cityTimeZoneIdentifier: nil, clockTimeZoneIdentifier: nil,
                systemTimeZoneIdentifier: "Europe/Paris") == "System Default (Europe/Paris)",
            "with no city the summary is the clock's own zone")
        check(
            DashboardWidgetsEngine.locationSummary(
                cityLabel: nil, cityTimeZoneIdentifier: nil,
                clockTimeZoneIdentifier: "America/New_York",
                systemTimeZoneIdentifier: "Europe/Paris") == "America/New York",
            "a picked zone reads as words rather than an identifier")
        check(
            DashboardWidgetsEngine.locationSummary(
                cityLabel: "Berlin, Germany", cityTimeZoneIdentifier: "Europe/Berlin",
                clockTimeZoneIdentifier: "Europe/Berlin",
                systemTimeZoneIdentifier: "Europe/Paris") == "Berlin, Germany · Europe/Berlin",
            "one location serving both should read as one line")
        check(
            DashboardWidgetsEngine.locationSummary(
                cityLabel: "Berlin, Germany", cityTimeZoneIdentifier: nil,
                clockTimeZoneIdentifier: "Europe/Paris",
                systemTimeZoneIdentifier: "Europe/Paris")
                == "Berlin, Germany for the weather · clock on Europe/Paris",
            "a city the clock does not follow must not claim to be the clock's location")

        // File Info: what the square says about a Finder selection.
        check(DashboardFileInfoSnapshot().isEmpty, "no selection should read as empty")
        // The empty card draws its mark alone, so these lines are spoken rather than drawn — the
        // accessibility label is the one place they still name the source and the empty selection.
        check(
            DashboardFileInfoSnapshot().kindLine == "Finder",
            "an empty snapshot should name where it reads from")
        check(
            DashboardFileInfoSnapshot().nameLine == "No selection",
            "an empty snapshot should say so rather than go blank")
        check(
            DashboardFileInfoSnapshot().sizeLine.isEmpty,
            "an empty snapshot should have no size to state")
        check(
            DashboardFileInfoSnapshot().iconPath == nil,
            "an empty snapshot should have no file icon, so the card rests on a generic glyph")

        let png = fileItem("Shot.png", kind: "PNG image", bytes: 1_500_000)
        let shot = DashboardFileInfoSnapshot(items: [png])
        check(shot.kindLine == "PNG image", "one file should lead with its kind")
        check(shot.nameLine == "Shot.png", "one file should be named by its filename")
        check(shot.sizeLine.contains("MB"), "one file should state its size")
        check(shot.iconPath == "/tmp/Shot.png", "the icon should come from the item")

        let folder = DashboardFileInfoSnapshot(items: [folderItem("Docs", children: 12)])
        check(folder.sizeLine == "12 items", "a folder should be counted rather than weighed")
        check(
            DashboardFileInfoSnapshot(items: [folderItem("Docs", children: 1)]).sizeLine == "1 item",
            "a single child should be singular")
        check(
            DashboardFileInfoSnapshot(items: [folderItem("Locked", children: nil)]).sizeLine.isEmpty,
            "an unreadable folder should drop the size line rather than guess")

        let app = DashboardFileInfoSnapshot(items: [
            fileItem("Spotter", kind: "Application", bytes: 12_000_000, path: "/Applications/Spotter.app")
        ])
        check(app.kindLine == "Application", "a package should state its kind")
        check(app.sizeLine.contains("MB"), "a package should be weighed like a file")

        let many = DashboardFileInfoSnapshot(items: [
            fileItem("a.png", kind: "PNG image", bytes: 1_000_000),
            fileItem("b.png", kind: "PNG image", bytes: 2_000_000),
        ])
        check(many.kindLine == "Selection", "several items have no one kind to lead with")
        check(many.nameLine == "2 items", "several items should be named by their count")
        check(
            many.sizeLine == DashboardFileInfoSummary.size(bytes: 3_000_000),
            "several items should sum to one size")
        check(many.iconPath == "/tmp/a.png", "several items should borrow the first icon")

        let mixed = DashboardFileInfoSnapshot(items: [
            fileItem("a.png", kind: "PNG image", bytes: 1_000_000),
            folderItem("Docs", children: 3), folderItem("More", children: 4),
        ])
        check(
            mixed.sizeLine == DashboardFileInfoSummary.size(bytes: 1_000_000) + " · 2 folders",
            "a mixed total should name the folders it could not cover")
        check(
            DashboardFileInfoSnapshot(items: [
                fileItem("a.png", kind: "PNG image", bytes: 1), folderItem("Docs", children: 3),
            ]).sizeLine.hasSuffix("· 1 folder"),
            "one uncovered folder should be singular")
        check(
            DashboardFileInfoSnapshot(items: [
                folderItem("A", children: 1), folderItem("B", children: 2),
            ]).sizeLine == "2 folders",
            "an all-folder selection should state only the folder count")
        check(
            !mixed.accessibilityLabel.isEmpty && mixed.accessibilityLabel.contains(","),
            "the three lines should be spoken as one sentence")

        // Device battery: two scans merge into one card.
        check(
            DashboardDeviceBatteryEngine.kind(forMinorType: "Keyboard", productName: "")
                == .keyboard,
            "bluetoothd's minor type should decide the category outright")
        check(
            DashboardDeviceBatteryEngine.kind(forMinorType: "Headset", productName: "")
                == .headphones,
            "a headset is drawn as headphones")
        check(
            DashboardDeviceBatteryEngine.kind(forMinorType: "", productName: "Keyboard Craft")
                == .keyboard,
            "a missing minor type should fall back to the product name")
        check(
            DashboardDeviceBatteryEngine.kind(forProductName: "Bunny's AirPods") == .headphones,
            "AirPods read as headphones by name")
        check(
            DashboardDeviceBatteryEngine.normalizedAddress("C0:44:42:D9:F9:83")
                == "c0-44-42-d9-f9-83",
            "bluetoothd's address spelling should normalize to IOKit's")

        let profilerJSON = """
            {"SPBluetoothDataType":[{"device_connected":[
            {"Keyboard Craft":{"device_address":"F5:B7:55:5E:72:17",
            "device_batteryLevelMain":"100%","device_minorType":"Keyboard"}},
            {"Quiet Mouse":{"device_address":"C0:44:42:D9:F9:83","device_minorType":"Mouse"}},
            {"AirPods Pro":{"device_address":"14:88:E6:AC:7F:37","device_batteryLevelLeft":"80%",
            "device_batteryLevelRight":"75%","device_batteryLevelCase":"5%",
            "device_minorType":"Headphones"}}],
            "device_not_connected":[{"Old Keyboard":{"device_address":"AA:BB:CC:DD:EE:FF",
            "device_batteryLevelMain":"50%"}}]}]}
            """.data(using: .utf8)!
        let bluetooth = DashboardDeviceBatteryEngine.bluetoothDevices(
            fromProfilerJSON: profilerJSON)
        check(
            bluetooth.count == 2,
            "only connected devices that report a level should be read")
        check(
            bluetooth.contains {
                $0.kind == .keyboard && $0.percent == 100 && $0.id == "f5-b7-55-5e-72-17"
            },
            "a keyboard's main level and normalized address should come through")
        check(
            bluetooth.contains { $0.kind == .headphones && $0.percent == 75 },
            "earbuds should read as their lowest bud, with the case ignored")
        check(
            bluetooth.allSatisfy { !$0.isCharging },
            "bluetoothd reports no charging state, so no bolt")
        check(
            DashboardDeviceBatteryEngine.bluetoothDevices(fromProfilerJSON: Data()).isEmpty,
            "unparseable profiler output should read as no devices")

        let hidMouse = DeviceBattery(
            id: "c0-44-42-d9-f9-83", productName: "Magic Mouse", kind: .mouse, percent: 85,
            isCharging: true)
        let merged = DashboardDeviceBatteryEngine.merged(hid: [hidMouse], bluetooth: bluetooth)
        check(
            merged.count == 3,
            "the Bluetooth scan should add only devices the HID scan didn't find")
        check(
            merged.contains { $0.id == "c0-44-42-d9-f9-83" && $0.isCharging },
            "a device both scans found should keep the HID reading and its charging flag")
        check(
            merged.first?.kind == .headphones,
            "the merged list should stay ordered lowest-first")

        check(DashboardFileInfoSummary.size(bytes: 512).contains("512"), "bytes should stay bytes")
        check(DashboardFileInfoSummary.size(bytes: 1_000).contains("KB"), "kilobytes are file-style")
        check(
            DashboardFileInfoSummary.size(bytes: 5_000_000_000).contains("GB"),
            "gigabytes are file-style")
        check(
            DashboardFileInfoSummary.size(bytes: -5) == DashboardFileInfoSummary.size(bytes: 0),
            "a negative size can only be a bad read, so it floors at zero")

        print(failures == 0 ? "Dashboard widgets tests passed" : "\(failures) test(s) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    private static func fileItem(
        _ name: String, kind: String, bytes: Int64, path: String? = nil
    ) -> DashboardFileInfoItem {
        DashboardFileInfoItem(
            path: path ?? "/tmp/\(name)", name: name, kind: kind, byteCount: bytes,
            childCount: nil)
    }

    private static func folderItem(_ name: String, children: Int?) -> DashboardFileInfoItem {
        DashboardFileInfoItem(
            path: "/tmp/\(name)", name: name, kind: "Folder", byteCount: nil,
            childCount: children)
    }

    private static func city(_ name: String, zone: String?) -> WeatherCity {
        WeatherCity(
            id: name.hashValue, name: name, latitude: 0, longitude: 0, country: nil, region: nil,
            timeZoneIdentifier: zone)
    }

    private static func near(_ value: Double, _ expected: Double) -> Bool {
        abs(value - expected) < 0.0001
    }

    private static func battery(
        _ productName: String, _ percent: Int, id: String = "id", charging: Bool = false
    ) -> DeviceBattery {
        DeviceBattery(
            id: id, productName: productName,
            kind: DashboardDeviceBatteryEngine.kind(forProductName: productName), percent: percent,
            isCharging: charging)
    }

    private static func date(_ stamp: String, _ calendar: Calendar) -> Date {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: stamp)!
    }
}
