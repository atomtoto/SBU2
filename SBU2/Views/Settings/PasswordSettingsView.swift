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
                Toggle("Ce BMS a un mot de passe", isOn: $connection.settings.hasPassword)
                if connection.settings.hasPassword {
                    LabeledContent("Mot de passe") {
                        TextField("000000", text: $connection.settings.password)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                    }
                }
            } header: {
                Text("Mot de passe actuel")
            } footer: {
                Text(currentValid
                     ? "Il est réenvoyé automatiquement avant chaque écriture."
                     : "Le mot de passe doit comporter exactement 6 chiffres.")
                    .foregroundStyle(currentValid ? Color.secondary : Color.red)
            }

            Section {
                LabeledContent("Nouveau mot de passe") {
                    TextField("000000", text: $newPassword)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                }
                Button(connection.settings.hasPassword ? "Modifier le mot de passe" : "Créer un mot de passe") {
                    if connection.settings.hasPassword {
                        connection.changePassword(to: newPassword)
                    } else {
                        connection.createPassword(newPassword)
                    }
                    newPassword = ""
                }
                .disabled(!canSubmit)

                Button("Supprimer le mot de passe", role: .destructive) {
                    connection.removePassword()
                }
                .disabled(!connection.settings.hasPassword || !currentValid)
            } header: {
                Text("Changer le mot de passe")
            } footer: {
                Text("Ces commandes sont écrites dans le BMS. Notez le mot de passe : il n'existe aucun moyen de le récupérer depuis l'application.")
            }

            switch connection.passwordOutcome {
            case .succeeded:
                Section {
                    Label("Le BMS a accepté la commande.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            case .rejected(let message):
                Section {
                    Label(message, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
            case .none:
                EmptyView()
            }
        }
        .navigationTitle("Mot de passe")
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
