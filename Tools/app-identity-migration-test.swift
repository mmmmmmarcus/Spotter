import Foundation

@main
struct AppIdentityMigrationTests {
    static func main() throws {
        var failures = 0
        func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
            if condition() {
                print("PASS  \(name)")
            } else {
                failures += 1
                print("FAIL  \(name)")
            }
        }

        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(
                "spotter-identity-migration-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Application Support", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        let suiteName = "spotter.identity-migration-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let legacyBundleID = suiteName + ".legacy"
        let currentBundleID = suiteName + ".current"

        defer {
            defaults.removePersistentDomain(forName: legacyBundleID)
            defaults.removePersistentDomain(forName: currentBundleID)
            defaults.removePersistentDomain(forName: suiteName)
            try? fileManager.removeItem(at: root)
        }

        try fileManager.createDirectory(
            at: support.appendingPathComponent("\(legacyBundleID)/Notes", isDirectory: true),
            withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: caches.appendingPathComponent(legacyBundleID, isDirectory: true),
            withIntermediateDirectories: true)
        try Data("legacy note".utf8).write(
            to: support.appendingPathComponent("\(legacyBundleID)/Notes/notes.json"))
        try Data().write(to: support.appendingPathComponent("\(legacyBundleID)/onboarded"))
        try Data("clipboard".utf8).write(
            to: caches.appendingPathComponent("\(legacyBundleID)/clipboard.sqlite3"))

        defaults.setPersistentDomain(
            [
                "plain": "legacy",
                "collision": "legacy",
                "\(legacyBundleID).showInDock": true,
            ], forName: legacyBundleID)
        defaults.setPersistentDomain(
            ["collision": "current"], forName: currentBundleID)

        let migrated = try AppIdentityMigration.migrateIfNeeded(
            currentBundleID: currentBundleID, legacyBundleID: legacyBundleID, defaults: defaults,
            applicationSupportRoot: support, cachesRoot: caches)
        let currentDomain =
            defaults.persistentDomain(forName: currentBundleID) ?? [:]

        expect(migrated, "migration runs once")
        expect(currentDomain["plain"] as? String == "legacy", "plain preference copied")
        expect(currentDomain["collision"] as? String == "current", "current preference wins")
        expect(
            currentDomain["\(currentBundleID).showInDock"] as? Bool == true,
            "bundle-prefixed preference remapped")
        expect(
            fileManager.fileExists(atPath: support.appendingPathComponent(
                "\(currentBundleID)/Notes/notes.json").path),
            "Application Support copied")
        expect(
            !fileManager.fileExists(atPath: support.appendingPathComponent(
                "\(currentBundleID)/onboarded").path),
            "onboarding marker intentionally omitted")
        expect(
            fileManager.fileExists(atPath: caches.appendingPathComponent(
                "\(currentBundleID)/clipboard.sqlite3").path),
            "cache content copied")
        expect(
            fileManager.fileExists(atPath: support.appendingPathComponent(
                "\(legacyBundleID)/Notes/notes.json").path),
            "legacy data retained")

        try Data("changed legacy note".utf8).write(
            to: support.appendingPathComponent("\(legacyBundleID)/Notes/notes.json"),
            options: .atomic)
        let reran = try AppIdentityMigration.migrateIfNeeded(
            currentBundleID: currentBundleID, legacyBundleID: legacyBundleID, defaults: defaults,
            applicationSupportRoot: support, cachesRoot: caches)
        let copiedData = try Data(contentsOf: support.appendingPathComponent(
            "\(currentBundleID)/Notes/notes.json"))
        expect(!reran, "migration is idempotent")
        expect(
            String(decoding: copiedData, as: UTF8.self) == "legacy note",
            "rerun does not overwrite")
        expect(
            AppIdentityMigration.legacyBundleID(for: AppIdentityMigration.betaBundleID)
                == AppIdentityMigration.legacyBetaBundleID,
            "beta identity maps to legacy beta")
        expect(
            AppIdentityMigration.legacyBundleID(for: "example.unrelated") == nil,
            "unrelated identities are ignored")

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
