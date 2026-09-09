import Foundation

@main
struct SettingsSyncTests {
    static func main() async throws {
        var revision = CoordinatedFileRevision()
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        precondition(!revision.isCurrent(first))
        revision.record(first)
        precondition(revision.isCurrent(first))
        precondition(!revision.isCurrent(second))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spotter-settings-sync-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("Settings.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let io = CoordinatedFileIO()
        try await io.write(first, to: file)
        let firstRead = try await io.read(from: file)
        precondition(firstRead == first)
        try await io.write(second, to: file)
        let secondRead = try await io.read(from: file)
        precondition(secondRead == second)
        precondition(FileManager.default.fileExists(atPath: file.path))

        let changed = DispatchSemaphore(value: 0)
        let watcher = CoordinatedFileWatcher(url: file) { changed.signal() }
        try Data("external replacement".utf8).write(to: file, options: .atomic)
        let observed = await Task.detached {
            waitForChange(changed)
        }.value
        watcher.stop()
        precondition(observed)

        testFixtureCoversEveryField()
        testSettingsRoundTrip()
        testCredentialsRoundTrip()
        testOlderFileLeavesNewFieldsUnset()
        testUnknownFieldsAreIgnored()
        testEmptyObjectDecodesToAllUnset()
        print("Settings Sync: ALL PASSED")
    }

    private static func waitForChange(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now() + 3) == .success
    }

    // MARK: - Backup format

    /// Every field set to a distinguishable value, so a round trip that drops one is a failure and
    /// `testFixtureCoversEveryField` fails the moment a new field is added without one.
    private static func populatedSettings() -> SettingsBackupData {
        SettingsBackupData(
            clipboardRetentionDays: 30,
            clipboardDisabledApps: ["com.apple.Passwords"],
            launchAtLogin: true,
            hyperKey: "capsLock",
            hyperKeyIncludesShift: false,
            hyperKeyQuickPress: "escape",
            hyperKeyReplacesGlyph: true,
            emojiSkinTone: "medium",
            showInMenuBar: false,
            showInDock: true,
            popToRootSeconds: 15,
            compactMode: true,
            showFavoritesInCompactMode: false,
            searchScopes: ["/Applications"],
            openOnCursorScreen: false,
            launcherSectionOrder: ["favorites", "apps"],
            launcherHiddenSections: ["commands"],
            preferredTerminal: "iterm",
            remembersPalettePosition: true,
            lockInputToEnglish: true,
            openRouterAPIKey: "sk-or-test-key",
            openRouterDefinitionModel: "vendor/define",
            openRouterGrammarModel: "vendor/grammar",
            openRouterChatModel: "vendor/chat",
            openRouterChatWebSearch: true,
            googleTranslationAPIKey: "google-test-key",
            googleTranslationEnabled: true,
            googleTranslationTargets: ["ja", "fr", "de"],
            updateAutoCheckEnabled: true,
            currencyRatesEnabled: true,
            dashboardWidgets: SettingsBackupData.DashboardWidgets(
                widgetOrder: ["clock", "weather"],
                calendarSourceIdentifier: "calendar-id",
                includesAllDayEvents: false,
                clockTimeZoneIdentifier: "Asia/Tokyo",
                weatherEnabled: true,
                weatherCity: Data("city".utf8),
                weatherUnit: "celsius"))
    }

    private static func populatedPluginPrefs() -> SettingsBackupPluginPrefs {
        SettingsBackupPluginPrefs(
            changeCase: SettingsBackupPluginPrefs.ChangeCase(
                source: "selectedText", primaryAction: "paste", preserveCase: true,
                preservePunctuation: false, exceptions: "iOS", prefix: "<", suffix: ">",
                pinned: ["camel"], recent: ["snake"], disabled: ["kebab"]),
            killProcess: SettingsBackupPluginPrefs.KillProcess(
                sort: "cpu", groupApps: true, searchPaths: false, searchPIDs: true,
                prioritizeApps: true, showPID: false, showPath: true, refreshSeconds: 3.5),
            imageModification: SettingsBackupPluginPrefs.ImageModification(
                output: "alongside", format: "png"),
            screenshot: SettingsBackupPluginPrefs.Screenshot(
                roundedCorners: true, captureScale: "retina", fileFormat: "png",
                includesWindowShadow: false, hidesSpotterWindows: true, previewDuration: 4.5),
            selectionTools: SettingsBackupPluginPrefs.SelectionTools(
                definitionPrompt: "define this", grammarPrompt: "fix this"),
            caffeinate: SettingsBackupPluginPrefs.Caffeinate(
                keepsDisplayAwake: true, keepsDiskAwake: false),
            windowManagement: SettingsBackupPluginPrefs.WindowManagement(
                gap: 8, cycleOnRepeat: true),
            mole: SettingsBackupPluginPrefs.Mole(binaryPath: "/opt/homebrew/bin/mole"),
            note: SettingsBackupPluginPrefs.Note(
                windowTransparency: 0.25, autoWindowSizing: false),
            dashboardWidgets: SettingsBackupData.DashboardWidgets(
                widgetOrder: ["uptime"],
                calendarSourceIdentifier: "legacy",
                includesAllDayEvents: true,
                clockTimeZoneIdentifier: "UTC",
                weatherEnabled: false,
                weatherCity: Data(),
                weatherUnit: "fahrenheit"))
    }

    /// Walks the fixtures with `Mirror` so adding a field to the format without adding it here fails
    /// the harness instead of silently going untested.
    private static func testFixtureCoversEveryField() {
        assertNoUnsetField(populatedSettings(), path: "SettingsBackupData")
        assertNoUnsetField(populatedPluginPrefs(), path: "SettingsBackupPluginPrefs")
    }

    private static func assertNoUnsetField(_ value: Any, path: String) {
        for child in Mirror(reflecting: value).children {
            let name = child.label ?? "?"
            guard let unwrapped = unwrap(child.value) else {
                fatalError("\(path).\(name) is unset in the round-trip fixture")
            }
            if String(reflecting: type(of: unwrapped)).contains("SettingsBackup") {
                assertNoUnsetField(unwrapped, path: "\(path).\(name)")
            }
        }
    }

    /// `Optional.none` reflects as an optional with no children; anything else is a real value.
    private static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }

    private static func testSettingsRoundTrip() {
        let settings = populatedSettings()
        let decodedSettings = try! decode(SettingsBackupData.self, from: encode(settings))
        precondition(
            encode(decodedSettings) == encode(settings),
            "a settings field did not survive encode → decode")
        precondition(decodedSettings.currencyRatesEnabled == true)
        precondition(decodedSettings.updateAutoCheckEnabled == true)
        precondition(decodedSettings.dashboardWidgets?.weatherEnabled == true)
        precondition(decodedSettings.dashboardWidgets?.weatherCity == Data("city".utf8))

        let prefs = populatedPluginPrefs()
        let decodedPrefs = try! decode(SettingsBackupPluginPrefs.self, from: encode(prefs))
        precondition(
            encode(decodedPrefs) == encode(prefs),
            "a plugin preference did not survive encode → decode")
        precondition(decodedPrefs.note?.windowTransparency == 0.25)
    }

    /// The owner's explicit ask: both API keys and the translate target list must come back intact.
    private static func testCredentialsRoundTrip() {
        let decoded = try! decode(SettingsBackupData.self, from: encode(populatedSettings()))
        precondition(decoded.openRouterAPIKey == "sk-or-test-key")
        precondition(decoded.googleTranslationAPIKey == "google-test-key")
        precondition(decoded.googleTranslationTargets == ["ja", "fr", "de"])
    }

    /// A v3 file written before a field existed must decode, and that field must read as "unset" —
    /// which is what makes the apply path leave this Mac's own value alone rather than resetting it.
    private static func testOlderFileLeavesNewFieldsUnset() {
        let newFields = ["currencyRatesEnabled"]
        var object = jsonObject(encode(populatedSettings()))
        for field in newFields {
            precondition(object[field] != nil, "\(field) is missing from the fixture")
            object.removeValue(forKey: field)
        }
        let older = try! JSONSerialization.data(withJSONObject: object)
        let decoded = try! decode(SettingsBackupData.self, from: older)
        precondition(decoded.currencyRatesEnabled == nil)
        // Everything the older file did carry is still there.
        precondition(decoded.openRouterAPIKey == "sk-or-test-key")
        precondition(decoded.googleTranslationTargets == ["ja", "fr", "de"])
        precondition(decoded.updateAutoCheckEnabled == true)
    }

    /// Synthesized `Codable` — no hand-written `CodingKeys`, no custom `init(from:)` — so a file from
    /// a newer build decodes here instead of throwing.
    private static func testUnknownFieldsAreIgnored() {
        var object = jsonObject(encode(populatedSettings()))
        object["aSettingFromTheFuture"] = ["nested": true]
        object["anotherOne"] = 7
        let data = try! JSONSerialization.data(withJSONObject: object)
        let decoded = try! decode(SettingsBackupData.self, from: data)
        precondition(decoded.currencyRatesEnabled == true)
        precondition(decoded.openRouterAPIKey == "sk-or-test-key")
    }

    private static func testEmptyObjectDecodesToAllUnset() {
        let decoded = try! decode(SettingsBackupData.self, from: Data("{}".utf8))
        for child in Mirror(reflecting: decoded).children {
            precondition(
                unwrap(child.value) == nil,
                "\(child.label ?? "?") decoded as a value from an empty object")
        }
        let prefs = try! decode(SettingsBackupPluginPrefs.self, from: Data("{}".utf8))
        for child in Mirror(reflecting: prefs).children {
            precondition(
                unwrap(child.value) == nil,
                "\(child.label ?? "?") decoded as a value from an empty object")
        }
    }

    private static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try! encoder.encode(value)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    private static func jsonObject(_ data: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}
