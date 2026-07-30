import CoreLocation
import MapKit
import UIKit

// MARK: - LandmarkPin (lightweight render struct)

struct LandmarkPin {
    let identifier:  String
    let name:        String
    let category:    String
    let coordinate:  CLLocationCoordinate2D
    let isDiscovered: Bool
}

// MARK: - LandmarkOverlayView

/// Transparent overlay above the fog MKOverlay. Draws discovered landmark icons above the
/// fog and undiscovered landmarks as hint "?" icons visible through it.
final class LandmarkOverlayView: UIView {

    var pins: [LandmarkPin] = []
    weak var mapView: MKMapView?

    // Cache rendered SF Symbol images — creating UIImage(systemName:) per pin per frame is expensive.
    private var imageCache: [String: UIImage] = [:]

    /// Override coordinate conversion for unit tests.
    var coordinateToPoint: ((CLLocationCoordinate2D) -> CGPoint)?

    /// Called when the user taps a pin. Receives the landmark identifier.
    var onPinTapped: ((String) -> Void)?

    // MARK: - Category icons

    static let categoryIcon: [String: String] = {
        var map: [String: String] = [:]

        // Wikidata category strings (bundled landmarks).
        map["stadium"]      = "sportscourt.fill"
        map["museum"]       = "building.columns.fill"
        map["nationalPark"] = "leaf.fill"
        map["airport"]      = "airplane"
        map["amusementPark"] = "ferriswheel"
        map["zoo"]          = "pawprint.fill"
        map["university"]   = "graduationcap.fill"
        map["theater"]      = "theatermasks.fill"
        map["library"]      = "books.vertical.fill"
        map["landmark"]     = "star.fill"

        return map
    }()

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        isOpaque        = false
        backgroundColor = .clear
        contentMode     = .redraw
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    // MARK: - Hit testing

    /// Only claim touches that land near a discovered pin; pass everything
    /// else through to the map so pan/zoom gestures work normally.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hitRadius: CGFloat = 30
        for pin in pins where pin.isDiscovered {
            guard let pinPoint = screenPoint(for: pin.coordinate) else { continue }
            let dx = point.x - pinPoint.x
            let dy = point.y - (pinPoint.y - 15)
            if sqrt(dx * dx + dy * dy) <= hitRadius {
                return self
            }
        }
        return nil
    }

    // MARK: - Update

    func update(pins: [LandmarkPin]) {
        self.pins = pins
        setNeedsDisplay()
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard coordinateToPoint != nil || mapView != nil else { return }

        for pin in pins {
            guard let point = screenPoint(for: pin.coordinate) else { continue }
            guard rect.insetBy(dx: -40, dy: -40).contains(point) else { continue }

            if pin.isDiscovered {
                drawDiscovered(pin: pin, at: point)
            } else {
                drawHint(at: point)
            }
        }
    }

    private func drawDiscovered(pin: LandmarkPin, at point: CGPoint) {
        let iconName = Self.categoryIcon[pin.category] ?? "mappin.circle.fill"
        let cacheKey = "discovered-\(iconName)"
        let image: UIImage
        if let cached = imageCache[cacheKey] {
            image = cached
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
            guard let rendered = UIImage(systemName: iconName, withConfiguration: config)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal) else { return }
            imageCache[cacheKey] = rendered
            image = rendered
        }

        // Background pill
        let pillSize = CGSize(width: image.size.width + 10, height: image.size.height + 10)
        let pillOrigin = CGPoint(x: point.x - pillSize.width / 2, y: point.y - pillSize.height - 4)
        let pillRect = CGRect(origin: pillOrigin, size: pillSize)
        let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillSize.height / 2)
        UIColor.systemBackground.withAlphaComponent(0.9).setFill()
        pill.fill()

        // Icon
        image.draw(at: CGPoint(x: pillOrigin.x + 5, y: pillOrigin.y + 5))

        // Name label
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9, weight: .semibold),
            .foregroundColor: UIColor.label
        ]
        let label = (pin.name as NSString)
        let labelSize = label.size(withAttributes: labelAttrs)
        let labelOrigin = CGPoint(
            x: point.x - labelSize.width / 2,
            y: point.y + 4
        )
        label.draw(at: labelOrigin, withAttributes: labelAttrs)
    }

    private func drawHint(at point: CGPoint) {
        let cacheKey = "hint"
        let image: UIImage
        if let cached = imageCache[cacheKey] {
            image = cached
        } else {
            let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
            guard let rendered = UIImage(systemName: "questionmark.circle.fill", withConfiguration: config)?
                .withTintColor(UIColor.secondaryLabel.withAlphaComponent(0.6), renderingMode: .alwaysOriginal) else { return }
            imageCache[cacheKey] = rendered
            image = rendered
        }

        let origin = CGPoint(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2)
        image.draw(at: origin, blendMode: .normal, alpha: 0.5)
    }

    // MARK: - Tap handling

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let tapPoint = gesture.location(in: self)
        let hitRadius: CGFloat = 30

        for pin in pins where pin.isDiscovered {
            guard let point = screenPoint(for: pin.coordinate) else { continue }
            let dx = tapPoint.x - point.x
            let dy = tapPoint.y - (point.y - 15) // offset to icon center
            if sqrt(dx * dx + dy * dy) <= hitRadius {
                onPinTapped?(pin.identifier)
                return
            }
        }
    }

    // MARK: - Helpers

    /// Direct coordinate→point conversion. Used only for hit-testing and tap
    /// handling (per-event, not per-frame), so N calls here is acceptable.
    private func screenPoint(for coordinate: CLLocationCoordinate2D) -> CGPoint? {
        if let converter = coordinateToPoint {
            return converter(coordinate)
        } else if let mapView {
            return mapView.convert(coordinate, toPointTo: self)
        }
        return nil
    }
}
