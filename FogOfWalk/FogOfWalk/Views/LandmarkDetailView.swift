import MapKit
import SwiftUI

struct LandmarkDetailView: View {
    let landmark: Landmark
    @Environment(\.dismiss) private var dismiss

    private var categoryLabel: String {
        // Check Wikidata category strings first (new bundled landmarks).
        switch landmark.category {
        case "stadium":      return "Stadium / Arena"
        case "museum":       return "Museum"
        case "nationalPark": return "National Park"
        case "airport":      return "Airport"
        case "amusementPark": return "Amusement Park"
        case "zoo":          return "Zoo"
        case "university":   return "University"
        case "theater":      return "Theater"
        case "library":      return "Library"
        case "landmark":     return "Landmark"
        default: break
        }
        return landmark.category
    }

    private var iconName: String {
        LandmarkOverlayView.categoryIcon[landmark.category] ?? "mappin.fill"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon + name
                VStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.system(size: 52))
                        .foregroundStyle(.blue)

                    Text(landmark.name)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text(categoryLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Divider()

                // Details
                VStack(spacing: 12) {
                    if landmark.isDiscovered, let date = landmark.firstDiscovered {
                        LabeledContent("Discovered") {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else {
                        LabeledContent("Status") {
                            Text("Not yet discovered")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                // Open in Maps
                Button {
                    let mapItem = MKMapItem(placemark: MKPlacemark(
                        coordinate: .init(latitude: landmark.latitude, longitude: landmark.longitude)
                    ))
                    mapItem.name = landmark.name
                    mapItem.openInMaps()
                } label: {
                    Label("Open in Maps", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
