//
//  OrientationLock.swift
//  SBU2
//

import SwiftUI
import UIKit

/// SBU pinned the app to portrait and unlocked rotation only on the GPS tab, so the
/// dials could be read in landscape. This keeps that behaviour.
final class OrientationLock {
    static let shared = OrientationLock()

    private(set) var mask: UIInterfaceOrientationMask = .portrait

    private init() {}

    func allowAllOrientations() { apply(.all) }

    func lockToPortrait() { apply(.portrait) }

    private func apply(_ mask: UIInterfaceOrientationMask) {
        guard self.mask != mask else { return }
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

/// The delegate exists only to answer the orientation question above.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}
