import SwiftUI
import Combine

class AppSettings: ObservableObject {
    @AppStorage("hideAmounts") var hideAmounts: Bool = false
}
