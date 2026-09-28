import SwiftUI

@main
struct SBU2WatchApp: App {
    @State private var connection = BMSConnection()

    var body: some Scene {
        WindowGroup {
            WatchDeviceListView()
                .environment(connection)
        }
    }
}
