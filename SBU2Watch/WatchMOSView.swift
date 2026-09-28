import SwiftUI

struct WatchMOSView: View {
    @Environment(BMSConnection.self) private var connection
    @State private var pendingConfirmation: MOSWriteTracker.Terminal?

    var body: some View {
        List {
            Section {
                terminalRow(.charge, title: "Charging", enabled: connection.info.chargeMOSEnabled)
                terminalRow(.discharge, title: "Discharging", enabled: connection.info.dischargeMOSEnabled)
            } footer: {
                Text("Changes are sent directly to the BMS.")
            }

            if let error = connection.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
        .navigationTitle("MOSFETs")
        .confirmationDialog(confirmationTitle, isPresented: Binding(
            get: { pendingConfirmation != nil },
            set: { if !$0 { pendingConfirmation = nil } }
        )) {
            Button(confirmationAction, role: isDisabling ? .destructive : nil) {
                applyConfirmedChange()
            }
            Button("Cancel", role: .cancel) { pendingConfirmation = nil }
        } message: {
            Text("This changes the live battery output. Check the pack before continuing.")
        }
    }

    private func terminalRow(_ terminal: MOSWriteTracker.Terminal,
                             title: String, enabled: Bool) -> some View {
        Button {
            pendingConfirmation = terminal
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                    Text(enabled ? "On" : "Off")
                        .font(.caption)
                        .foregroundStyle(enabled ? .green : .secondary)
                }
                Spacer()
                if connection.mosWrite.isWaiting(for: terminal) {
                    ProgressView()
                } else {
                    Image(systemName: "power")
                }
            }
        }
        .disabled(!connection.canControlMOS || connection.mosWrite.isBusy)
    }

    private var isDisabling: Bool {
        switch pendingConfirmation {
        case .charge: connection.info.chargeMOSEnabled
        case .discharge: connection.info.dischargeMOSEnabled
        case nil: false
        }
    }

    private var confirmationTitle: String {
        guard let terminal = pendingConfirmation else { return "Change MOSFET?" }
        let name = terminal == .charge ? "charging" : "discharging"
        return "\(isDisabling ? "Disable" : "Enable") \(name)?"
    }

    private var confirmationAction: String {
        isDisabling ? "Disable" : "Enable"
    }

    private func applyConfirmedChange() {
        guard let terminal = pendingConfirmation, connection.canControlMOS else { return }
        let info = connection.info
        pendingConfirmation = nil
        switch terminal {
        case .charge:
            connection.setMOS(terminal: .charge,
                              charge: !info.chargeMOSEnabled,
                              discharge: info.dischargeMOSEnabled)
        case .discharge:
            connection.setMOS(terminal: .discharge,
                              charge: info.chargeMOSEnabled,
                              discharge: !info.dischargeMOSEnabled)
        }
    }
}
