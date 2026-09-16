import Combine

@MainActor
enum DashboardBatteryScreen {
    static func registration(core: AppCore) -> PluginPaletteScreenRegistration {
        PluginPaletteScreenRegistration(
            placeholder: "Filter devices by name or type…",
            snapshot: { [weak core] query in
                let devices = core?.dashboardDeviceBattery.devices ?? []
                let filtered = DashboardDeviceBatteryEngine.filtered(devices, query: query)
                return PluginPaletteSnapshot(
                    sectionTitle: "Device Batteries",
                    items: filtered.map { device in
                        PluginPaletteItem(
                            id: device.id,
                            title: device.productName.isEmpty
                                ? DashboardDeviceBatteryEngine.label(for: device) : device.productName,
                            subtitle: device.kind.noun + (device.isCharging ? " · Charging" : ""),
                            icon: .symbol(device.kind.systemImage),
                            accessories: [
                                PluginPaletteAccessory(
                                    systemImage: device.isCharging ? "bolt.fill" : "battery.100percent",
                                    text: "\(DashboardDeviceBatteryEngine.clampedPercent(device.percent))%")
                            ],
                            primaryActionTitle: "Copy Battery Info")
                    },
                    emptyMessage: devices.isEmpty
                        ? "No devices reporting battery levels" : "No matching devices")
            },
            performPrimaryAction: { [weak core] id in
                guard let device = core?.dashboardDeviceBattery.devices.first(where: { $0.id == id }) else {
                    return
                }
                Paster.copyPlainText(DashboardDeviceBatteryEngine.accessibilityLabel(for: [device]))
            },
            actions: { [weak core] _ in
                PopoverMenuContent(
                    header: "Battery",
                    items: [
                        PopoverMenuItem(title: "Refresh", systemImage: "arrow.clockwise") {
                            core?.dashboardDeviceBattery.refresh()
                        }
                    ])
            },
            onOpen: { [weak core] in core?.dashboardDeviceBattery.start(reader: .list) },
            onClose: { [weak core] in core?.dashboardDeviceBattery.stop(reader: .list) },
            observeChanges: { [weak core] invalidate in
                core?.dashboardDeviceBattery.objectWillChange.sink { invalidate() } ?? AnyCancellable {}
            })
    }
}
