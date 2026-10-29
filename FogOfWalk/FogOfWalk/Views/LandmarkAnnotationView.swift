import MapKit
import UIKit

/// Immutable presentation data; annotations never hold Core Data objects.
struct LandmarkPin: Equatable {
    let identifier: String
    let name: String
    let category: String
    let coordinate: CLLocationCoordinate2D
    let isDiscovered: Bool

    init(identifier: String, name: String, category: String,
         coordinate: CLLocationCoordinate2D, isDiscovered: Bool) {
        self.identifier = identifier
        self.name = name
        self.category = category
        self.coordinate = coordinate
        self.isDiscovered = isDiscovered
    }

    init(landmark: Landmark) {
        self.init(identifier: landmark.identifier, name: landmark.name, category: landmark.category,
                  coordinate: CLLocationCoordinate2D(latitude: landmark.latitude, longitude: landmark.longitude),
                  isDiscovered: landmark.isDiscovered)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identifier == rhs.identifier && lhs.name == rhs.name && lhs.category == rhs.category
            && lhs.isDiscovered == rhs.isDiscovered
            && lhs.coordinate.latitude == rhs.coordinate.latitude
            && lhs.coordinate.longitude == rhs.coordinate.longitude
    }
}

final class LandmarkAnnotation: NSObject, MKAnnotation {
    private(set) var pin: LandmarkPin
    var identifier: String { pin.identifier }
    @objc dynamic var title: String? { pin.isDiscovered ? pin.name : nil }
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(pin: LandmarkPin) {
        self.pin = pin
        coordinate = pin.coordinate
        super.init()
    }

    @discardableResult
    func update(pin: LandmarkPin) -> Bool {
        precondition(pin.identifier == identifier)
        guard self.pin != pin else { return false }
        let titleChanged = title != (pin.isDiscovered ? pin.name : nil)
        if titleChanged { willChangeValue(forKey: "title") }
        self.pin = pin
        if coordinate.latitude != pin.coordinate.latitude || coordinate.longitude != pin.coordinate.longitude {
            coordinate = pin.coordinate
        }
        if titleChanged { didChangeValue(forKey: "title") }
        return true
    }
}

/// MapKit positions each view; icon, pill and name retain their size and orientation.
/// No sibling hit-test surface or gesture recognizer stands between a pin and the map.
final class LandmarkAnnotationView: MKAnnotationView {
    static let reuseID = "landmark"
    static let categoryIcon: [String: String] = [
        "stadium": "sportscourt.fill", "museum": "building.columns.fill",
        "nationalPark": "leaf.fill", "airport": "airplane", "amusementPark": "ferriswheel",
        "zoo": "pawprint.fill", "university": "graduationcap.fill", "theater": "theatermasks.fill",
        "library": "books.vertical.fill", "landmark": "star.fill"
    ]

    private var renderedPin: LandmarkPin?
    private var renderedStyle: UIUserInterfaceStyle?

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: LandmarkAnnotationView, _: UITraitCollection) in
            view.configure()
        }
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        configure()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        renderedPin = nil
        image = nil
        isEnabled = false
        isAccessibilityElement = false
        accessibilityLabel = nil
        accessibilityIdentifier = nil
    }

    func configure() {
        guard let pin = (annotation as? LandmarkAnnotation)?.pin else { return }
        displayPriority = .required
        clusteringIdentifier = nil
        canShowCallout = false
        isDraggable = false
        isEnabled = pin.isDiscovered
        isAccessibilityElement = pin.isDiscovered
        accessibilityTraits = pin.isDiscovered ? .button : []
        accessibilityLabel = pin.isDiscovered ? pin.name : nil
        accessibilityIdentifier = "landmark-\(pin.identifier)"
        guard renderedPin != pin || renderedStyle != traitCollection.userInterfaceStyle else { return }
        renderedPin = pin
        renderedStyle = traitCollection.userInterfaceStyle
        // Render each native annotation's fixed-size contents only on data, reuse or
        // appearance changes; MapKit handles its position and gesture interaction.
        traitCollection.performAsCurrent {
            let symbol = pin.isDiscovered ? Self.categoryIcon[pin.category] ?? "mappin.circle.fill"
                : "questionmark.circle.fill"
            let config = UIImage.SymbolConfiguration(pointSize: pin.isDiscovered ? 18 : 16,
                                                     weight: pin.isDiscovered ? .bold : .medium)
            let icon = (UIImage(systemName: symbol, withConfiguration: config)
                ?? UIImage(systemName: "mappin.circle.fill", withConfiguration: config))!
                .withTintColor(pin.isDiscovered ? .systemBlue : .secondaryLabel.withAlphaComponent(0.6),
                               renderingMode: .alwaysOriginal)
            if pin.isDiscovered {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: UIColor.label
                ]
                let name = pin.name as NSString
                let labelSize = name.size(withAttributes: attrs)
                let pillSize = CGSize(width: icon.size.width + 10, height: icon.size.height + 10)
                let size = CGSize(width: max(pillSize.width, labelSize.width),
                                  height: pillSize.height + 8 + labelSize.height)
                image = UIGraphicsImageRenderer(size: size).image { _ in
                    let pill = CGRect(x: (size.width - pillSize.width) / 2, y: 0,
                                      width: pillSize.width, height: pillSize.height)
                    UIColor.systemBackground.withAlphaComponent(0.9).setFill()
                    UIBezierPath(roundedRect: pill, cornerRadius: pillSize.height / 2).fill()
                    icon.draw(at: CGPoint(x: pill.minX + 5, y: 5))
                    name.draw(at: CGPoint(x: (size.width - labelSize.width) / 2, y: pillSize.height + 8),
                              withAttributes: attrs)
                }
                // Four points below the pill and four above the label.
                centerOffset = CGPoint(x: 0, y: image!.size.height / 2 - pillSize.height - 4)
            } else {
                image = UIGraphicsImageRenderer(size: icon.size).image { _ in
                    icon.draw(at: .zero, blendMode: .normal, alpha: 0.5)
                }
                centerOffset = .zero
            }
        }
    }
}
