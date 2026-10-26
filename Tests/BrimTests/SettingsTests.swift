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
    }

    func testRoundTripKeepsEveryField() {
        let store = JSONSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        var settings = Settings()
        settings.hoverDelay = 0.3
        settings.collapseDelay = 0.8
        settings.launchAtLogin = true
        settings.enabledModules = ["clock", "media"]
        settings.showOnNonNotchedDisplays = false
        settings.preferredPlayerBundleID = "com.spotify.client"
        settings.agentFinishedRetentionMinutes = 30

        store.save(settings)
        XCTAssertEqual(store.load(), settings)
    }

    func testUnversionedFileMigratesAndKeepsValues() throws {
        let data = Data(#"{"hoverDelay": 0.4, "enabledModules": ["media"], "showOnNonNotchedDisplays": false}"#.utf8)
        let settings = try SettingsMigrator.migrate(data)

        XCTAssertEqual(settings.schemaVersion, Settings.currentSchemaVersion)
        XCTAssertEqual(settings.hoverDelay, 0.4)
        XCTAssertEqual(settings.enabledModules, ["media"])
        XCTAssertFalse(settings.showOnNonNotchedDisplays)
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
        XCTAssertFalse(settings.showOnNonNotchedDisplays)
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
