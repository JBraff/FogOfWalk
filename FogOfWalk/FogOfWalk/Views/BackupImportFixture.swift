#if DEBUG
import SwiftUI

/// Exercises the production import controls without opening storage or starting tracking.
struct BackupImportFixture: View {
    static func isRequested(arguments: [String]) -> Bool {
        arguments.contains("-backup-import-fixture")
    }

    @State private var pending = false
    @State private var result = "No import"

    var body: some View {
        Form {
            Button("Load Fictional Backup") { pending = true; result = "No import" }
            if pending {
                BackupImportControls(
                    onMerge: { result = "Merged"; pending = false },
                    onReplace: { result = "Replaced"; pending = false },
                    onCancel: { result = "Cancelled"; pending = false })
            }
            Text(result).accessibilityIdentifier("import-result")
        }
    }
}
#endif
