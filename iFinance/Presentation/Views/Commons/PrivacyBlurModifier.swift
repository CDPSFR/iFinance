import SwiftUI

extension View {
    func privacyBlur(hidden: Bool) -> some View {
        self
            .blur(radius: hidden ? 8 : 0)
            .animation(.easeInOut(duration: 0.2), value: hidden)
    }
}
