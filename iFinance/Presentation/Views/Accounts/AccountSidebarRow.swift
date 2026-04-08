import SwiftUI

struct AccountSidebarRow: View {
    let account: Account
    let balance: Decimal
    let isClosed: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: account.type.icon)
                .foregroundColor(.blue)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body)

                if let bank = account.bank {
                    Text(bank)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Text(balance, format: .currency(code: account.currency))
                .font(.caption)
                .foregroundColor(isClosed ? .gray : (balance >= 0 ? .green : .red))
        }
    }
}
