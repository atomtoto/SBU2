//
//  KeyboardDismissal.swift
//  SBU2
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Gives every field in the app a way to be left again.
    ///
    /// Applied once, at the root. Everything it sets up runs off notifications rather
    /// than off the view hierarchy, so a single one of these covers every screen there
    /// is: in a tab, pushed onto the stack, or presented in a sheet.
    ///
    /// It used to be applied per screen, which is what made the Done bar come and go.
    /// A SwiftUI keyboard toolbar belongs to the view that declares it, and two screens
    /// of the same navigation stack — the settings form and the password screen pushed
    /// from it — each declared one. Both were in the hierarchy at once, and which of
    /// them the keyboard showed was not something either of them decided.
    func dismissableKeyboard() -> some View {
        modifier(DismissableKeyboard())
    }
}

private struct DismissableKeyboard: ViewModifier {
    #if canImport(UIKit)
    @State private var assistant = KeyboardAssistant()
    #endif

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            // Set once here rather than on each form: it travels down the environment,
            // so every list and form below dismisses on a drag.
            .scrollDismissesKeyboard(.immediately)
            .onAppear { assistant.start() }
            .onDisappear { assistant.stop() }
        #else
        content
        #endif
    }
}

#if canImport(UIKit)

/// Watches for editing to begin anywhere in the app, and makes sure there is a way out
/// of it.
///
/// Two ways, in fact. A Done bar above the keyboard, because a number pad has no return
/// key — fitted to the field itself, so it is there whenever a field is, whatever
/// screen that field happens to be on. And a tap anywhere else, because that is what
/// anyone tries first.
///
/// The tap is *watched*, never taken. `cancelsTouchesInView` stays off and the
/// recogniser agrees to run alongside every other one, so the row, picker or link the
/// tap was really meant for still receives it. The version before this hung a SwiftUI
/// `simultaneousGesture` on the whole form, which did take it: choosing a device type
/// or opening the password screen needed the finger held down rather than tapped, which
/// is a high price for putting a keyboard away.
private final class KeyboardAssistant: NSObject, UIGestureRecognizerDelegate {

    private var observing = false
    private var tap: UITapGestureRecognizer?

    func start() {
        guard !observing else { return }
        observing = true
        let centre = NotificationCenter.default
        centre.addObserver(self, selector: #selector(editingBegan),
                           name: UITextField.textDidBeginEditingNotification, object: nil)
        centre.addObserver(self, selector: #selector(editingBegan),
                           name: UITextView.textDidBeginEditingNotification, object: nil)
        centre.addObserver(self, selector: #selector(keyboardAppeared),
                           name: UIResponder.keyboardWillShowNotification, object: nil)
        centre.addObserver(self, selector: #selector(keyboardLeft),
                           name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    func stop() {
        guard observing else { return }
        NotificationCenter.default.removeObserver(self)
        observing = false
        removeTap()
    }

    // MARK: - The Done bar

    /// Fitted as the field's own input accessory the moment it starts being edited, and
    /// only if it has none of its own.
    @objc private func editingBegan(_ note: Notification) {
        switch note.object {
        case let field as UITextField where field.inputAccessoryView == nil:
            field.inputAccessoryView = makeDoneBar()
            field.reloadInputViews()
        case let view as UITextView where view.inputAccessoryView == nil:
            view.inputAccessoryView = makeDoneBar()
            view.reloadInputViews()
        default:
            break
        }
    }

    /// A system Done rather than a word of our own, so it is bold, right-aligned and in
    /// the reader's language without any of that being arranged here.
    private func makeDoneBar() -> UIToolbar {
        let bar = UIToolbar()
        bar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace,
                                     target: nil, action: nil),
                     UIBarButtonItem(barButtonSystemItem: .done,
                                     target: self, action: #selector(endEditing))]
        bar.sizeToFit()
        return bar
    }

    // MARK: - A tap anywhere else

    @objc private func keyboardAppeared(_ note: Notification) {
        guard tap == nil, let window = Self.keyWindow else { return }
        let recogniser = UITapGestureRecognizer(target: self, action: #selector(endEditing))
        recogniser.cancelsTouchesInView = false
        recogniser.delaysTouchesBegan = false
        recogniser.delaysTouchesEnded = false
        recogniser.delegate = self
        window.addGestureRecognizer(recogniser)
        tap = recogniser
    }

    /// Taken off again as soon as the keyboard goes, so nothing of this is watching the
    /// app the rest of the time.
    @objc private func keyboardLeft(_ note: Notification) {
        removeTap()
    }

    private func removeTap() {
        guard let tap else { return }
        tap.view?.removeGestureRecognizer(tap)
        self.tap = nil
    }

    @objc private func endEditing() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// A tap on a field is not a tap away from one: inside the field being edited it
    /// moves the cursor, and on another field it moves the editing there. Either way,
    /// putting the keyboard away would be the wrong answer.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let candidate = view {
            if candidate is UITextField || candidate is UITextView { return false }
            view = candidate.superview
        }
        return true
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
    }
}

#endif
