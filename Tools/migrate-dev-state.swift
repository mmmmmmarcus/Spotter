import Foundation

private let sourceBundleID = "com.spotter.app.dev"
private let destinationBundleID = "com.spotter.app"
private let fileManager = FileManager.default

private let fixedPreferenceKeys: Set<String> = [
    "boundAppBundleIDs",
    "boundCustomCommandIDs",
    "boundPaneBundleIDs",
    "clipboardDisabledApps",
    "clipboardRetentionDays",
    "compactMode",
    "customCommands",
    "emojiSkinTone",
    "favoriteApps",
    "hiddenLauncherItems",
    "hiddenLauncherKinds",
    "hyperKeyIncludesShift",
    "hyperKeyPhysicalKey",
    "hyperKeyQuickPress",
    "hyperKeyReplacesGlyph",
    "launcherSearchScopes",
    "openOnCursorScreen",
    "popToRootTimeout",
    "showFavoritesInCompactMode",
    "showInMenuBar",
]

private let safeCacheFiles = [
    "calculator-history.json",
    "clipboard.sqlite3",
    "clipboard.sqlite3-shm",
    "clipboard.sqlite3-wal",
    "emoji-frequency.json",
    "launcher-ranking.json",
]

private func copyIfMissing(from source: URL, to destination: URL) throws -> Bool {
    guard fileManager.fileExists(atPath: source.path) else { return false }
    guard !fileManager.fileExists(atPath: destination.path) else { return false }
    try fileManager.copyItem(at: source, to: destination)
    return true
}

private func mergeDirectory(from source: URL, to destination: URL) throws -> Int {
    guard fileManager.fileExists(atPath: source.path) else { return 0 }
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    let entries = try fileManager.contentsOfDirectory(
        at: source, includingPropertiesForKeys: [.isDirectoryKey])
    var copied = 0
    for entry in entries {
        let target = destination.appendingPathComponent(entry.lastPathComponent)
        let isDirectory =
            try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        if isDirectory {
            copied += try mergeDirectory(from: entry, to: target)
        } else if try copyIfMissing(from: entry, to: target) {
            copied += 1
        }
    }
    return copied
}

private let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
private let destinationSupportURL = libraryURL
    .appendingPathComponent("Application Support", isDirectory: true)
    .appendingPathComponent(destinationBundleID, isDirectory: true)
private let migrationMarkerURL = destinationSupportURL
    .appendingPathComponent("dev-state-migrated-v1")

if fileManager.fileExists(atPath: migrationMarkerURL.path) {
    print("Dev state migration already completed.")
    exit(EXIT_SUCCESS)
}

let defaults = UserDefaults.standard
let sourceDomain = defaults.persistentDomain(forName: sourceBundleID) ?? [:]
var destinationDomain = defaults.persistentDomain(forName: destinationBundleID) ?? [:]
var migratedPreferenceCount = 0
var migratedPreferenceKeys: Set<String> = []

for (key, value) in sourceDomain {
    let isHotKey = key.hasPrefix("KeyboardShortcuts_")
    guard fixedPreferenceKeys.contains(key) || isHotKey else { continue }
    guard destinationDomain[key] == nil else { continue }
    destinationDomain[key] = value
    migratedPreferenceCount += 1
    migratedPreferenceKeys.insert(key)
}

precondition(!migratedPreferenceKeys.contains("currencyRatesEnabled"))
defaults.setPersistentDomain(destinationDomain, forName: destinationBundleID)
defaults.synchronize()

let sourceCacheURL = libraryURL
    .appendingPathComponent("Caches", isDirectory: true)
    .appendingPathComponent(sourceBundleID, isDirectory: true)
let destinationCacheURL = libraryURL
    .appendingPathComponent("Caches", isDirectory: true)
    .appendingPathComponent(destinationBundleID, isDirectory: true)
try fileManager.createDirectory(at: destinationCacheURL, withIntermediateDirectories: true)

var migratedCacheCount = 0
for fileName in safeCacheFiles {
    if try copyIfMissing(
        from: sourceCacheURL.appendingPathComponent(fileName),
        to: destinationCacheURL.appendingPathComponent(fileName))
    {
        migratedCacheCount += 1
    }
}
migratedCacheCount += try mergeDirectory(
    from: sourceCacheURL.appendingPathComponent("images", isDirectory: true),
    to: destinationCacheURL.appendingPathComponent("images", isDirectory: true))

let sourceSupportURL = libraryURL
    .appendingPathComponent("Application Support", isDirectory: true)
    .appendingPathComponent(sourceBundleID, isDirectory: true)
try fileManager.createDirectory(at: destinationSupportURL, withIntermediateDirectories: true)
_ = try copyIfMissing(
    from: sourceSupportURL.appendingPathComponent("onboarded"),
    to: destinationSupportURL.appendingPathComponent("onboarded"))
try Data().write(to: migrationMarkerURL, options: .atomic)

print(
    "Migrated \(migratedPreferenceCount) preference keys and "
        + "\(migratedCacheCount) cache items; network consent was not migrated.")
