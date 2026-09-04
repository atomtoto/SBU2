//
//  SBU2App.swift
//  SBU2
//

import SwiftUI

@main
struct SBU2App: App {
    @State private var connection = BMSConnection()

    var body: some Scene {
        WindowGroup {
            ScanView()
                .environment(connection)
        }
    }
}
