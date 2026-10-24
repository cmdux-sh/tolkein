import Foundation

enum AppSettings {
    private static let urlKey = "workerURL"

    static var workerURL: String {
        get { suite?.string(forKey: urlKey) ?? "" }
        set { suite?.set(newValue, forKey: urlKey) }
    }

    private static var suite: UserDefaults? {
        UserDefaults(suiteName: AppIdentity.appGroup)
    }
}

enum SnapshotStore {
    static func load() -> UsageSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? SnapshotCoding.decoder().decode(UsageSnapshot.self, from: data)
    }

    static func save(_ snapshot: UsageSnapshot) throws {
        guard let url = fileURL else { return }
        let data = try SnapshotCoding.encoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppIdentity.appGroup)?
            .appendingPathComponent("snapshot.json", isDirectory: false)
    }
}
