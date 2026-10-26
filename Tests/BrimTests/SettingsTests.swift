import XCTest
@testable import BrimKit

final class SettingsTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testMissingFileGivesDefaults() {
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        XCTAssertEqual(store.load(), Settings())
        XCTAssertFalse(store.hasSavedSettings)
    }

    func testNewInstallsStartWithNowPlayingAndTheClock() {
        XCTAssertEqual(Settings().enabledModules, ["media", "clock"])
    }

    func testSavingMarksTheStoreAsSaved() {
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        store.save(Settings())
        XCTAssertTrue(store.hasSavedSettings)
    }

    func testRoundTripKeepsEveryField() {
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        var settings = Settings()
        settings.hoverDelay = 0.3
        settings.collapseDelay = 0.8
        settings.launchAtLogin = true
        settings.enabledModules = ["clock", "media"]
        settings.displayMode = .mainOnly
        settings.preferredPlayerBundleID = "com.spotify.client"
        settings.agentFinishedRetentionMinutes = 30
        settings.agentNotificationsEnabled = true

        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testUnversionedFileMigratesAndKeepsValues() throws {
        let data = Data(#"{"hoverDelay": 0.4, "enabledModules": ["media"], "showOnNonNotchedDisplays": false}"#.utf8)
        let settings = try SettingsMigrator.migrate(data)

        XCTAssertEqual(settings.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(settings.hoverDelay, 0.4)
        XCTAssertEqual(settings.enabledModules, ["media"])
        XCTAssertEqual(settings.displayMode, .notchedOnly)
        XCTAssertEqual(settings.collapseDelay, Settings().collapseDelay)
    }

    func testSchemaOneFileMigratesToTheCurrentSchema() throws {
        let data = Data(
            #"{"schemaVersion":1,"hoverDelay":0.25,"enabledModules":["clock"],"showOnNonNotchedDisplays":false}"#
                .utf8
        )
        let settings = try SettingsMigrator.migrate(data)

        XCTAssertEqual(settings.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(settings.hoverDelay, 0.25)
        XCTAssertEqual(settings.displayMode, .notchedOnly)
        XCTAssertNil(settings.preferredPlayerBundleID)
        XCTAssertEqual(settings.agentFinishedRetentionMinutes, Settings().agentFinishedRetentionMinutes)
    }

    func testSchemaTwoFileMigratesToTheCurrentSchema() throws {
        let data = Data(
            #"{"schemaVersion":2,"hoverDelay":0.3,"preferredPlayerBundleID":"com.spotify.client"}"#
                .utf8
        )
        let settings = try SettingsMigrator.migrate(data)

        XCTAssertEqual(settings.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(settings.hoverDelay, 0.3)
        XCTAssertEqual(settings.preferredPlayerBundleID, "com.spotify.client")
        XCTAssertEqual(settings.agentFinishedRetentionMinutes, 10)
        XCTAssertFalse(settings.agentNotificationsEnabled)
    }

    func testSchemaThreeFileMigratesToTheCurrentSchema() throws {
        let data = Data(
            #"{"schemaVersion":3,"agentFinishedRetentionMinutes":30,"enabledModules":["clock","agents"]}"#
                .utf8
        )
        let settings = try SettingsMigrator.migrate(data)

        XCTAssertEqual(settings.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(settings.agentFinishedRetentionMinutes, 30)
        XCTAssertEqual(settings.enabledModules, ["clock", "agents"])
        XCTAssertFalse(settings.agentNotificationsEnabled)
    }

    func testSchemaFourFileMigratesWithHoverAndLiveNotchOn() throws {
        let data = Data(
            #"{"schemaVersion":4,"hoverDelay":0.3,"agentNotificationsEnabled":true,"enabledModules":["agents"]}"#
                .utf8
        )
        let settings = try SettingsMigrator.migrate(data)

        XCTAssertEqual(settings.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(settings.hoverDelay, 0.3)
        XCTAssertTrue(settings.agentNotificationsEnabled)
        XCTAssertEqual(settings.enabledModules, ["agents"])
        XCTAssertTrue(settings.opensOnHover)
        XCTAssertTrue(settings.showLiveActivity)
    }

    func testSchemaFiveHandleToggleBecomesADisplayMode() throws {
        let off = try SettingsMigrator.migrate(
            Data(#"{"schemaVersion":5,"showOnNonNotchedDisplays":false,"hoverDelay":0.3}"#.utf8))
        XCTAssertEqual(off.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(off.displayMode, .notchedOnly)
        XCTAssertEqual(off.hoverDelay, 0.3)

        let on = try SettingsMigrator.migrate(Data(#"{"schemaVersion":5,"showOnNonNotchedDisplays":true}"#.utf8))
        XCTAssertEqual(on.displayMode, .all)
    }

    func testOpenPanelShortcutRoundTripsAndDefaultsToNone() throws {
        XCTAssertNil(Settings().openPanelShortcut)
        var settings = Settings()
        settings.openPanelShortcut = HotKey(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space")
        let decoded = try SettingsMigrator.migrate(JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.openPanelShortcut, settings.openPanelShortcut)
    }

    func testAShortcutWithoutACommandKeyIsDroppedOnLoad() throws {
        let data = Data(
            #"{"schemaVersion":6,"openPanelShortcut":{"keyCode":0,"modifiers":4,"keyLabel":"A"},"hoverDelay":0.3}"#.utf8)
        let settings = try SettingsMigrator.migrate(data)
        XCTAssertNil(settings.openPanelShortcut)
        XCTAssertEqual(settings.hoverDelay, 0.3)
    }

    func testUnknownDisplayModeFallsBackToAllDisplays() throws {
        let settings = try SettingsMigrator.migrate(
            Data(#"{"schemaVersion":6,"displayMode":"ceilingOnly","hoverDelay":0.3}"#.utf8))
        XCTAssertEqual(settings.displayMode, .all)
        XCTAssertEqual(settings.hoverDelay, 0.3)
    }

    func testOpenModeAndLiveNotchRoundTrip() throws {
        var settings = Settings()
        settings.opensOnHover = false
        settings.showLiveActivity = false
        let data = try JSONEncoder().encode(settings)
        let decoded = try SettingsMigrator.migrate(data)
        XCTAssertFalse(decoded.opensOnHover)
        XCTAssertFalse(decoded.showLiveActivity)
    }

    func testAgentRetentionIsClampedToItsRange() throws {
        XCTAssertEqual(
            try SettingsMigrator.migrate(Data(#"{"agentFinishedRetentionMinutes": 999}"#.utf8))
                .agentFinishedRetentionMinutes,
            Settings.agentRetentionRange.upperBound
        )
        XCTAssertEqual(
            try SettingsMigrator.migrate(Data(#"{"agentFinishedRetentionMinutes": 0}"#.utf8))
                .agentFinishedRetentionMinutes,
            Settings.agentRetentionRange.lowerBound
        )
    }

    func testDelaysAreClampedToTheirRanges() throws {
        XCTAssertEqual(try SettingsMigrator.migrate(Data(#"{"hoverDelay": 99}"#.utf8)).hoverDelay,
                       Settings.hoverDelayRange.upperBound)
        XCTAssertEqual(try SettingsMigrator.migrate(Data(#"{"hoverDelay": 0}"#.utf8)).hoverDelay,
                       Settings.hoverDelayRange.lowerBound)
        XCTAssertEqual(try SettingsMigrator.migrate(Data(#"{"collapseDelay": 99}"#.utf8)).collapseDelay,
                       Settings.collapseDelayRange.upperBound)
        XCTAssertEqual(try SettingsMigrator.migrate(Data(#"{"collapseDelay": 0}"#.utf8)).collapseDelay,
                       Settings.collapseDelayRange.lowerBound)
    }

    func testCorruptFileIsBackedUpAndReset() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        try Data("not json".utf8).write(to: url)
        let store = JSONSettingsStore(fileURL: url)

        XCTAssertEqual(store.load(), Settings())
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("settings.corrupt-") })
    }

    func testSavedFileContainsTheCurrentSchemaVersion() throws {
        let url = directory.appendingPathComponent("settings.json")
        let store = JSONSettingsStore(fileURL: url)
        var settings = Settings()
        settings.schemaVersion = 0
        store.save(settings)

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(object?["schemaVersion"] as? Int, Settings.currentSchemaVersion)
    }
}
