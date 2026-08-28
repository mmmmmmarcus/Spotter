import Combine
import Foundation
import IOKit

/// Backs the device-battery card: what the connected peripherals report. Two reads feed it —
/// the IOKit registry for HID devices and bluetoothd (via one `system_profiler` subprocess) for the
/// BLE peripherals that publish nothing there — and `DashboardDeviceBatteryEngine` stays pure, hands
/// back the merged list and is handed finished values.
///
/// Unlike the weather card this needs no consent gate. Any process can read the registry, and
/// `system_profiler` only relays what bluetoothd already knows — no TCC prompt, no entitlement, no
/// Bluetooth framework (that one requires `NSBluetoothAlwaysUsageDescription` and prompts the user,
/// which is why IOBluetooth stays off-limits). Nothing is stored and nothing leaves the machine.
@MainActor
final class DashboardDeviceBatteryStore: ObservableObject {
    @Published private(set) var devices: [DeviceBattery] = []

    /// Levels move in whole percent over hours, so the card only needs a slow poll while it's on
    /// screen; a connect or disconnect lands on the next palette open, which restarts the loop.
    private static let refreshInterval: TimeInterval = 60

    /// The Bluetooth read is a ~0.2 s subprocess and `refresh()` runs on every palette open, so a
    /// recent answer is reused rather than paying that per summon. Half the poll interval: fresh
    /// enough that a newly connected device lands within a summon or two.
    private static let bluetoothReuseWindow: Duration = .seconds(30)

    /// Every HID peripheral that reports a level hangs off one of these, whatever the transport.
    private nonisolated static let serviceClass = "AppleDeviceManagementHIDEventService"

    private var refreshTask: Task<Void, Never>?
    private var hidDevices: [DeviceBattery] = []
    private var bluetoothDevices: [DeviceBattery] = []
    private var bluetoothTask: Task<Void, Never>?
    private var bluetoothScannedAt: ContinuousClock.Instant?

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
        bluetoothTask?.cancel()
        bluetoothTask = nil
    }

    /// The registry half is synchronous on the main actor deliberately: that scan is a handful of
    /// property reads, measured at ~0.03 ms, so hopping off and back would cost more than it saves.
    /// The Bluetooth half is a subprocess, so it lands when it lands and re-publishes then.
    func refresh() {
        hidDevices = Self.scan()
        publishMerged()
        refreshBluetooth()
    }

    /// One read in flight at a time — a poll that fires mid-read would only duplicate it — and a
    /// recent answer is reused instead of respawning `system_profiler` on every palette open.
    private func refreshBluetooth() {
        guard bluetoothTask == nil else { return }
        if let scannedAt = bluetoothScannedAt,
            scannedAt.duration(to: .now) < Self.bluetoothReuseWindow
        { return }
        bluetoothTask = Task { [weak self] in
            let scanned = await Self.bluetoothScan()
            guard let self else { return }
            self.bluetoothTask = nil
            guard !Task.isCancelled else { return }
            self.bluetoothScannedAt = .now
            self.bluetoothDevices = scanned
            self.publishMerged()
        }
    }

    private func publishMerged() {
        let merged = DashboardDeviceBatteryEngine.merged(
            hid: hidDevices, bluetooth: bluetoothDevices)
        guard merged != devices else { return }
        devices = merged
    }

    /// What bluetoothd holds for connected BLE peripherals — a keyboard reporting through the
    /// battery GATT service publishes nothing in the IOKit registry, so the HID scan can't see it.
    /// `system_profiler` is the unrestricted route to bluetoothd's answer.
    private nonisolated static func bluetoothScan() async -> [DeviceBattery] {
        await Task.detached(priority: .utility) {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]
            process.standardOutput = output
            process.standardError = Pipe()
            guard (try? process.run()) != nil else { return [] }
            // Drained before the wait, like FinderSelection: waiting first can block on a child
            // that is itself blocked writing a report larger than the pipe buffer.
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
            return DashboardDeviceBatteryEngine.bluetoothDevices(fromProfilerJSON: data)
        }.value
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
