import SwiftUI

/// Création ou modification d'un projet
struct ProjectFormView: View {
    @Binding var isPresented: Bool
    var projectToEdit: Project? = nil

    @EnvironmentObject var projectsController: ProjectsController
    @EnvironmentObject var booksController: BooksController

    @State private var name = ""
    @State private var color = BookFormView.palette[0].hex
    @State private var hasStartDate = false
    @State private var startDate = Date()
    @State private var hasEndDate = false
    @State private var endDate = Date()
    @State private var hasBudget = false
    @State private var budget: Decimal = 0
    @State private var isCompleted = false
    @State private var note = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Nom", text: $name, prompt: Text("Voyage en Australie"))

                    LabeledContent("Couleur") {
                        HStack(spacing: 8) {
                            ForEach(BookFormView.palette, id: \.hex) { item in
                                Button {
                                    color = item.hex
                                } label: {
                                    Circle()
                                        .fill(Color(hex: item.hex))
                                        .frame(width: 16, height: 16)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: color == item.hex ? 2 : 0)
                                                .padding(-3)
                                        )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(item.name)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }

                Section {
                    Toggle("Date de début", isOn: $hasStartDate)
                    if hasStartDate {
                        DatePicker("Début", selection: $startDate, displayedComponents: .date)
                    }
                    Toggle("Date de fin", isOn: $hasEndDate)
                    if hasEndDate {
                        DatePicker("Fin", selection: $endDate, displayedComponents: .date)
                    }
                }

                Section {
                    Toggle("Enveloppe prévue", isOn: $hasBudget)
                    if hasBudget {
                        TextField("Montant", value: $budget, format: .number)
                            .multilineTextAlignment(.trailing)
                    }
                } footer: {
                    Text("Sans enveloppe, le projet sert seulement à regrouper des transactions.")
                }

                Section {
                    if projectToEdit != nil {
                        Toggle("Projet terminé", isOn: $isCompleted)
                    }
                    TextField("Note", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Annuler") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Button(projectToEdit == nil ? "Créer" : "Enregistrer") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding(12)
        }
        .frame(width: 460, height: 520)
        .navigationTitle(projectToEdit == nil ? "Nouveau projet" : "Modifier le projet")
        .onAppear(perform: load)
    }

    private func load() {
        guard let project = projectToEdit else { return }
        name = project.name
        color = project.displayColor
        hasStartDate = project.startDate != nil
        startDate = project.startDate ?? Date()
        hasEndDate = project.endDate != nil
        endDate = project.endDate ?? Date()
        hasBudget = project.budget != nil
        budget = project.budget ?? 0
        isCompleted = project.isCompleted
        note = project.note ?? ""
    }

    private func save() {
        guard let bookID = projectToEdit?.bookID ?? booksController.currentBook?.id else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        var project = projectToEdit ?? Project(bookID: bookID, name: trimmedName)
        project.name = trimmedName
        project.color = color
        project.startDate = hasStartDate ? startDate : nil
        project.endDate = hasEndDate ? endDate : nil
        project.budget = hasBudget && budget > 0 ? budget : nil
        project.isCompleted = isCompleted
        project.note = trimmedNote.isEmpty ? nil : trimmedNote

        let isNew = projectToEdit == nil
        Task {
            if isNew {
                await projectsController.createProject(project)
            } else {
                await projectsController.updateProject(project)
            }
            isPresented = false
        }
    }
}
