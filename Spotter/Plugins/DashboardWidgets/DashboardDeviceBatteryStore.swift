import Combine
import Foundation
import IOKit

/// Backs the device-battery card: what the connected mice, keyboards and trackpads report.
/// `DashboardDeviceBatteryEngine` stays pure and is handed finished values; the IOKit read lives here.
///
/// Unlike the weather card this needs no consent gate. The levels come from the IOKit
/// registry, which any process can read — no TCC prompt, no entitlement, no Bluetooth framework (that
/// one requires `NSBluetoothAlwaysUsageDescription` and prompts the user, which is why AirPods, being
/// non-HID, are deliberately out of scope). Nothing is stored and nothing leaves the machine.
@MainActor
final class DashboardDeviceBatteryStore: ObservableObject {
    @Published private(set) var devices: [DeviceBattery] = []

    /// Levels move in whole percent over hours, so the card only needs a slow poll while it's on
    /// screen; a connect or disconnect lands on the next palette open, which restarts the loop.
    private static let refreshInterval: TimeInterval = 60

    /// Every HID peripheral that reports a level hangs off one of these, whatever the transport.
    private nonisolated static let serviceClass = "AppleDeviceManagementHIDEventService"

    private var refreshTask: Task<Void, Never>?

    /// Driven by the dashboard's appearance, like `DashboardWidgetsStore` — the palette is the only
    /// place these levels are drawn, so nothing polls while it is closed.
    func start() {
        guard refreshTask == nil else { return }
        refresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(Self.refreshInterval))
                } catch {
                    break
                }
                self?.refresh()
            }
        }
    }

    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Synchronous on the main actor deliberately: the scan is a handful of registry property reads,
    /// measured at ~0.03 ms, so hopping off and back would cost more than it saves.
    func refresh() {
        let scanned = Self.scan()
        guard scanned != devices else { return }
        devices = scanned
    }

    /// Reads every HID peripheral publishing `BatteryPercent`. Devices without one — a built-in
    /// keyboard, anything that doesn't report — simply aren't in the iterator.
    nonisolated static func scan() -> [DeviceBattery] {
        var iterator: io_iterator_t = 0
        guard
            IOServiceGetMatchingServices(
                kIOMainPortDefault, IOServiceMatching(serviceClass), &iterator) == KERN_SUCCESS
        else {
            AppLog.error("DashboardWidgets", "Battery scan could not match \(serviceClass)")
            return []
        }
        defer { IOObjectRelease(iterator) }

        var found: [DeviceBattery] = []
        var seen: Set<String> = []
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            guard let percent = property(service, "BatteryPercent") as? Int else { continue }
            let productName =
                (property(service, "Product") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            // The address is stable across reconnects; the name is the last resort so a device that
            // reports neither still gets a key rather than colliding on an empty string.
            let identifier =
                (property(service, "DeviceAddress") as? String)
                ?? (property(service, "SerialNumber") as? String)
                ?? productName
            guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
            // Absent flags read as zero, which is "on its own battery" — the bolt is the claim that
            // needs evidence, so a device that reports nothing doesn't get one.
            let statusFlags = property(service, "BatteryStatusFlags") as? Int ?? 0
            found.append(
                DeviceBattery(
                    id: identifier, productName: productName,
                    kind: DashboardDeviceBatteryEngine.kind(forProductName: productName),
                    percent: DashboardDeviceBatteryEngine.clampedPercent(percent),
                    isCharging: DashboardDeviceBatteryEngine.isOnExternalPower(
                        statusFlags: statusFlags)))
        }
        return DashboardDeviceBatteryEngine.ordered(found)
    }

    private nonisolated static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
