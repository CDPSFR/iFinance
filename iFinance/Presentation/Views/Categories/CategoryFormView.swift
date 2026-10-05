import SwiftUI

/// Création ou modification d'une catégorie.
/// Tous les contrôles partagent une colonne de 260 points, alignée à droite.
struct CategoryFormView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController
    @EnvironmentObject var transactionsController: TransactionsController
    @Binding var isPresented: Bool

    var categoryToEdit: Category?
    /// Parent présélectionné lors de la création d'une sous-catégorie
    var parentCategory: Category? = nil
    /// Sens présélectionné à la création (par exemple depuis une transaction de type revenu)
    var initialIsIncome: Bool? = nil

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedParent: UUID?
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: String = "#2196F3"
    @State private var isIncome: Bool = false
    @State private var isCreating = false
    @State private var iconSearch = ""
    @State private var showDeleteConfirmation = false

    private static let controlWidth: CGFloat = 260

    let availableIcons = [
        // Alimentation
        "cart.fill", "fork.knife", "cup.and.saucer.fill", "wineglass.fill",
        "birthday.cake.fill", "refrigerator.fill", "frying.pan.fill", "takeoutbag.and.cup.and.straw.fill",

        // Transport
        "car.fill", "fuelpump.fill", "tram.fill", "bus.fill", "airplane",
        "bicycle", "ferry.fill", "ev.charger.fill", "parkingsign.circle.fill",

        // Logement
        "house.fill", "bolt.fill", "flame.fill", "drop.fill", "wifi",
        "wrench.and.screwdriver.fill", "sofa.fill", "bed.double.fill", "key.fill",

        // Santé
        "cross.case.fill", "heart.fill", "pills.fill", "stethoscope",
        "figure.run", "dumbbell.fill", "brain.filled.head.profile", "bandage.fill",

        // Shopping
        "bag.fill", "tag.fill", "tshirt.fill", "shoe.fill", "eyeglasses",
        "watch.analog", "sparkles", "paintbrush.fill",

        // Loisirs
        "tv.fill", "gamecontroller.fill", "music.note", "headphones",
        "film.fill", "book.fill", "theatermasks.fill", "sportscar.fill",
        "figure.hiking", "figure.swimming", "figure.soccer", "tennis.racket",
        "camera.fill", "photo.fill", "ticket.fill",

        // Voyages
        "airplane.departure", "suitcase.fill", "beach.umbrella.fill",
        "map.fill", "globe", "tent.fill", "mountain.2.fill",

        // Finance
        "dollarsign.circle.fill", "banknote.fill", "creditcard.fill",
        "chart.line.uptrend.xyaxis", "chart.bar.fill", "percent",
        "arrow.up.arrow.down.circle.fill", "building.columns.fill",
        "safe.fill", "bitcoinsign.circle.fill",

        // Travail
        "briefcase.fill", "desktopcomputer", "laptopcomputer",
        "printer.fill", "phone.fill", "envelope.fill", "doc.fill",
        "pencil.and.list.clipboard", "person.2.fill",

        // Abonnements & Services
        "play.rectangle.fill", "antenna.radiowaves.left.and.right",
        "newspaper.fill", "cloud.fill", "iphone",

        // Famille & Enfants
        "figure.and.child.holdinghands", "teddybear.fill",
        "stroller.fill", "backpack.fill", "graduationcap.fill",

        // Animaux
        "pawprint.fill", "dog.fill", "cat.fill", "lizard.fill",

        // Dons & Impôts
        "hand.raised.fill", "building.2.fill", "scalemass.fill",
        "person.crop.circle.badge.checkmark",

        // Divers
        "gift.fill", "folder.fill", "star.fill", "bell.fill",
        "questionmark.circle.fill", "ellipsis.circle.fill"
    ]
    
    let availableColors = [
        "#F44336", "#E91E63", "#9C27B0", "#673AB7",
        "#3F51B5", "#2196F3", "#03A9F4", "#00BCD4",
        "#009688", "#4CAF50", "#8BC34A", "#CDDC39",
        "#FFEB3B", "#FFC107", "#FF9800", "#FF5722"
    ]

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    /// Nombre de transactions déjà classées dans la catégorie modifiée
    private var transactionCount: Int {
        guard let id = categoryToEdit?.id else { return 0 }
        return transactionsController.allTransactions.filter { $0.categoryID == id }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Picker("Sens", selection: $isIncome) {
                Text("Dépense").tag(false)
                Text("Revenu").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .onChange(of: isIncome) { _, _ in
                // Le parent doit rester du même sens que la catégorie
                if let parentID = selectedParent,
                   categoriesController.getCategory(id: parentID)?.isIncome != isIncome {
                    selectedParent = nil
                }
            }

            Form {
                Section {
                    LabeledContent("Nom") {
                        TextField("Nom", text: $name, prompt: Text("Restaurants"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .frame(width: Self.controlWidth)
                    }

                    LabeledContent("Catégorie parente") {
                        FillPopUpPicker(items: parentItems, selection: $selectedParent)
                            .frame(width: Self.controlWidth)
                    }
                }

                Section {
                    LabeledContent("Couleur") {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                            ForEach(availableColors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: selectedColor.caseInsensitiveCompare(color) == .orderedSame ? 2 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Couleur \(color)")
                            }
                        }
                        .frame(width: Self.controlWidth)
                        .padding(.vertical, 4)
                    }

                    LabeledContent("Icône") {
                        VStack(spacing: 6) {
                            TextField("Rechercher", text: $iconSearch, prompt: Text("Rechercher une icône"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)

                            // Quatre lignes visibles, le reste défile
                            ScrollView {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                                    ForEach(filteredIcons, id: \.self) { icon in
                                        Button {
                                            selectedIcon = icon
                                        } label: {
                                            Image(systemName: icon)
                                                .font(.system(size: 13))
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 27)
                                                .foregroundStyle(selectedIcon == icon ? Color.white : Color.secondary)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                        .fill(selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.06))
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(icon)
                                    }
                                }
                            }
                            .frame(height: 4 * 27 + 3 * 6)
                        }
                        .frame(width: Self.controlWidth)
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    LabeledContent("Description") {
                        TextField("Description", text: $description, prompt: Text("Facultatif"), axis: .vertical)
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2...4)
                            .frame(width: Self.controlWidth)
                    }
                } footer: {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 8) {
                if categoryToEdit != nil {
                    Button("Supprimer…", role: .destructive) { showDeleteConfirmation = true }
                }
                Spacer()
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(categoryToEdit == nil ? "Créer" : "Enregistrer") {
                    saveCategory()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || isCreating)
            }
            .padding(12)
        }
        .frame(width: 520, height: 680)
        .sheetBackground()
        .onAppear(perform: loadCategoryData)
        .alert("Supprimer la catégorie ?", isPresented: $showDeleteConfirmation) {
            Button("Annuler", role: .cancel) { }
            Button("Supprimer", role: .destructive) {
                guard let id = categoryToEdit?.id else { return }
                Task {
                    await categoriesController.deleteCategory(id: id)
                    isPresented = false
                }
            }
        } message: {
            Text(transactionCount == 0
                 ? "La catégorie « \(name) » sera supprimée."
                 : "La catégorie « \(name) » sera supprimée. Ses \(transactionCount) transaction\(transactionCount > 1 ? "s" : "") ne seront plus classées.")
        }
    }

    // MARK: - En-tête

    /// Pastille qui reflète en direct la couleur et l'icône choisies
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: selectedIcon)
                .font(.system(size: 18))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: selectedColor))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(categoryToEdit == nil ? "Nouvelle catégorie" : "Modifier la catégorie")
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        guard categoryToEdit != nil else {
            return "Ajoutée au livre « \(bookController.currentBook?.name ?? "") »."
        }
        let count = transactionCount
        return "\(count) transaction\(count > 1 ? "s" : "") classée\(count > 1 ? "s" : "")"
    }

    private var hint: String {
        if categoryToEdit != nil, transactionCount > 0 {
            return "Changer le sens ou la catégorie parente s'applique aux \(transactionCount) transactions déjà classées."
        }
        return "Une sous-catégorie a le même sens (dépense ou revenu) que sa catégorie parente."
    }

    private var filteredIcons: [String] {
        iconSearch.isEmpty ? availableIcons : availableIcons.filter { $0.localizedCaseInsensitiveContains(iconSearch) }
    }

    private var parentItems: [FillPopUpItem<UUID>] {
        [FillPopUpItem<UUID>(id: nil, title: "Aucune (catégorie principale)")]
            + availableParentCategories.map { FillPopUpItem(id: $0.id, title: $0.name, systemImage: $0.icon ?? "folder") }
    }

    private func loadCategoryData() {
        if let category = categoryToEdit {
            name = category.name
            description = category.description ?? ""
            selectedParent = category.parentID
            selectedIcon = category.displayIcon  // Utilise displayIcon au lieu de icon
            selectedColor = category.displayColor  // Utilise displayColor au lieu de color
            isIncome = category.isIncome
        } else {
            // Réinitialiser pour une nouvelle catégorie (sous la catégorie parente si fournie)
            name = ""
            description = ""
            selectedParent = parentCategory?.id
            selectedIcon = "folder.fill"
            selectedColor = parentCategory?.displayColor ?? "#2196F3"
            isIncome = parentCategory?.isIncome ?? initialIsIncome ?? false
        }
    }
    
    private var availableParentCategories: [Category] {
        // Ne montrer que les catégories racines du même type (revenu/dépense)
        let roots = categoriesController.rootCategories.filter { $0.isIncome == isIncome }
        
        // Si on édite, exclure la catégorie elle-même
        if let editingID = categoryToEdit?.id {
            return roots.filter { $0.id != editingID }
        }
        
        return roots
    }
    
    private func saveCategory() {
        guard !trimmedName.isEmpty,
              let bookID = bookController.currentBook?.id else {
            return
        }
        
        isCreating = true
        
        Task {
            if let existingCategory = categoryToEdit {
                // Modification
                var updated = existingCategory
                updated.name = trimmedName
                updated.description = description.isEmpty ? nil : description
                updated.parentID = selectedParent
                updated.icon = selectedIcon
                updated.color = selectedColor
                updated.isIncome = isIncome
                
                await categoriesController.updateCategory(updated)
            } else {
                // Création
                await categoriesController.createCategory(
                    bookID: bookID,
                    name: trimmedName,
                    description: description.isEmpty ? nil : description,
                    parentID: selectedParent,
                    color: selectedColor,
                    icon: selectedIcon,
                    isIncome: isIncome
                )
            }
            
            isPresented = false
        }
    }
}
