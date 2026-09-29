import SwiftUI

extension View {
    /// Keep form labels and their controls near each other in a wide Mac window.
    @ViewBuilder
    func centeredMacForm() -> some View {
        #if targetEnvironment(macCatalyst)
        frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }
}
