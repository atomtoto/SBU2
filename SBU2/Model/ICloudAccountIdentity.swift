import Foundation

/// Detects an account switch even when it happened while the app was closed.
/// Apple's token is opaque: archive it locally and compare decoded tokens using
/// NSObject equality, rather than comparing archive bytes or deriving an ID.
final class ICloudAccountIdentity {
    private static let initializedKey = "sync.accountIdentity.initialized"
    private static let signedInKey = "sync.accountIdentity.signedIn"
    private static let archiveKey = "sync.accountIdentity.archive"

    private let tokenProvider: () -> (any NSObjectProtocol)?

    init(tokenProvider: @escaping () -> (any NSObjectProtocol)? = {
        FileManager.default.ubiquityIdentityToken
    }) {
        self.tokenProvider = tokenProvider
    }

    /// Call on the main queue before touching the cloud store. The first check
    /// establishes a baseline; a later sign-in, sign-out or account switch is a
    /// change. A separate presence marker distinguishes signed out from untracked.
    func accountChanged(defaults: UserDefaults) -> Bool {
        let current = tokenProvider()
        let initialized = defaults.bool(forKey: Self.initializedKey)
        let previouslySignedIn = defaults.bool(forKey: Self.signedInKey)
        let previous = defaults.data(forKey: Self.archiveKey).flatMap(decodeToken)

        let changed: Bool
        if !initialized {
            changed = false
        } else if previouslySignedIn != (current != nil) {
            changed = true
        } else if let current {
            // A damaged/missing saved token cannot safely identify the account.
            changed = previous?.isEqual(current) != true
        } else {
            changed = false
        }

        let archive = current.flatMap {
            try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: false)
        }
        defaults.set(archive, forKey: Self.archiveKey)
        defaults.set(current != nil, forKey: Self.signedInKey)
        defaults.set(true, forKey: Self.initializedKey)
        return changed
    }

    private func decodeToken(_ data: Data) -> (any NSObjectProtocol)? {
        guard let decoder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        decoder.requiresSecureCoding = false
        decoder.decodingFailurePolicy = .setErrorAndReturn
        defer { decoder.finishDecoding() }
        return decoder.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? any NSObjectProtocol
    }
}
