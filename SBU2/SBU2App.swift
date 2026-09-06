//
//  SBU2App.swift
//  SBU2
//

import SwiftUI
import UIKit

@main
struct SBU2App: App {
    /// Only there to answer the orientation question: portrait everywhere but GPS.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var connection = BMSConnection()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            DeviceListView()
                .environment(connection)
                .environment(appSettings)
                .preferredColorScheme(colorScheme)
                .onChange(of: appSettings.keepScreenAwake, initial: true) { _, keepAwake in
                    UIApplication.shared.isIdleTimerDisabled = keepAwake
                }
                .onChange(of: appSettings.snapshot) { _, _ in
                    appSettings.persist()
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appSettings.appearance {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
