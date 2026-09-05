//
//  DeviceTabsView.swift
//  SBU2
//

import SwiftUI

/// The tabs shown once a pack is open. Which tabs exist depends on the device type,
/// exactly as in SBU.
///
/// The tabs deliberately do not nest their own `NavigationStack`: this view is already
/// pushed onto the device list's stack, so drill-downs from the settings tab push there
/// and the back button keeps working all the way out to the list.
struct DeviceTabsView: View {
    @Environment(BMSConnection.self) private var connection

    let deviceName: String

    var body: some View {
        TabView {
            OverviewView()
                .navigationTitle(deviceName)
                .navigationBarTitleDisplayMode(.inline)
                .tabItem { Label("Overview", systemImage: "chart.bar.doc.horizontal") }

            if connection.settings.kind == .vehicle {
                TripView()
                    .navigationTitle("Trajet")
                    .navigationBarTitleDisplayMode(.inline)
                    .tabItem { Label("Trajet", systemImage: "location.north.line.fill") }
            }

            DeviceSettingsView()
                .tabItem { Label("Réglages", systemImage: "slider.horizontal.3") }
        }
        .onChange(of: connection.settings) { _, _ in
            connection.saveSettings()
        }
    }
}
