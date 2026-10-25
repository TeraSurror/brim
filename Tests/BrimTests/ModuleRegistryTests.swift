import XCTest
@testable import BrimKit

@MainActor
final class ModuleRegistryTests: XCTestCase {
    private var clock: FakeModule!
    private var weather: FakeModule!
    private var calendar: FakeModule!
    private var registry: ModuleRegistry!

    override func setUp() async throws {
        clock = FakeModule(id: "clock")
        weather = FakeModule(id: "weather")
        calendar = FakeModule(id: "calendar")
        registry = ModuleRegistry(modules: [clock, weather, calendar])
    }

    func testEnabledModulesFollowSettingsOrder() {
        registry.apply(enabledIDs: ["calendar", "clock"])

        XCTAssertEqual(registry.enabledModules.map(\.id), ["calendar", "clock"])
        XCTAssertTrue(calendar.isEnabled)
        XCTAssertTrue(clock.isEnabled)
        XCTAssertFalse(weather.isEnabled)
    }

    func testUnknownAndDuplicateIDsAreIgnored() {
        registry.apply(enabledIDs: ["clock", "not-a-module", "clock", ""])
        XCTAssertEqual(registry.enabledModules.map(\.id), ["clock"])
    }

    func testEveryModuleIsToggledToTheRightState() {
        registry.apply(enabledIDs: ["clock"])
        XCTAssertEqual(clock.enableHistory, [true])
        XCTAssertEqual(weather.enableHistory, [false])
        XCTAssertEqual(calendar.enableHistory, [false])

        registry.apply(enabledIDs: ["weather"])
        XCTAssertEqual(clock.enableHistory, [true, false])
        XCTAssertEqual(weather.enableHistory, [false, true])
    }

    func testDisabledModulesAreTheComplement() {
        registry.apply(enabledIDs: ["clock"])
        XCTAssertEqual(registry.disabledModules.map(\.id), ["weather", "calendar"])

        registry.apply(enabledIDs: [])
        XCTAssertEqual(registry.disabledModules.map(\.id), ["clock", "weather", "calendar"])
    }

    func testLookupById() {
        XCTAssertEqual(registry.module(id: "weather")?.id, "weather")
        XCTAssertNil(registry.module(id: "missing"))
    }
}
