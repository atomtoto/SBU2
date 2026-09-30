//
//  SBU2App.swift
//  SBU2
//

import SwiftUI
import UIKit

@main
struct SBU2App: App {
    /// Only there to answer the iPhone orientation question.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var connection = BMSConnection()
    @State private var appSettings = AppSettings()
    @State private var iCloudSync = ICloudSettingsSync.shared

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environment(connection)
                .environment(appSettings)
                .environment(iCloudSync)
                .preferredColorScheme(colorScheme)
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
                .onChange(of: appSettings.keepScreenAwake, initial: true) { _, keepAwake in
                    #if !targetEnvironment(macCatalyst)
                    UIApplication.shared.isIdleTimerDisabled = keepAwake
                    #endif
                }
                .onChange(of: appSettings.snapshot) { _, _ in
                    appSettings.persist()
                }
        }
        #if targetEnvironment(macCatalyst)
        WindowGroup("Settings", id: "app-settings", for: String.self) { _ in
            NavigationStack {
                AppSettingsView()
            }
            .environment(appSettings)
            .environment(iCloudSync)
            .preferredColorScheme(colorScheme)
            .task { iCloudSync.start() }
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
        }
        .defaultSize(width: 680, height: 680)
        .commands {
            CommandGroup(replacing: .appSettings) {
                OpenAppSettingsCommand()
            }
        }
        #endif
    }

    private var colorScheme: ColorScheme? {
        switch appSettings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

#if targetEnvironment(macCatalyst)
private struct OpenAppSettingsCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: "app-settings", value: "app-settings")
        }
        .keyboardShortcut(",", modifiers: .command)
    }
}
#endif
