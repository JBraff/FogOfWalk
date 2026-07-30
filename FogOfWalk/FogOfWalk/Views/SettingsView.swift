import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ExplorationStore.self) private var store
    @Environment(LandmarkStore.self)    private var landmarkStore
    @Environment(\.dismiss)             private var dismiss

    @State private var exportURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    @State private var showImporter = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var importSummaryMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Export Backup…") { exportBackup() }

                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share Backup File", systemImage: "square.and.arrow.up")
                        }
                    }

                    Button("Import Backup…") { showImporter = true }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("Export your exploration history and discovered landmarks to a file you control. Import merges a backup into what's already on this device — nothing is ever overwritten.")
                }

                if let importSummaryMessage {
                    Section {
                        Text(importSummaryMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            handleImportResult(result)
        }
        .alert("Export Failed", isPresented: $showExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage)
        }
        .alert("Import Failed", isPresented: $showImportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importErrorMessage)
        }
    }

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func exportBackup() {
        do {
            let data = try BackupService.exportData(explorationStore: store, landmarkStore: landmarkStore)
            let filename = "FogOfWalk-Backup-\(Self.exportDateFormatter.string(from: Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            exportURL = url
        } catch {
            exportErrorMessage = error.localizedDescription
            showExportError = true
        }
    }

    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importErrorMessage = error.localizedDescription
            showImportError = true
        case .success(let url):
            do {
                let data = try Data(contentsOf: url)
                let payload = try BackupService.decode(data)
                let summary = BackupService.merge(payload, into: store, landmarkStore: landmarkStore)
                importSummaryMessage = "Imported \(summary.cellsAdded) new cell\(summary.cellsAdded == 1 ? "" : "s"), "
                    + "\(summary.landmarksAdded) new landmark\(summary.landmarksAdded == 1 ? "" : "s")."
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
    }
}
