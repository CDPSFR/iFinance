import SwiftUI

struct TransactionFiltersView: View {
    @EnvironmentObject var accountsController: AccountsController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var payeesController: PayeesController
    
    @Binding var filters: TransactionFilters
    @Binding var isPresented: Bool
    
    @State private var tempFilters: TransactionFilters
    @State private var customStartDate: Date
    @State private var customEndDate: Date
    @State private var selectedDateRange: TransactionFilters.DateRange
    
    init(filters: Binding<TransactionFilters>, isPresented: Binding<Bool>) {
        self._filters = filters
        self._isPresented = isPresented
        
        let currentFilters = filters.wrappedValue
        _tempFilters = State(initialValue: currentFilters)
        _selectedDateRange = State(initialValue: currentFilters.dateRange)
        
        if case .custom(let start, let end) = currentFilters.dateRange {
            _customStartDate = State(initialValue: start)
            _customEndDate = State(initialValue: end)
        } else {
            _customStartDate = State(initialValue: Date())
            _customEndDate = State(initialValue: Date())
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Filtres")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                if tempFilters.isActive {
                    Button {
                        resetFilters()
                    } label: {
                        Text("Tout effacer")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                }
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            
            Divider()
            
            // Contenu
            ScrollView {
                VStack(spacing: 20) {
                    // Type de transaction
                    filterSection(title: "Type de transaction", icon: "arrow.left.arrow.right.circle") {
                        Picker("", selection: $tempFilters.transactionType) {
                            Text("Tout").tag(nil as TransactionType?)
                            ForEach(TransactionType.allCases, id: \.self) { type in
                                HStack {
                                    Image(systemName: type.icon)
                                    Text(type.displayName)
                                }
                                .tag(type as TransactionType?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    
                    // Compte
                    if accountsController.activeAccounts.count > 1 {
                        filterSection(title: "Compte", icon: "creditcard") {
                            Picker("", selection: $tempFilters.accountID) {
                                Text("Tout").tag(nil as UUID?)
                                ForEach(accountsController.activeAccounts) { account in
                                    Text(account.name).tag(account.id as UUID?)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                    
                    // Catégorie
                    filterSection(title: "Catégorie", icon: "folder") {
                        Picker("", selection: $tempFilters.categoryID) {
                            Text("Tout").tag(nil as UUID?)
                            
                            ForEach(categoriesController.rootCategories) { category in
                                HStack {
                                    if let iconName = category.icon {
                                        Image(systemName: iconName)
                                            .foregroundColor(Color(hex: category.displayColor))
                                    }
                                    Text(category.name)
                                }
                                .tag(category.id as UUID?)
                                
                                ForEach(categoriesController.getSubcategories(for: category.id)) { sub in
                                    HStack {
                                        Text("  ")
                                        if let iconName = sub.icon {
                                            Image(systemName: iconName)
                                                .foregroundColor(Color(hex: sub.displayColor))
                                                .font(.caption)
                                        }
                                        Text(sub.name)
                                    }
                                    .tag(sub.id as UUID?)
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    
                    // Bénéficiaire
                    filterSection(title: "Bénéficiaire", icon: "person.crop.circle") {
                        Picker("", selection: $tempFilters.payeeID) {
                            Text("Tout").tag(nil as UUID?)
                            ForEach(payeesController.payees) { payee in
                                Text(payee.name).tag(payee.id as UUID?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Intervalle de dates
                    filterSection(title: "Intervalle", icon: "calendar") {
                        VStack(spacing: 12) {
                            Picker("", selection: $selectedDateRange) {
                                Text("Tout").tag(TransactionFilters.DateRange.all)
                                Text("Aujourd'hui").tag(TransactionFilters.DateRange.today)
                                Text("Cette semaine").tag(TransactionFilters.DateRange.thisWeek)
                                Text("Ce mois").tag(TransactionFilters.DateRange.thisMonth)
                                Text("Mois dernier").tag(TransactionFilters.DateRange.lastMonth)
                                Text("Cette année").tag(TransactionFilters.DateRange.thisYear)
                                Text("Personnalisé").tag(TransactionFilters.DateRange.custom(start: customStartDate, end: customEndDate))
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .onChange(of: selectedDateRange) { oldValue, newValue in
                                if case .custom = newValue {
                                    // Garde les dates custom
                                } else {
                                    tempFilters.dateRange = newValue
                                }
                            }
                            
                            // Dates personnalisées
                            if case .custom = selectedDateRange {
                                VStack(spacing: 8) {
                                    DatePicker("De", selection: $customStartDate, displayedComponents: [.date])
                                    DatePicker("À", selection: $customEndDate, displayedComponents: [.date])
                                }
                                .onChange(of: customStartDate) { oldValue, newValue in
                                    tempFilters.dateRange = .custom(start: newValue, end: customEndDate)
                                }
                                .onChange(of: customEndDate) { oldValue, newValue in
                                    tempFilters.dateRange = .custom(start: customStartDate, end: newValue)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Footer avec boutons
            HStack(spacing: 12) {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Fermer") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Appliquer") {
                    applyFilters()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 450, height: 600)
    }
    
    @ViewBuilder
    private func filterSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                Text(title)
                    .frame(width: 120, alignment: .trailing)
            }
            
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private func resetFilters() {
        tempFilters = .empty
        selectedDateRange = .all
        customStartDate = Date()
        customEndDate = Date()
    }
    
    private func applyFilters() {
        filters = tempFilters
        isPresented = false
    }
}
