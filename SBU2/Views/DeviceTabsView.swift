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
    @State private var selectedTab: DeviceTab = .overview
    @State private var gpsFullscreen = false
    @State private var isLandscape = false

    let deviceName: String

    var body: some View {
        TabView(selection: $selectedTab) {
            OverviewView()
                .navigationTitle(deviceName)
                .navigationBarTitleDisplayMode(.inline)
                .tabItem { Label("Overview", systemImage: "chart.bar.doc.horizontal.fill") }
                .tag(DeviceTab.overview)

            if connection.settings.kind == .vehicle {
                GPSView(isLandscapeFullscreen: $gpsFullscreen)
                    .navigationTitle(deviceName)
                    .navigationBarTitleDisplayMode(.inline)
                    .tabItem { Label("GPS", systemImage: Self.gpsSymbol) }
                    .tag(DeviceTab.gps)
            }

            DeviceSettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(DeviceTab.more)
        }
        .toolbar {
            if selectedTab == .gps && isLandscape {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy(duration: 0.3)) {
                            gpsFullscreen.toggle()
                        }
                    } label: {
                        Image(systemName: gpsFullscreen
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                    .accessibilityLabel(gpsFullscreen
                                        ? "Exit full screen"
                                        : "Enter full screen")
                }
            }
        }
        .onGeometryChange(for: Bool.self) { proxy in
            proxy.size.width > proxy.size.height
        } action: { landscape in
            isLandscape = landscape
            if !landscape {
                gpsFullscreen = false
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab != .gps {
                gpsFullscreen = false
            }
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

private enum DeviceTab: Hashable {
    case overview, gps, more
}
