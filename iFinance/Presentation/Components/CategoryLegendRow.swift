import SwiftUI

struct CategoryLegendRow: View {
    let data: CategoriesChartView.CategoryData
    let isSelected: Bool
    let currency: String
    
    var body: some View {
        HStack(spacing: 12) {
            // Pastille de couleur
            Circle()
                .fill(data.color)
                .frame(width: 12, height: 12)
            
            // Nom de la catégorie
            VStack(alignment: .leading, spacing: 2) {
                Text(data.categoryName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                Text("\(Int(data.percentage))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Montant
            Text(data.amount, format: .currency(code: currency))
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(.red)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? data.color.opacity(0.1) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? data.color : Color.clear, lineWidth: 2)
        )
    }
}
