import SwiftUI

struct AccountSidebarRow: View {
    let account: Account
    let balance: Decimal
    let isClosed: Bool
    @EnvironmentObject var appSettings: AppSettings
    @AppStorage(SettingsKeys.showSidebarBalances) private var showBalance = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: account.type.icon)
                .foregroundStyle(isClosed ? Color.secondary : Color.accentColor)
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

            if showBalance {
                Text(balance, format: .currency(code: account.currency))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .privacyBlur(hidden: appSettings.hideAmounts)
            }
        }
    }
}
