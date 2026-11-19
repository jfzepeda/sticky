import Foundation

/// Locates the shared App Group container. The identifier comes from the
/// `StickyAppGroupID` Info.plist key, which XcodeGen fills from `STICKY_APP_GROUP`,
/// so app, widget and MCP helper always agree.
public enum AppGroup {
    public static let infoPlistKey = "StickyAppGroupID"
    public static let directoryName = "StickyDesk"
    public static let fileName = "notes.json"

    public static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String,
              !value.isEmpty, !value.contains("$(")
        else { return nil }
        return value
    }

    public static func storeURL(appGroupID: String? = identifier) throws -> URL {
        guard let appGroupID else { throw RepositoryError.appGroupNotConfigured }
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            throw RepositoryError.containerUnavailable(appGroupID)
        }
        return container
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
