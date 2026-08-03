import Foundation

/// Canonical reference for the 50 US states, used to filter and normalize the
/// "States" breakdown to real US states only, regardless of whether reverse
/// geocoding returned an abbreviation ("CA") or a full name ("California").
enum USState {

    static let abbreviationToFullName: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
        "CA": "California", "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
        "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas",
        "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
        "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi",
        "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah",
        "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
        "WI": "Wisconsin", "WY": "Wyoming",
    ]

    static let allFullNames: Set<String> = Set(abbreviationToFullName.values)

    static let count = abbreviationToFullName.count

    /// Resolves a raw geocoded value (abbreviation or full name, any case) to its
    /// canonical full name. Returns `nil` if the value isn't one of the 50 US states
    /// (e.g. a foreign province/region, or an unrecognized string).
    static func canonicalFullName(for rawState: String) -> String? {
        let trimmed = rawState.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let full = abbreviationToFullName[trimmed.uppercased()] {
            return full
        }
        return allFullNames.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
}
