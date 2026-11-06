import Foundation

/// Bundle identifiers and the App Group live in `ios/Config/Shared.xcconfig`.
/// Replace every `PLACEHOLDER` before building. The Info.plist values are
/// expanded at build time so the app and the widget stay in lockstep.
enum AppIdentity {
    static var appGroup: String {
        bundleString("TolkeinsAppGroup", fallback: "group.PLACEHOLDER.tolkeins")
    }

    static var keychainAccessGroup: String {
        bundleString(
            "TolkeinsKeychainAccessGroup",
            fallback: "PLACEHOLDER.group.PLACEHOLDER.tolkeins"
        )
    }

    static let keychainService = "tolkeins.read-token"
    static let keychainAccount = "read-token"

    static var hasPlaceholderIdentity: Bool {
        let values = [appGroup, keychainAccessGroup]
        return values.contains { value in
            value.contains("PLACEHOLDER") || value.contains("$(")
        }
    }

    private static func bundleString(_ key: String, fallback: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return fallback
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
