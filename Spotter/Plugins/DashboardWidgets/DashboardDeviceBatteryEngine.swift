import Foundation

/// What a connected peripheral reports. Deliberately not the Mac's own battery: that already has a
/// menu-bar item, and a laptop's percentage next to a mouse's would read as the same kind of thing.
struct DeviceBattery: Equatable, Identifiable, Sendable {
    let id: String
    let productName: String
    let kind: DeviceBatteryKind
    let percent: Int
    let isCharging: Bool
}

enum DeviceBatteryKind: String, CaseIterable, Equatable, Sendable {
    case mouse
    case keyboard
    case trackpad
    case other

    /// The noun the card uses in place of the full product name, which is usually the owner's —
    /// "Marcus's Magic Mouse" never fits a 116-point square.
    var noun: String {
        switch self {
        case .mouse: return "Mouse"
        case .keyboard: return "Keyboard"
        case .trackpad: return "Trackpad"
        case .other: return "Device"
        }
    }

    /// `trackpad` is not an SF Symbol on macOS 26, so the pointing hand stands in for it.
    var systemImage: String {
        switch self {
        case .mouse: return "computermouse.fill"
        case .keyboard: return "keyboard.fill"
        case .trackpad: return "rectangle.and.hand.point.up.left.fill"
        case .other: return "battery.100percent"
        }
    }
}

/// One position in the card's gauge grid. The overflow slot exists so a fifth device is counted
/// rather than silently missing from a grid that has no room for it; the empty slot keeps the grid
/// four squares whatever is connected, so one device sits where one device sits rather than sliding
/// into the middle of the card.
enum DeviceBatterySlot: Equatable, Identifiable, Sendable {
    case device(DeviceBattery)
    case overflow(Int)
    case empty(Int)

    var id: String {
        switch self {
        case .device(let device): return device.id
        case .overflow(let count): return "overflow-\(count)"
        case .empty(let index): return "empty-\(index)"
        }
    }

    var isCharging: Bool {
        guard case .device(let device) = self else { return false }
        return device.isCharging
    }
}

enum DashboardDeviceBatteryEngine {
    /// Under this the card turns its headline red. Matches where macOS itself starts warning.
    static let lowThreshold = 20

    /// Apple names a paired device after its owner ("Marcus's Magic Mouse"), so the product string
    /// can't be matched whole — the category noun inside it is the stable part. Anything else keeps
    /// its own name rather than being guessed at from a vendor/product table that would rot.
    static func kind(forProductName name: String) -> DeviceBatteryKind {
        let lowercased = name.lowercased()
        if lowercased.contains("trackpad") { return .trackpad }
        if lowercased.contains("keyboard") { return .keyboard }
        if lowercased.contains("mouse") { return .mouse }
        return .other
    }

    /// A reported level outside 0–100 is a device lying rather than a device to hide, so it clamps.
    static func clampedPercent(_ percent: Int) -> Int { min(100, max(0, percent)) }

    static func isLow(_ percent: Int) -> Bool { percent < lowThreshold }

    /// The short label: the category noun, or the product's own name when it isn't one Spotter knows.
    static func label(for device: DeviceBattery) -> String {
        device.kind == .other ? device.productName : device.kind.noun
    }

    static func percentLabel(_ percent: Int) -> String { "\(clampedPercent(percent))%" }

    /// Lowest first — the card headlines whichever device needs charging soonest. Name and then id
    /// break ties so two devices at the same level can't swap places between scans.
    static func ordered(_ devices: [DeviceBattery]) -> [DeviceBattery] {
        devices.sorted {
            if $0.percent != $1.percent { return $0.percent < $1.percent }
            let left = label(for: $0)
            let right = label(for: $1)
            if left != right { return left < right }
            return $0.id < $1.id
        }
    }

    /// How many gauges the square seats before the last one has to stand for the rest.
    static let gaugeSlotLimit = 4

    /// The grid's contents: always `limit` slots. Under it the remainder are empty rings, so the
    /// grid is the same shape whether one device is connected or four and a device keeps its
    /// position as others come and go; over it, the last slot counts what didn't fit rather than
    /// dropping those devices unremarked.
    static func gaugeSlots(for devices: [DeviceBattery], limit: Int) -> [DeviceBatterySlot] {
        guard limit >= 2 else { return devices.prefix(max(0, limit)).map(DeviceBatterySlot.device) }
        guard devices.count > limit else {
            let shown = devices.map(DeviceBatterySlot.device)
            return shown + (shown.count..<limit).map(DeviceBatterySlot.empty)
        }
        let shown = devices.prefix(limit - 1)
        return shown.map(DeviceBatterySlot.device) + [.overflow(devices.count - shown.count)]
    }

    /// Two columns always: the grid is a fixed four squares, so a lone device no longer grows to fill
    /// the card — it stays the size it will be when a second one connects.
    static func gaugeColumns(slotCount: Int) -> Int { slotCount <= 1 ? 1 : 2 }

    static func gaugeRows(for slots: [DeviceBatterySlot], columns: Int) -> [[DeviceBatterySlot]] {
        guard columns > 0 else { return [] }
        return stride(from: 0, to: slots.count, by: columns).map {
            Array(slots[$0..<min($0 + columns, slots.count)])
        }
    }

    /// The largest circle that fits every slot in `interior` points both ways — the binding direction
    /// is whichever of columns or rows is longer, so three devices size to their two rows.
    static func gaugeDiameter(slotCount: Int, interior: Double, spacing: Double) -> Double {
        guard slotCount > 0 else { return 0 }
        let columns = Double(gaugeColumns(slotCount: slotCount))
        let rows = (Double(slotCount) / columns).rounded(.up)
        let width = (interior - spacing * (columns - 1)) / columns
        let height = (interior - spacing * (rows - 1)) / rows
        return max(0, min(width, height))
    }

    /// How far the arc sweeps, 0 to 1.
    static func gaugeFraction(_ percent: Int) -> Double { Double(clampedPercent(percent)) / 100 }

    /// The HID service publishes no explicit charging key — only `BatteryStatusFlags`, whose bit 0 is
    /// set on a cabled device and clear on one running off its battery. Read that bit alone: the rest
    /// of the word is undocumented, and "on external power" is exactly what a bolt claims, the same
    /// thing the menu-bar bolt means.
    static func isOnExternalPower(statusFlags: Int) -> Bool { statusFlags & 0x01 != 0 }

    static func accessibilityLabel(for devices: [DeviceBattery]) -> String {
        guard !devices.isEmpty else { return "No device batteries" }
        let readings = devices.map {
            "\(label(for: $0)) \(clampedPercent($0.percent)) percent"
                + ($0.isCharging ? ", charging" : "")
        }
        return "Battery: \(readings.joined(separator: ", "))"
    }
}
