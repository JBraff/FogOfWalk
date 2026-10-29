#if DEBUG
import SwiftUI
import MapKit
import CoreData

/// Deterministic, in-memory map for XCUITest gestures. Never compiled into Release builds.
struct LandmarkInteractionFixture: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LandmarkFixtureController { LandmarkFixtureController() }
    func updateUIViewController(_ controller: LandmarkFixtureController, context: Context) {}
}

final class LandmarkFixtureController: UIViewController {
    private let map = MKMapView()
    private let coordinator: MapContainerView.Coordinator
    private let status = UILabel()
    private let geometry = UILabel()
    private var tapCount = 0
    private var originalSize: CGSize?
    private var edgeAdded = false
    private let center = CLLocationCoordinate2D(latitude: 40, longitude: -74)

    init() {
        let container = NSPersistentContainer(name: "FogOfWalk")
        let desc = NSPersistentStoreDescription()
        desc.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [desc]
        container.loadPersistentStores { _, error in precondition(error == nil) }
        let settings = GridSettings()
        settings.showLandmarks = true
        coordinator = MapContainerView.Coordinator(store: ExplorationStore(container: container),
            gridSettings: settings, landmarkStore: LandmarkStore(container: container),
            searchService: LandmarkSearchService(source: EmptyLandmarkSource()))
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        map.delegate = coordinator
        map.accessibilityIdentifier = "fixture-map"
        map.isPitchEnabled = false
        map.showsCompass = false
        map.addOverlay(FogOverlay(), level: .aboveLabels)
        coordinator.onLandmarkTapped = { [weak self] _ in
            guard let self else { return }
            tapCount += 1
            status.text = "Taps: \(tapCount)"
        }
        coordinator.landmarkStore.addLandmarks([
            WikidataLandmark(id: "Q1", name: "Fixture Museum", description: nil, lat: 40, lon: -74,
                             category: "museum", imageURL: nil)
        ], visitedCells: [GridMath.cellID(for: center)])
        status.text = "Taps: 0"
        status.accessibilityIdentifier = "fixture-status"
        geometry.text = "Unchecked"
        geometry.accessibilityIdentifier = "fixture-geometry"
        let controls = UIStackView(arrangedSubviews: [status, geometry,
            button("Reset map") { [weak self] in self?.reset() },
            button("Read map") { [weak self] in self?.inspect() },
            button("Make hint") { [weak self] in self?.setDiscovery(false) },
            button("Discover hint") { [weak self] in self?.setDiscovery(true) }])
        controls.axis = .vertical
        controls.spacing = 4
        map.translatesAutoresizingMaskIntoConstraints = false
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(map)
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            map.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            map.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            map.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            map.bottomAnchor.constraint(equalTo: controls.topAnchor),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            controls.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reset()
    }

    private func button(_ title: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func reset() {
        map.setRegion(MKCoordinateRegion(center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)), animated: false)
        if !edgeAdded {
            let edge = map.convert(CGPoint(x: -40, y: map.bounds.midY + 100), toCoordinateFrom: map)
            coordinator.landmarkStore.addLandmarks([
                WikidataLandmark(id: "Q2", name: "Edge Museum", description: nil,
                    lat: edge.latitude, lon: edge.longitude, category: "museum", imageURL: nil)
            ], visitedCells: [GridMath.cellID(for: edge)])
            edgeAdded = true
        }
        coordinator.refreshLandmarks(in: map.region, mapView: map)
    }

    private func setDiscovery(_ discovered: Bool) {
        // Fixture-only state change, including resetting a discovery for the inert-hint check.
        guard let landmark = coordinator.landmarkStore.allLandmarks.first else { return }
        landmark.isDiscovered = discovered
        coordinator.refreshLandmarks(in: map.region, mapView: map)
    }

    private func inspect(attempt: Int = 0) {
        status.text = String(format: "Camera: %.6f,%.6f; Taps: %d",
                             map.centerCoordinate.latitude, map.centerCoordinate.longitude, tapCount)
        guard let annotation = coordinator.landmarkAnnotations["Q1"],
              let marker = map.view(for: annotation) else {
            geometry.text = "Offscreen"
            return
        }
        let anchor = marker.convert(CGPoint(x: marker.bounds.midX - marker.centerOffset.x,
                                            y: marker.bounds.midY - marker.centerOffset.y), to: map)
        let expected = map.convert(annotation.coordinate, toPointTo: map)
        if originalSize == nil { originalSize = marker.bounds.size }
        let aligned = hypot(anchor.x - expected.x, anchor.y - expected.y) <= 1
        let fixed = marker.bounds.size == originalSize && marker.transform == .identity
        geometry.text = aligned && fixed ? "Aligned; fixed size"
            : "Mismatch dx=\(anchor.x - expected.x) dy=\(anchor.y - expected.y)"
        // Native deceleration may outlive XCUITest's idle check. Sample until it settles,
        // without changing the camera, annotation position or dimensions.
        if (!aligned || !fixed) && attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.inspect(attempt: attempt + 1)
            }
        }
    }
}
#endif
