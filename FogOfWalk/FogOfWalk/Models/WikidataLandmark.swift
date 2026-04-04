import Foundation

/// A landmark sourced from the bundled Wikidata dataset.
struct WikidataLandmark: Equatable {
    /// Wikidata QID (e.g. "Q12345") — stable unique identifier.
    let id: String
    let name: String
    /// Short description from Wikidata (e.g. "art museum in New York City").
    let description: String?
    let lat: Double
    let lon: Double
    /// Category string (e.g. "museum", "airport", "stadium").
    /// Matches the keys used in `LandmarkStore.categoryRadius` and
    /// `LandmarkOverlayView.categoryIcon`.
    let category: String
    /// Wikimedia Commons image URL, if available.
    let imageURL: String?
}
