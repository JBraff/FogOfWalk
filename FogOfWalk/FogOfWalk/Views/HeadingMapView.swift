import MapKit

/// A foreground-only compass for the location marker. It never requests locations or
/// changes the map camera, and is disabled alongside MapKit in the Study app.
final class MapHeadingController: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private let headingAvailable: Bool
    private var startedAt: Date?
    private(set) var heading: CLLocationDirection?
    var onChange: (() -> Void)?

    init(manager: CLLocationManager = CLLocationManager(),
         headingAvailable: Bool = CLLocationManager.headingAvailable()) {
        self.manager = manager
        self.headingAvailable = headingAvailable
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
    }

    func update(enabled: Bool, active: Bool, visible: Bool) {
        let authorized = manager.authorizationStatus == .authorizedAlways
            || manager.authorizationStatus == .authorizedWhenInUse
        let shouldRun = enabled && active && visible && authorized && headingAvailable
        guard shouldRun != (startedAt != nil) else { return }
        if shouldRun {
            startedAt = Date()
            manager.startUpdatingHeading()
        } else {
            startedAt = nil
            manager.stopUpdatingHeading()
            heading = nil
            onChange?()
        }
    }

    func setOrientation(_ orientation: UIInterfaceOrientation) {
        switch orientation {
        case .portraitUpsideDown: manager.headingOrientation = .portraitUpsideDown
        case .landscapeLeft: manager.headingOrientation = .landscapeRight
        case .landscapeRight: manager.headingOrientation = .landscapeLeft
        default: manager.headingOrientation = .portrait
        }
    }

    func receive(trueHeading: Double, magneticHeading: Double, accuracy: Double, timestamp: Date) {
        guard let startedAt, timestamp >= startedAt else { return }
        let value = trueHeading >= 0 ? trueHeading : magneticHeading
        heading = accuracy >= 0 && value.isFinite && (0..<360).contains(value) ? value : nil
        onChange?()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor [weak self] in
            self?.receive(trueHeading: newHeading.trueHeading, magneticHeading: newHeading.magneticHeading,
                          accuracy: newHeading.headingAccuracy, timestamp: newHeading.timestamp)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in self?.onChange?() }
    }
}

final class HeadingMapView: MKMapView {
    let headingController = MapHeadingController()
    var locationDisplayEnabled = false { didSet { updateHeading() } }
    var sceneActive = false { didSet { updateHeading() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        headingController.onChange = { [weak self] in
            self?.updateHeading()
            self?.updateHeadingMarker()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateHeading()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        headingController.setOrientation(window?.windowScene?.interfaceOrientation ?? .portrait)
    }

    private func updateHeading() {
        headingController.update(enabled: locationDisplayEnabled, active: sceneActive, visible: window != nil)
    }

    func updateHeadingMarker() {
        (view(for: userLocation) as? HeadingUserLocationView)?
            .setHeading(headingController.heading, mapHeading: camera.heading)
    }
}

/// Keep MapKit's blue dot and accuracy display; add only a small directional pointer.
final class HeadingUserLocationView: MKUserLocationView {
    private let pointerContainer = UIView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
    private(set) var displayedAngle: CGFloat?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        let pointer = UIImageView(image: UIImage(systemName: "triangle.fill"))
        pointer.tintColor = .systemBlue
        pointer.frame = CGRect(x: 24, y: 3, width: 16, height: 16)
        pointerContainer.addSubview(pointer)
        pointerContainer.isUserInteractionEnabled = false
        pointerContainer.isHidden = true
        addSubview(pointerContainer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        pointerContainer.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func setHeading(_ heading: CLLocationDirection?, mapHeading: CLLocationDirection) {
        displayedAngle = heading.map { CGFloat(($0 - mapHeading) * .pi / 180) }
        pointerContainer.isHidden = displayedAngle == nil
        pointerContainer.transform = CGAffineTransform(rotationAngle: displayedAngle ?? 0)
    }
}
