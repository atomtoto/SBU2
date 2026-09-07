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
                .tabItem { Label("Overview", systemImage: "chart.bar.doc.horizontal.fill") }

            if connection.settings.kind == .vehicle {
                GPSView()
                    .navigationTitle(deviceName)
                    .navigationBarTitleDisplayMode(.inline)
                    .tabItem { Label("GPS", systemImage: Self.gpsSymbol) }
            }

            DeviceSettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
        .onChange(of: connection.settings) { _, _ in
            connection.saveSettings()
        }
    }

    /// SBU switched to the newer symbol once it became available.
    private static var gpsSymbol: String {
        if #available(iOS 18.0, *) {
            return "powermeter"
        }
        return "location.north.line.fill"
    }
}
