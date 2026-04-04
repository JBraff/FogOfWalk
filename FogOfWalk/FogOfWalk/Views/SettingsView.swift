import SwiftUI

struct SettingsView: View {
    @Environment(GridSettings.self)     private var gridSettings
    @Environment(ExplorationStore.self) private var store
    @Environment(\.dismiss)            private var dismiss

    @State private var selectedSize          = CellSizeMeters.normal.rawValue
    @State private var selectedHighlight     = HighlightPeriod.today
    @State private var showDeleteAlert       = false

    var body: some View {
        NavigationStack {
            SettingsForm(
                selectedSize: $selectedSize,
                selectedHighlight: $selectedHighlight,
                showDeleteAlert: $showDeleteAlert,
                savedCellSize: gridSettings.cellSizeMeters
            )
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            gridSettings.cellSizeMeters  = selectedSize
                            gridSettings.highlightPeriod = selectedHighlight
                            dismiss()
                        }
                    }
                }
                .onAppear {
                    selectedSize      = gridSettings.cellSizeMeters
                    selectedHighlight = gridSettings.highlightPeriod
                }
                .confirmationDialog(
                    "Delete All Data?",
                    isPresented: $showDeleteAlert,
                    titleVisibility: .visible
                ) {
                    Button("Delete Everything", role: .destructive) {
                        store.deleteAllCells()
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes all your exploration history and cannot be undone.")
                }
        }
    }

}

private struct SettingsForm: View {
    @Binding var selectedSize:      Double
    @Binding var selectedHighlight: HighlightPeriod
    @Binding var showDeleteAlert:   Bool
    let savedCellSize: Double

    private func cellSizeButton(_ size: CellSizeMeters) -> some View {
        Button {
            selectedSize = size.rawValue
        } label: {
            HStack {
                Text(size.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedSize == size.rawValue {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    private func highlightButton(_ period: HighlightPeriod) -> some View {
        Button {
            selectedHighlight = period
        } label: {
            HStack {
                Text(period.displayName)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedHighlight == period {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                }
            }
        }
    }

    var body: some View {
        Form {
            Section("Cell Size") {
                cellSizeButton(.fine)
                cellSizeButton(.normal)
                cellSizeButton(.coarse)
                cellSizeButton(.veryCoarse)
            }

            if selectedSize != savedCellSize {
                Section {
                    Label(
                        "Changing cell size shows your exploration at the new resolution. Previous data is preserved.",
                        systemImage: "info.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Highlight Recent") {
                ForEach(HighlightPeriod.allCases) { period in
                    highlightButton(period)
                }
            }

            Section("Data") {
                Button("Delete All Exploration Data", role: .destructive) {
                    showDeleteAlert = true
                }
            }
        }
    }
}
