import SwiftUI

@main
struct SBU2WatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var connection = BMSConnection()
    @State private var appSettings = AppSettings()
    @State private var iCloudSync = ICloudSettingsSync.shared

    var body: some Scene {
        WindowGroup {
            WatchDeviceListView()
                .environment(connection)
                .environment(appSettings)
                .environment(iCloudSync)
                .task {
                    iCloudSync.start()
                    appSettings.reload()
                    connection.reloadSavedSettings()
                }
                .onReceive(NotificationCenter.default.publisher(for: ICloudSettingsSync.didChange)) { _ in
                    appSettings.reload()
                    connection.reloadSavedSettings()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { iCloudSync.synchronize() }
                }
                .onChange(of: appSettings.snapshot) { _, _ in
                    appSettings.persist()
                }
                .onChange(of: appSettings.showDemoDevice, initial: true) { _, show in
                    connection.setShowDemoDevice(show)
                }
        }
    }
}
