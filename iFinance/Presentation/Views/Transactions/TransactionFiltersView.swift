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
            SheetHeader(title: "Filtres")

            // Contenu
            ScrollView {
                VStack(spacing: 20) {
                    // Type de transaction
                    filterSection(title: "Type de transaction", icon: "arrow.left.arrow.right.circle") {
                        Picker("", selection: $tempFilters.transactionType) {
                            Text("Tout").tag(nil as TransactionType?)
                            // Label, pas HStack : un menu macOS n'afficherait que l'icône
                            ForEach(TransactionType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.icon)
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
                        // Menu AppKit : icône et nom, sous-catégories indentées (comme les formulaires)
                        FillPopUpPicker(items: categoryItems, selection: $tempFilters.categoryID)
                            // Taille naturelle, comme les autres menus de la feuille
                            .fixedSize()
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
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }

            // Pied : « Tout effacer » à gauche tant qu'un filtre est actif
            SheetFooter {
                if tempFilters.isActive {
                    Button("Tout effacer") {
                        resetFilters()
                    }
                }
            } actions: {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Appliquer") {
                    applyFilters()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(width: 450, height: 600)
        .sheetBackground()
    }
    
    /// « Tout », puis les catégories et leurs sous-catégories indentées
    private var categoryItems: [FillPopUpItem<UUID>] {
        var items = [FillPopUpItem<UUID>(id: nil, title: "Tout")]
        for category in categoriesController.rootCategories {
            items.append(FillPopUpItem(id: category.id, title: category.name, systemImage: category.displayIcon))
            for sub in categoriesController.getSubcategories(for: category.id) {
                items.append(FillPopUpItem(id: sub.id, title: sub.name, systemImage: sub.displayIcon, indentationLevel: 1))
            }
        }
        return items
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
