import SwiftUI

struct CategoryFormView: View {
    @EnvironmentObject var bookController: BooksController
    @EnvironmentObject var categoriesController: CategoriesController
    @Binding var isPresented: Bool
    
    var categoryToEdit: Category?
    
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedParent: UUID?
    @State private var selectedIcon: String = "folder.fill"
    @State private var selectedColor: String = "#2196F3"
    @State private var isIncome: Bool = false
    @State private var isCreating = false
    @State private var iconSearch = ""

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
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(categoryToEdit == nil ? "Nouvelle Catégorie" : "Modifier la Catégorie")
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Formulaire
            Form {
                Section {
                    TextField("Nom de la catégorie", text: $name)
                        .textFieldStyle(.roundedBorder)
                    
                    TextField("Description (optionnel)", text: $description, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }
                
                Section {
                    Picker("Type", selection: $isIncome) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Dépense")
                        }
                        .tag(false)
                        
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                            Text("Revenu")
                        }
                        .tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: isIncome) { oldValue, newValue in
                        // Réinitialiser le parent si on change de type
                        selectedParent = nil
                    }
                    
                    // Catégorie parent (optionnel)
                    Picker("Catégorie parent", selection: $selectedParent) {
                        Text("Aucune (catégorie racine)").tag(nil as UUID?)
                        
                        ForEach(availableParentCategories) { category in
                            Text(category.name).tag(category.id as UUID?)
                        }
                    }
                }
                
                Section {
                    // Sélecteur d'icône
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Icône")
                            .font(.headline)

                        HStack {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField("Rechercher une icône", text: $iconSearch)
                                .textFieldStyle(.plain)
                            if !iconSearch.isEmpty {
                                Button { iconSearch = "" } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(6)

                        let filtered = iconSearch.isEmpty ? availableIcons : availableIcons.filter { $0.localizedCaseInsensitiveContains(iconSearch) }

                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(42)), count: 10), spacing: 8) {
                                ForEach(filtered, id: \.self) { icon in
                                    Button {
                                        selectedIcon = icon
                                    } label: {
                                        Image(systemName: icon)
                                            .font(.title3)
                                            .foregroundColor(selectedIcon == icon ? .white : Color(hex: selectedColor))
                                            .frame(width: 38, height: 38)
                                            .background(
                                                Circle()
                                                    .fill(selectedIcon == icon ? Color(hex: selectedColor) : Color.gray.opacity(0.1))
                                            )
                                    }
                                    .buttonStyle(.plain)
                                    .help(icon)
                                }
                            }
                            .padding(4)
                        }
                        .frame(height: 210)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                }

                Section {
                    // Sélecteur de couleur
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couleur")
                            .font(.headline)

                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(40)), count: 8), spacing: 10) {
                            ForEach(availableColors, id: \.self) { color in
                                Button {
                                    selectedColor = color
                                } label: {
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                        )
                                        .shadow(radius: selectedColor == color ? 3 : 0)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Aperçu
                Section {
                    HStack {
                        Text("Aperçu")
                            .font(.headline)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Image(systemName: selectedIcon)
                                .foregroundColor(Color(hex: selectedColor))
                            Text(name.isEmpty ? "Nom de la catégorie" : name)
                                .foregroundColor(name.isEmpty ? .secondary : .primary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(hex: selectedColor).opacity(0.1))
                        )
                    }
                }
            }
            .formStyle(.grouped)
            
            Spacer()
            
            // Boutons
            HStack {
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(categoryToEdit == nil ? "Créer" : "Modifier") {
                    saveCategory()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 640, height: 780)
        .onAppear {
            loadCategoryData()
        }
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
            // Réinitialiser pour une nouvelle catégorie
            name = ""
            description = ""
            selectedParent = nil
            selectedIcon = "folder.fill"
            selectedColor = "#2196F3"
            isIncome = false
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
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
              let bookID = bookController.currentBook?.id else {
            return
        }
        
        isCreating = true
        
        Task {
            if let existingCategory = categoryToEdit {
                // Modification
                var updated = existingCategory
                updated.name = name
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
                    name: name,
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
