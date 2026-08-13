import Foundation

enum AppIdentityMigration {
    static let stableBundleID = "com.spotter.app1"
    static let betaBundleID = "com.spotter.app1.beta"
    static let legacyStableBundleID = "com.spotter.app"
    static let legacyBetaBundleID = "com.spotter.app.beta"

    private static let markerKey = "app-identity-migration.from-com.spotter.app.v1"

    static func runForCurrentApp() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        do {
            try migrateIfNeeded(currentBundleID: bundleID)
        } catch {
            NSLog("Spotter identity migration failed: %@", error.localizedDescription)
        }
    }

    @discardableResult
    static func migrateIfNeeded(
        currentBundleID: String,
        legacyBundleID overrideLegacyBundleID: String? = nil,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        applicationSupportRoot: URL? = nil,
        cachesRoot: URL? = nil
    ) throws -> Bool {
        let legacyBundleID: String
        if let overrideLegacyBundleID {
            legacyBundleID = overrideLegacyBundleID
        } else if let resolved = Self.legacyBundleID(for: currentBundleID) {
            legacyBundleID = resolved
        } else {
            return false
        }
        var currentDomain = defaults.persistentDomain(forName: currentBundleID) ?? [:]
        guard currentDomain[markerKey] as? Bool != true else { return false }

        if let legacyDomain = defaults.persistentDomain(forName: legacyBundleID) {
            for (key, value) in legacyDomain {
                let destinationKey = migratedKey(
                    key, from: legacyBundleID, to: currentBundleID)
                if currentDomain[destinationKey] == nil { currentDomain[destinationKey] = value }
            }
        }

        let supportRoot = applicationSupportRoot ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let cacheRoot = cachesRoot ?? fileManager
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try mergeDirectory(
            from: supportRoot.appendingPathComponent(legacyBundleID, isDirectory: true),
            to: supportRoot.appendingPathComponent(currentBundleID, isDirectory: true),
            excludingTopLevelNames: ["onboarded"], fileManager: fileManager)
        try mergeDirectory(
            from: cacheRoot.appendingPathComponent(legacyBundleID, isDirectory: true),
            to: cacheRoot.appendingPathComponent(currentBundleID, isDirectory: true),
            excludingTopLevelNames: [], fileManager: fileManager)

        currentDomain[markerKey] = true
        defaults.setPersistentDomain(currentDomain, forName: currentBundleID)
        return true
    }

    static func legacyBundleID(for currentBundleID: String) -> String? {
        switch currentBundleID {
        case stableBundleID: legacyStableBundleID
        case betaBundleID: legacyBetaBundleID
        default: nil
        }
    }

    private static func migratedKey(_ key: String, from legacy: String, to current: String) -> String {
        guard key.hasPrefix(legacy + ".") else { return key }
        return current + key.dropFirst(legacy.count)
    }

    private static func mergeDirectory(
        from source: URL, to destination: URL, excludingTopLevelNames: Set<String>,
        fileManager: FileManager
    ) throws {
        guard fileManager.fileExists(atPath: source.path) else { return }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fileManager.contentsOfDirectory(
            at: source, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        {
            guard !excludingTopLevelNames.contains(item.lastPathComponent) else { continue }
            let target = destination.appendingPathComponent(item.lastPathComponent)
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: item, to: target)
                continue
            }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                try mergeDirectory(
                    from: item, to: target, excludingTopLevelNames: [],
                    fileManager: fileManager)
            }
        }
    }
}
