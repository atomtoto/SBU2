//
//  InterfaceOrientationObserver.swift
//  SBU2
//

import Observation
import UIKit

/// Tracks whether the interface is currently drawn in a portrait orientation.
///
/// `UIDevice.current.orientation` reports the device's physical attitude, which
/// reads `.faceUp`, `.faceDown` or `.unknown` — none of them portrait or landscape —
/// whenever the phone is lying flat, exactly the position it's often in once
/// mounted. Reading `UIWindowScene.interfaceOrientation` instead always reflects
/// what is actually on screen.
@Observable
final class InterfaceOrientationObserver {

    private(set) var isPortrait = true

    @ObservationIgnored private var token: NSObjectProtocol?

    /// Call from `onAppear`. Device-orientation notifications are opt-in and this
    /// pairs with `stop()`, so nothing here needs to know whether some other screen
    /// already turned them on.
    func start() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        refresh()
        token = NotificationCenter.default.addObserver(forName: UIDevice.orientationDidChangeNotification,
                                                        object: nil,
                                                        queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    /// Call from `onDisappear`.
    func stop() {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
        token = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func refresh() {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        isPortrait = scene.interfaceOrientation.isPortrait
    }
}
