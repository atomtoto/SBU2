#if os(iOS) && !targetEnvironment(macCatalyst)
import CarPlay
import UIKit

@MainActor
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private let runtime = AppRuntime.shared
    private var interfaceController: CPInterfaceController?
    private var tabs: CPTabBarTemplate?
    private var dashboard: CPListTemplate?
    private var devices: CPListTemplate?
    private var timer: Timer?
    private var dashboardItems: [CPListItem] = []
    private var lastSnapshot: CarPlayDashboardSnapshot?
    private var lastDevices: [DeviceEntry] = []
    private var lastDeviceStatus: String?
    private var hasAutoConnected = false

    private struct DeviceEntry: Equatable {
        let id: String
        let name: String
        let detail: String
        let isDemo: Bool
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController) {
        runtime.start()
        runtime.isCarPlayConnected = true
        runtime.iCloudSync.synchronize()
        self.interfaceController = interfaceController
        let dashboard = CPListTemplate(title: "Battery", sections: [])
        dashboard.tabTitle = "Battery"
        dashboard.tabImage = UIImage(systemName: "battery.100percent")
        let devices = CPListTemplate(title: "Devices", sections: [])
        devices.tabTitle = "Devices"
        devices.tabImage = UIImage(systemName: "antenna.radiowaves.left.and.right")
        self.dashboard = dashboard
        self.devices = devices
        let tabs = CPTabBarTemplate(templates: [dashboard, devices])
        self.tabs = tabs
        refresh()
        interfaceController.setRootTemplate(tabs, animated: false, completion: nil)
        tabs.select(runtime.connection.openDeviceID == nil ? devices : dashboard)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnectInterfaceController interfaceController: CPInterfaceController) {
        timer?.invalidate()
        timer = nil
        self.interfaceController = nil
        tabs = nil
        dashboard = nil
        devices = nil
        dashboardItems = []
        lastSnapshot = nil
        lastDevices = []
        lastDeviceStatus = nil
        runtime.isCarPlayConnected = false
        // The iPhone may still be displaying this pack: disconnecting the car
        // releases its UI, rather than closing the shared Bluetooth connection.
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        runtime.iCloudSync.synchronize()
        refresh()
    }

    private func refresh() {
        let connection = runtime.connection
        if connection.openDeviceID != nil { hasAutoConnected = true }
        if !hasAutoConnected, connection.openDeviceID == nil,
           let target = connection.autoConnectTarget {
            hasAutoConnected = true
            connection.open(target)
            if let dashboard { tabs?.select(dashboard) }
        }
        refreshDashboard()
        refreshDevices()
    }

    private func refreshDashboard() {
        guard let dashboard else { return }
        let connection = runtime.connection
        guard let id = connection.openDeviceID else {
            if !dashboardItems.isEmpty || dashboard.sections.isEmpty {
                dashboard.updateSections([CPListSection(items: [CPListItem(
                    text: "No BMS selected", detailText: "Choose a battery in Devices.")])])
                dashboardItems = []
                lastSnapshot = nil
            }
            return
        }
        let device = connection.discovered.first { $0.id == id }
        let name = connection.settings.name.isEmpty
            ? (device.map { connection.displayName(for: $0) } ?? "BMS") : connection.settings.name
        let snapshot = CarPlayDashboardSnapshot(
            deviceName: name, status: connection.status, isDemo: connection.isDemoOpen,
            isReconnecting: connection.isReconnecting, hasReading: connection.hasReading,
            lastBasicInfoAt: connection.lastBasicInfoAt, info: connection.info,
            remainingHours: connection.remainingHours, capacityUnit: runtime.appSettings.capacityUnit,
            cellNominalMillivolts: connection.settings.cellNominalVoltage,
            lastError: connection.lastError, now: .now)
        guard snapshot != lastSnapshot else { return }
        let rows = Array(snapshot.rows.prefix(CPListTemplate.maximumItemCount))
        if dashboardItems.count != rows.count {
            dashboardItems = rows.map {
                CPListItem(text: $0.title, detailText: $0.detail, image: UIImage(systemName: $0.symbol))
            }
            dashboard.updateSections([CPListSection(items: dashboardItems)])
        } else {
            for (item, row) in zip(dashboardItems, rows) {
                if item.text != row.title { item.setText(row.title) }
                if item.detailText != row.detail { item.setDetailText(row.detail) }
                item.setImage(UIImage(systemName: row.symbol))
            }
        }
        lastSnapshot = snapshot
    }

    private func refreshDevices() {
        guard let devices else { return }
        let connection = runtime.connection
        let entries = connection.discovered.map { device in
            DeviceEntry(id: device.id, name: connection.displayName(for: device),
                        detail: connection.openDeviceID == device.id ? "Selected"
                            : (device.isDemo ? "Simulated values" : "Connect"), isDemo: device.isDemo)
        }
        let status: String
        switch connection.status {
        case .bluetoothOff: status = "Bluetooth is turned off"
        case .unauthorized: status = "Bluetooth access denied"
        case .unsupported: status = "Bluetooth LE unavailable"
        default: status = connection.lastError ?? "Scanning for batteries…"
        }
        let deviceStatus = status + (connection.openDeviceID ?? "")
        guard entries != lastDevices || deviceStatus != lastDeviceStatus || devices.sections.isEmpty else { return }
        lastDevices = entries
        lastDeviceStatus = deviceStatus
        let items = entries.prefix(CPListTemplate.maximumItemCount).map { entry in
            let item = CPListItem(text: entry.name, detailText: entry.detail,
                                  image: UIImage(systemName: entry.isDemo ? "flask" : "battery.100percent"))
            item.accessoryType = .disclosureIndicator
            item.handler = { [weak self] _, completion in
                defer { completion() }
                guard let self,
                      let device = self.runtime.connection.discovered.first(where: { $0.id == entry.id }) else { return }
                self.hasAutoConnected = true
                if self.runtime.connection.openDeviceID != device.id { self.runtime.connection.open(device) }
                self.refresh()
                if let dashboard = self.dashboard { self.tabs?.select(dashboard) }
            }
            return item
        }
        devices.updateSections([CPListSection(items: items.isEmpty
            ? [CPListItem(text: status, detailText: "Check the BMS Bluetooth module.")] : items)])
        let isOpen = connection.openDeviceID != nil
        devices.trailingNavigationBarButtons = [CPBarButton(title: isOpen ? "Disconnect" : "Scan") { [weak self] _ in
            guard let self else { return }
            self.hasAutoConnected = true
            if self.runtime.connection.openDeviceID != nil {
                self.runtime.connection.close()
            } else {
                self.runtime.connection.startScanning()
            }
            self.refresh()
        }]
    }
}
#endif
