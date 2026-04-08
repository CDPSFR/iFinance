import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Text("Paramètres")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Section en cours de développement")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
