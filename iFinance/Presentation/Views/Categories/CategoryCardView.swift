import SwiftUI

struct CategoryCardView: View {
    let category: Category
    let subcategories: [Category]
    let onEdit: (Category) -> Void
    let onDelete: (Category) -> Void
    
    @State private var isExpanded = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Catégorie parent
            HStack(spacing: 12) {
                // Icône
                if let iconName = category.icon {
                    Image(systemName: iconName)
                        .font(.title2)
                        .foregroundColor(Color(hex: category.displayColor))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color(hex: category.displayColor).opacity(0.1))
                        )
                }
                
                // Nom
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.headline)
                    
                    if let description = category.description {
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Badge nombre de sous-catégories
                if !subcategories.isEmpty {
                    Text("\(subcategories.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(12)
                }
                
                // Bouton expand si sous-catégories
                if !subcategories.isEmpty {
                    Button {
                        withAnimation {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                
                // Menu actions
                Menu {
                    Button {
                        onEdit(category)
                    } label: {
                        Label("Modifier", systemImage: "pencil")
                    }
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        onDelete(category)
                    } label: {
                        Label("Supprimer", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.borderlessButton)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Sous-catégories (si expanded)
            if isExpanded && !subcategories.isEmpty {
                VStack(spacing: 8) {
                    ForEach(subcategories) { sub in
                        SubcategoryRowView(
                            subcategory: sub,
                            parentColor: category.displayColor,
                            onEdit: { onEdit(sub) },
                            onDelete: { onDelete(sub) }
                        )
                    }
                }
                .padding(.leading, 20)
                .padding(.top, 8)
            }
        }
    }
}

struct SubcategoryRowView: View {
    let subcategory: Category
    let parentColor: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Indicateur visuel
            Rectangle()
                .fill(Color(hex: parentColor))
                .frame(width: 3, height: 30)
                .cornerRadius(2)
            
            // Icône
            if let iconName = subcategory.icon {
                Image(systemName: iconName)
                    .font(.subheadline)
                    .foregroundColor(Color(hex: subcategory.displayColor))
                    .frame(width: 30, height: 30)
            }
            
            // Nom
            Text(subcategory.name)
                .font(.subheadline)
            
            Spacer()
            
            // Menu actions
            Menu {
                Button {
                    onEdit()
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

// Helper pour convertir hex en Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
