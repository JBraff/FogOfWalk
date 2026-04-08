import SwiftUI

/// A top-of-screen banner shown when the user has "While Using" location permission
/// but not "Always". Tapping "Open Settings" deep-links to the app's location settings page.
struct AlwaysLocationBanner: View {
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.fill")
                .foregroundStyle(.white)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Enable Background Location")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text("Fog of Walk can only track your walks when the app is open. Allow \u{201C}Always\u{201D} in Settings to record your path in the background.")
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
        .background(Color.accentColor)
        .accessibilityElement(children: .contain)
    }
}
