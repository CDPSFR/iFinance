import SwiftUI
import AppKit

// Dans un Form groupé, les Picker SwiftUI (menu et segmenté) gardent leur largeur
// naturelle même avec .frame(maxWidth: .infinity). Ces contrôles AppKit occupent
// toute la largeur disponible.

// MARK: - Segmented

/// Contrôle segmenté dont les segments se partagent toute la largeur
struct FillSegmentedPicker<Value: Hashable>: NSViewRepresentable {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map { $0.title },
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: FillSegmentedPicker

        init(_ parent: FillSegmentedPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ control: NSSegmentedControl) {
            guard parent.options.indices.contains(control.selectedSegment) else { return }
            parent.selection = parent.options[control.selectedSegment].value
        }
    }
}

// MARK: - Pop-up

struct FillPopUpItem<ID: Hashable>: Equatable {
    let id: ID?                 // nil = option « Aucun / Sélectionner… »
    let title: String
    var systemImage: String? = nil
    var indentationLevel: Int = 0
}

/// Menu déroulant qui occupe toute la largeur disponible
struct FillPopUpPicker<ID: Hashable>: NSViewRepresentable {
    let items: [FillPopUpItem<ID>]
    @Binding var selection: ID?

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        // Ne reconstruire le menu que si les options ont changé
        if coordinator.renderedItems != items {
            button.removeAllItems()
            for item in items {
                let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                if let systemImage = item.systemImage {
                    menuItem.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
                }
                menuItem.indentationLevel = item.indentationLevel
                button.menu?.addItem(menuItem)
            }
            coordinator.renderedItems = items
        }

        let index = items.firstIndex { $0.id == selection } ?? -1
        if button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject {
        var parent: FillPopUpPicker
        var renderedItems: [FillPopUpItem<ID>] = []

        init(_ parent: FillPopUpPicker) {
            self.parent = parent
        }

        @objc func selectionChanged(_ button: NSPopUpButton) {
            guard parent.items.indices.contains(button.indexOfSelectedItem) else { return }
            parent.selection = parent.items[button.indexOfSelectedItem].id
        }
    }
}
