//
//  PasswordSettingsView.swift
//  SBU2
//

import SwiftUI

/// Hardware password management, ported from SBU's PasswordSettings.
///
/// A protected pack rejects every write until the password is entered, so the app
/// stores it and replays it before each factory-mode write.
struct PasswordSettingsView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var newPassword = ""

    var body: some View {
        @Bindable var connection = connection

        Form {
            Section {
                Toggle("Has password", isOn: $connection.settings.hasPassword)
                if connection.settings.hasPassword {
                    LabeledContent("Password") {
                        TextField("000000", text: $connection.settings.password)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                }
            } header: {
                Text("Current password")
            } footer: {
                Text(currentValid
                     ? "It is sent again automatically before every write."
                     : "Configuration invalid. Passwords need to have 6 digits.")
                    .foregroundStyle(currentValid ? Color.secondary : Color.red)
            }

            Section {
                LabeledContent("New Password") {
                    TextField("000000", text: $newPassword)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                }
                Button(connection.settings.hasPassword ? "Update Password" : "Create Password") {
                    if connection.settings.hasPassword {
                        connection.changePassword(to: newPassword)
                    } else {
                        connection.createPassword(newPassword)
                    }
                    newPassword = ""
                }
                .disabled(!canSubmit)

                Button("Remove password", role: .destructive) {
                    connection.removePassword()
                }
                .disabled(!connection.settings.hasPassword || !currentValid)
            } header: {
                Text("Change Password")
            } footer: {
                Text("These commands are written to the BMS. Write the password down: there is no way to recover it from the app.")
            }

            switch connection.passwordOutcome {
            case .succeeded:
                Section {
                    Label("The BMS accepted the command.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .rejected(let message):
                Section {
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            case .idle:
                EmptyView()
            }
        }
        .navigationTitle("Password")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { normalisePassword(&connection.settings) }
    }

    private var currentValid: Bool {
        !connection.settings.hasPassword || JBD.isValidPassword(connection.settings.password)
    }

    private var canSubmit: Bool {
        JBD.isValidPassword(newPassword) && currentValid
    }

    /// Pads or trims a half-typed password so a stale value never gets replayed.
    private func normalisePassword(_ settings: inout DeviceSettings) {
        let digits = settings.password.filter(\.isNumber)
        if digits.count > 6 {
            settings.password = String(digits.suffix(6))
        } else if digits.count < 6 {
            settings.password = String(repeating: "0", count: 6 - digits.count) + digits
        } else {
            settings.password = digits
        }
    }
}
