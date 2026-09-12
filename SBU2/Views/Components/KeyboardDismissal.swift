//
//  KeyboardDismissal.swift
//  SBU2
//

import SwiftUI
#if canImport(UIKit)
import Combine
import UIKit
#endif

extension View {
    /// Gives a form full of number fields a way to be left again.
    ///
    /// A number pad has no return key, so a field keeps the keyboard until something
    /// else takes it — and in a form of nothing but numbers there is often nothing
    /// else to tap. Three ways out are added here: a tap anywhere on the form, a drag
    /// of the form itself, and a Done button above the keyboard for anyone who looks
    /// for one there.
    func dismissableKeyboard() -> some View {
        modifier(DismissableKeyboard())
    }
}

private struct DismissableKeyboard: ViewModifier {

    /// Only while the keyboard is actually up does a tap put it away.
    ///
    /// Without that condition the tap that *opens* a field would also close it: the
    /// gesture runs alongside the field's own handling rather than instead of it, so
    /// it would fire on the way in and resign the field as it became first responder.
    @State private var keyboardIsUp = false

    func body(content: Content) -> some View {
        #if canImport(UIKit)
        content
            .scrollDismissesKeyboard(.interactively)
            // Simultaneous, so rows, pickers and links all keep working normally.
            .simultaneousGesture(TapGesture().onEnded {
                if keyboardIsUp { endEditing() }
            })
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { endEditing() }
                        .fontWeight(.semibold)
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardIsUp = true
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardIsUp = false
            }
        #else
        content
        #endif
    }

    private func endEditing() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }
}
