import Foundation
import Testing
@testable import SBU2

@Suite("iCloud account identity")
struct ICloudAccountIdentityTests {
    @Test("A first signed-out launch establishes a baseline")
    func signedOutBaseline() {
        withDefaults { defaults in
            let identity = ICloudAccountIdentity(tokenProvider: { nil })
            #expect(!identity.accountChanged(defaults: defaults))
            #expect(!identity.accountChanged(defaults: defaults))
        }
    }

    @Test("Account equality survives relaunch and different token instances")
    func equalityAcrossRelaunch() {
        withDefaults { defaults in
            let initial = ICloudAccountIdentity(tokenProvider: { NSNumber(value: 42) })
            #expect(!initial.accountChanged(defaults: defaults))
            let sameAccount = ICloudAccountIdentity(tokenProvider: { NSNumber(value: 42) })
            #expect(!sameAccount.accountChanged(defaults: defaults))
            let otherAccount = ICloudAccountIdentity(tokenProvider: { NSNumber(value: 43) })
            #expect(otherAccount.accountChanged(defaults: defaults))
            #expect(!otherAccount.accountChanged(defaults: defaults))
        }
    }

    @Test("Signing in or out while the app is closed is detected once")
    func signInAndOut() {
        withDefaults { defaults in
            let signedOut = ICloudAccountIdentity(tokenProvider: { nil })
            #expect(!signedOut.accountChanged(defaults: defaults))
            let signedIn = ICloudAccountIdentity(tokenProvider: { NSString(string: "account") })
            #expect(signedIn.accountChanged(defaults: defaults))
            #expect(!signedIn.accountChanged(defaults: defaults))
            #expect(signedOut.accountChanged(defaults: defaults))
            #expect(!signedOut.accountChanged(defaults: defaults))
        }
    }

    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "SBU2.ICloudAccountIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }
}
