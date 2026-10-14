import CoreLocation
import Foundation
import Observation

/// The proposed recording policy runs in shadow mode during the legacy baseline.
/// Nothing in this file decides whether exploration receives a location.
enum StudySampleValidator {
    enum Decision: String, Codable {
        case accepted
        case invalidCoordinate
        case invalidAccuracy
        case staleOrFuture
        case beforeSession
        case outOfOrder
    }

    static func assess(
        _ location: CLLocation,
        receivedAt: Date,
        sessionStartedAt: Date,
        lastAcceptedAt: Date?
    ) -> Decision {
        let coordinate = location.coordinate
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite,
              CLLocationCoordinate2DIsValid(coordinate) else { return .invalidCoordinate }
        guard location.horizontalAccuracy.isFinite,
              (0...25).contains(location.horizontalAccuracy) else { return .invalidAccuracy }
        let age = receivedAt.timeIntervalSince(location.timestamp)
        guard age.isFinite, (0...15).contains(age) else { return .staleOrFuture }
        guard location.timestamp >= sessionStartedAt else { return .beforeSession }
        if let lastAcceptedAt, location.timestamp <= lastAcceptedAt { return .outOfOrder }
        return .accepted
    }
}

@MainActor
protocol LocationDiagnosticRecording: AnyObject {
    func recordLifecycle(_ name: String, detail: String?)
    func recordBatch(_ locations: [CLLocation], receivedAt: Date, sessionStartedAt: Date?)
    func recordDownstream(cell: CellID, isNew: Bool, discoveries: Int, dayRollover: Bool)
}

/// An explicitly started, local-only JSONL capture in the separate `.study` app.
/// The normal app cannot start or resume a capture. Files are excluded from backup.
@MainActor
@Observable
final class LocationStudyDiagnostics: LocationDiagnosticRecording {
    static let shared = LocationStudyDiagnostics()
    static let studyBundleID = "com.jeremybraff.fogofwalk.study"
    static let maxBytes = 16 * 1_024 * 1_024
    static let retentionDays = 7

    struct Event: Codable {
        let kind: String
        let recordedAt: Date
        var detail: String? = nil
        var batchID: String? = nil
        var index: Int? = nil
        var batchCount: Int? = nil
        var sampleTime: Date? = nil
        var latitude: Double? = nil
        var longitude: Double? = nil
        var horizontalAccuracy: Double? = nil
        var speed: Double? = nil
        var ageSeconds: Double? = nil
        var shadowDecision: StudySampleValidator.Decision? = nil
        var forwarded: Bool? = nil
        var cellX: Int32? = nil
        var cellY: Int32? = nil
        var isNewCell: Bool? = nil
        var discoveries: Int? = nil
        var dayRollover: Bool? = nil
    }

    enum CaptureError: LocalizedError {
        case notStudyApp
        case alreadyCapturing

        var errorDescription: String? {
            switch self {
            case .notStudyApp: "Diagnostics require the separate study app."
            case .alreadyCapturing: "A diagnostic capture is already running."
            }
        }
    }

    let isStudyApp: Bool
    private let directoryURL: URL
    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    @ObservationIgnored private var handle: FileHandle?
    @ObservationIgnored private var byteCount = 0
    @ObservationIgnored private var shadowLastAcceptedAt: Date?
    @ObservationIgnored private var shadowSessionStartedAt: Date?

    private(set) var isCapturing = false
    private(set) var captureStartedAt: Date?
    private(set) var captureEndedAt: Date?
    private(set) var currentFileURL: URL?
    private(set) var motionFileURL: URL?
    private(set) var lastError: String?

    init(
        isStudyApp: Bool? = nil,
        directoryURL: URL? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.isStudyApp = isStudyApp ?? (Bundle.main.bundleIdentifier == Self.studyBundleID)
        self.defaults = defaults
        self.directoryURL = directoryURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("LocationStudy", isDirectory: true)
        let encoder = JSONEncoder()
        // Fractional seconds matter when comparing fix receipt with motion onset.
        encoder.dateEncodingStrategy = .millisecondsSince1970
        self.encoder = encoder

        guard self.isStudyApp else { return }
        try? prepareDirectory()
        removeExpiredFiles()
        if let name = defaults.string(forKey: "locationStudy.fileName") {
            let url = self.directoryURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                currentFileURL = url
                captureStartedAt = defaults.object(forKey: "locationStudy.startedAt") as? Date
                captureEndedAt = defaults.object(forKey: "locationStudy.endedAt") as? Date
                if defaults.bool(forKey: "locationStudy.active") {
                    do {
                        let fileHandle = try FileHandle(forWritingTo: url)
                        byteCount = Int(try fileHandle.seekToEnd())
                        handle = fileHandle
                        isCapturing = true
                        captureEndedAt = nil
                        recordLifecycle("process_relaunch", detail: nil)
                    } catch {
                        lastError = "Could not resume diagnostic capture: \(error.localizedDescription)"
                        defaults.set(false, forKey: "locationStudy.active")
                    }
                }
            }
        }
    }

    func startCapture(at date: Date = Date()) throws {
        guard isStudyApp else { throw CaptureError.notStudyApp }
        guard !isCapturing else { throw CaptureError.alreadyCapturing }
        try prepareDirectory()
        let url = directoryURL.appendingPathComponent("location-\(UUID().uuidString).jsonl")
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]) else { throw CocoaError(.fileWriteUnknown) }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        handle = try FileHandle(forWritingTo: url)
        currentFileURL = url
        captureStartedAt = date
        captureEndedAt = nil
        lastError = nil
        byteCount = 0
        shadowLastAcceptedAt = nil
        shadowSessionStartedAt = nil
        isCapturing = true
        defaults.set(url.lastPathComponent, forKey: "locationStudy.fileName")
        defaults.set(date, forKey: "locationStudy.startedAt")
        defaults.removeObject(forKey: "locationStudy.endedAt")
        defaults.set(true, forKey: "locationStudy.active")
        append(Event(kind: "capture_start", recordedAt: date, detail: "legacy"))
    }

    func stopCapture(at date: Date = Date()) {
        endCapture(at: date, recordStop: true)
    }

    private func endCapture(at date: Date, recordStop: Bool) {
        guard isCapturing else { return }
        if recordStop { append(Event(kind: "capture_stop", recordedAt: date)) }
        try? handle?.close()
        handle = nil
        isCapturing = false
        captureEndedAt = date
        defaults.set(false, forKey: "locationStudy.active")
        defaults.set(date, forKey: "locationStudy.endedAt")
    }

    func recordLifecycle(_ name: String, detail: String? = nil) {
        append(Event(kind: name, recordedAt: Date(), detail: detail))
    }

    func recordBatch(_ locations: [CLLocation], receivedAt: Date, sessionStartedAt: Date?) {
        guard isCapturing else { return }
        let batchID = UUID().uuidString
        append(Event(kind: "batch", recordedAt: receivedAt,
                     detail: "legacy", batchID: batchID, batchCount: locations.count))
        if shadowSessionStartedAt != sessionStartedAt {
            shadowSessionStartedAt = sessionStartedAt
            shadowLastAcceptedAt = nil
        }
        // Assess every delivered sample in timestamp order, while retaining its original
        // index. The legacy pipeline still forwards only locations.last unchanged.
        for (index, location) in locations.enumerated().sorted(by: {
            $0.element.timestamp < $1.element.timestamp
        }) {
            let decision = sessionStartedAt.map {
                StudySampleValidator.assess(
                    location, receivedAt: receivedAt, sessionStartedAt: $0,
                    lastAcceptedAt: shadowLastAcceptedAt
                )
            }
            if decision == .accepted { shadowLastAcceptedAt = location.timestamp }
            var event = Event(kind: "sample", recordedAt: receivedAt)
            event.batchID = batchID
            event.index = index
            event.batchCount = locations.count
            event.sampleTime = location.timestamp
            event.latitude = location.coordinate.latitude.isFinite ? location.coordinate.latitude : nil
            event.longitude = location.coordinate.longitude.isFinite ? location.coordinate.longitude : nil
            event.horizontalAccuracy = location.horizontalAccuracy.isFinite ? location.horizontalAccuracy : nil
            event.speed = location.speed.isFinite ? location.speed : nil
            event.ageSeconds = receivedAt.timeIntervalSince(location.timestamp)
            event.shadowDecision = decision
            event.forwarded = index == locations.count - 1
            append(event)
        }
    }

    func recordDownstream(cell: CellID, isNew: Bool, discoveries: Int, dayRollover: Bool) {
        var event = Event(kind: "downstream", recordedAt: Date())
        event.cellX = cell.x
        event.cellY = cell.y
        event.isNewCell = isNew
        event.discoveries = discoveries
        event.dayRollover = dayRollover
        append(event)
    }

    func saveMotionReference(_ result: StudyMotionReference.Result) throws {
        guard isStudyApp else { throw CaptureError.notStudyApp }
        try prepareDirectory()
        let url = directoryURL.appendingPathComponent("motion-\(UUID().uuidString).json")
        try encoder.encode(result).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
        motionFileURL = url
    }

    private func append(_ event: Event) {
        guard isCapturing, let handle else { return }
        do {
            var data = try encoder.encode(event)
            data.append(0x0A)
            if byteCount + data.count > Self.maxBytes {
                lastError = "Capture reached the 16 MiB limit and stopped."
                endCapture(at: Date(), recordStop: false)
                return
            }
            try handle.write(contentsOf: data)
            byteCount += data.count
        } catch {
            lastError = "Diagnostic write failed: \(error.localizedDescription)"
            endCapture(at: Date(), recordStop: false)
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directoryURL
        try url.setResourceValues(values)
    }

    private func removeExpiredFiles(now: Date = Date()) {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directoryURL, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        for url in urls where url.pathExtension == "jsonl" || url.lastPathComponent.hasPrefix("motion-") {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified < cutoff else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }
}
