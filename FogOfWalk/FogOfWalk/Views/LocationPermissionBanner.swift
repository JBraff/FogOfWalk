import SwiftUI

/// A top-of-screen banner for a location-permission problem: location denied, or
/// "While Using" granted without "Always". "Open Settings" deep-links to the app's settings.
struct LocationPermissionBanner: View {
    let prompt: LocationService.PermissionPrompt
    var onDismiss: () -> Void

    private var title: String {
        switch prompt {
        case .denied:          return "Location Access Is Off"
        case .upgradeToAlways: return "Enable Background Location"
        }
    }

    private var message: String {
        switch prompt {
        case .denied:
            return "Fog of Walk can\u{2019}t uncover the map without your location. Turn on location access in Settings and choose \u{201C}Always\u{201D} to record walks in the background."
        case .upgradeToAlways:
            return "Fog of Walk can only track your walks when the app is open. Allow \u{201C}Always\u{201D} in Settings to record your path in the background."
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: prompt == .denied ? "location.slash.fill" : "location.fill")
                .foregroundStyle(.white)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.white.opacity(0.25), in: Capsule())
                .padding(.top, 2)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.8))
            }
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(prompt == .denied ? Color.orange : Color.accentColor)
        .accessibilityElement(children: .contain)
    }
}
