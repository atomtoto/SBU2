//
//  OrientationLock.swift
//  SBU2
//

import SwiftUI
import UIKit

/// Keep the iPhone portrait-first behaviour, while letting iPad windows rotate on
/// every tab. On iPad the available window width, not the device orientation,
/// determines whether a dashboard has room for multiple columns.
final class OrientationLock {
    static let shared = OrientationLock()

    private(set) var mask: UIInterfaceOrientationMask = OrientationLock.defaultMask

    private static var defaultMask: UIInterfaceOrientationMask {
        #if targetEnvironment(macCatalyst)
        .all
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .portrait
        #endif
    }

    private init() {}

    func allowAllOrientations() { apply(.all) }

    func lockToPortrait() { apply(Self.defaultMask) }

    private func apply(_ mask: UIInterfaceOrientationMask) {
        guard self.mask != mask else { return }
        self.mask = mask
        #if !targetEnvironment(macCatalyst)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        #endif
    }
}

/// Starts shared services even when the first scene is the CarPlay display.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        AppRuntime.shared.start()
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.shared.mask
    }
}
