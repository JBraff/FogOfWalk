import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(ExplorationStore.self) private var store
    @Environment(LandmarkStore.self)    private var landmarkStore
    @Environment(LocationService.self) private var locationService
    @Environment(\.dismiss)             private var dismiss

    @State private var exportURL: URL?
    @State private var showExportError = false
    @State private var exportErrorMessage = ""

    @State private var showImporter = false
    @State private var showImportError = false
    @State private var importErrorMessage = ""
    @State private var importSummaryMessage: String?
    @State private var study = LocationStudyDiagnostics.shared
    @State private var studyMessage: String?
    @State private var isQueryingMotion = false

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

                if study.isStudyApp {
                    Section {
                        Picker("Tracking source", selection: Binding(
                            get: { locationService.studyLocationSource },
                            set: { _ = locationService.setStudyLocationSource($0) }
                        )) {
                            Text("Legacy").tag(StudyLocationSource.legacy)
                            Text("Automatic pause/resume").tag(StudyLocationSource.liveUpdates)
                        }
                        .disabled(study.isCapturing)
                        .accessibilityIdentifier("studyLocationSource")
                        Toggle("Tracking off — stationary control", isOn: Binding(
                            get: { locationService.isStudyTrackingDisabled },
                            set: { _ = locationService.setStudyTrackingDisabled($0) }
                        ))
                        .disabled(study.isCapturing)
                        .accessibilityIdentifier("studyTrackingOff")
                        Text(locationService.isStudyTrackingDisabled
                             ? "Tracking OFF: no exploration is recorded. Use only while stationary."
                             : locationService.studyLocationSource == .legacy
                                ? "Tracking ON: legacy tracking and map location are enabled."
                                : "Automatic tracking: \(locationService.studySourceStatus). The map dot and follow are disabled during this experiment.")

                        if study.isCapturing {
                            Button("Stop Diagnostic Capture") { study.stopCapture() }
                            Text("Capture running since \(study.captureStartedAt?.formatted() ?? "unknown time").")
                        } else {
                            Button("Start Diagnostic Capture") {
                                do {
                                    try study.startCapture()
                                    locationService.recordStudyTrackingState()
                                }
                                catch { studyMessage = error.localizedDescription }
                            }
                        }

                        if let url = study.currentFileURL, !study.isCapturing {
                            ShareLink(item: url) {
                                Label("Export Location Diagnostic Log", systemImage: "square.and.arrow.up")
                            }
                        }

                        Button("Query Motion History for Last Capture") {
                            queryMotionHistory()
                        }
                        .disabled(study.isCapturing || study.captureStartedAt == nil
                                  || study.captureEndedAt == nil || isQueryingMotion)

                        if let url = study.motionFileURL {
                            ShareLink(item: url) {
                                Label("Export Motion Reference", systemImage: "square.and.arrow.up")
                            }
                        }
                        if isQueryingMotion { ProgressView("Querying motion history…") }
                        if let message = study.lastError ?? studyMessage {
                            Text(message).foregroundStyle(.orange)
                        }
                    } header: {
                        Text("Location Study")
                    } footer: {
                        Text("Choose a source before recording and leave Tracking off unchecked for a walk. Selection persists after relaunch. Automatic pause/resume requires Always permission. Stop Diagnostic Capture stops logging only. Select Legacy to restore the original tracker and map dot. Logs contain precise locations and stay on this phone until exported; old files are removed after seven days.")
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
            let didStart = url.startAccessingSecurityScopedResource()
            defer { if didStart { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let payload = try BackupService.decode(data)
                let summary = try BackupService.merge(payload, into: store, landmarkStore: landmarkStore)
                importSummaryMessage = "Imported \(summary.cellsAdded) new cell\(summary.cellsAdded == 1 ? "" : "s"), "
                    + "\(summary.landmarksAdded) new landmark\(summary.landmarksAdded == 1 ? "" : "s")."
            } catch {
                importErrorMessage = error.localizedDescription
                showImportError = true
            }
        }
    }

    private func queryMotionHistory() {
        guard let start = study.captureStartedAt, let end = study.captureEndedAt else { return }
        isQueryingMotion = true
        studyMessage = nil
        Task {
            do {
                let result = try await StudyMotionReference.query(from: start, to: end)
                try study.saveMotionReference(result)
                studyMessage = "Motion history saved. Review its timing and distance uncertainty before scoring a departure."
            } catch {
                studyMessage = "Motion history unavailable: \(error.localizedDescription)"
            }
            isQueryingMotion = false
        }
    }
}
