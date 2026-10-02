import Foundation
import Observation

/// Process-wide services: CarPlay can launch without creating an iPhone window.
@MainActor
@Observable
final class AppRuntime {
    static let shared = AppRuntime()

    let connection = BMSConnection()
    let appSettings = AppSettings()
    let iCloudSync = ICloudSettingsSync.shared
    var isCarPlayConnected = false

    @ObservationIgnored private var settingsObserver: NSObjectProtocol?
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        iCloudSync.start()
        reloadSettings()
        settingsObserver = NotificationCenter.default.addObserver(
            forName: ICloudSettingsSync.didChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reloadSettings() }
        }
    }

    private func reloadSettings() {
        appSettings.reload()
        connection.reloadSavedSettings()
        connection.setShowDemoDevice(appSettings.showDemoDevice)
    }
}
