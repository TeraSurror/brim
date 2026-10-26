import XCTest
@testable import BrimKit

@MainActor
final class AppModelTests: XCTestCase {
    private var store: FakeSettingsStore!
    private var loginItems: FakeLoginItems!
    private var permissions: FakePermissions!
    private var clock: FakeModule!
    private var media: FakeModule!
    private var agent: FakeAgentControllingModule!
    private var model: AppModel!

    override func setUp() async throws {
        var settings = Settings()
        settings.enabledModules = ["clock"]
        store = FakeSettingsStore(settings)
        loginItems = FakeLoginItems()
        permissions = FakePermissions()
        clock = FakeModule(id: "clock", permissions: [])
        media = FakeModule(id: "media", permissions: [.automation], explanation: "Brim needs to talk to Music and Spotify.")
        agent = FakeAgentControllingModule()
        let registry = ModuleRegistry(modules: [clock, media, agent])
        model = AppModel(
            store: store,
            loginItems: loginItems,
            registry: registry,
            permissions: permissions
        )
    }

    func testEnabledModulesAreActiveAtLaunch() {
        XCTAssertEqual(model.activeModules.map(\.id), ["clock"])
        XCTAssertEqual(model.disabledModules.map(\.id), ["media", "agents"])
    }

    func testAgentRetentionIsAppliedAtLaunchAndOnChange() {
        XCTAssertEqual(agent.appliedRetention, [Settings().agentFinishedRetentionMinutes])

        model.settings.agentFinishedRetentionMinutes = 30

        XCTAssertEqual(agent.appliedRetention, [Settings().agentFinishedRetentionMinutes, 30])
    }

    func testAgentSocketPathAndClearFinishedGoThroughTheModule() {
        XCTAssertEqual(model.agentSocketPath, agent.socketPath)

        model.clearFinishedAgentSessions()

        XCTAssertEqual(agent.clearFinishedCount, 1)
    }

    func testAgentNotificationSettingIsForwardedToTheModule() {
        XCTAssertFalse(agent.notificationsEnabled)

        model.settings.agentNotificationsEnabled = true

        XCTAssertTrue(agent.notificationsEnabled)
    }

    func testRequestingNotificationPermissionTurnsTheSettingOn() async {
        await model.requestAgentNotificationPermission()

        XCTAssertEqual(agent.notificationRequests, 1)
        XCTAssertEqual(model.agentNotificationAuthorization, .authorized)
        XCTAssertTrue(model.settings.agentNotificationsEnabled)
        XCTAssertNil(model.agentNotificationError)
    }

    func testDeniedSystemPermissionStillEnablesNotchAlerts() async {
        agent.requestResult = .denied

        await model.requestAgentNotificationPermission()

        XCTAssertEqual(model.agentNotificationAuthorization, .denied)
        XCTAssertTrue(model.settings.agentNotificationsEnabled)
        XCTAssertEqual(
            model.agentNotificationError,
            "macOS banners are unavailable; Brim will show a notch alert."
        )
    }

    func testLaunchStateComesFromTheSystemAndIsWrittenBack() {
        XCTAssertFalse(model.launchAtLogin)
        XCTAssertFalse(store.stored.launchAtLogin)
    }

    func testLaunchAtLoginTogglesTheServiceAndSettings() {
        model.setLaunchAtLogin(true)
        XCTAssertEqual(loginItems.setCalls, [true])
        XCTAssertTrue(model.launchAtLogin)
        XCTAssertTrue(store.stored.launchAtLogin)

        model.setLaunchAtLogin(false)
        XCTAssertEqual(loginItems.setCalls, [true, false])
        XCTAssertFalse(store.stored.launchAtLogin)
    }

    func testLaunchAtLoginFailureIsReported() {
        loginItems.failure = FakeLoginError()
        model.setLaunchAtLogin(true)

        XCTAssertNotNil(model.launchAtLoginError)
        XCTAssertFalse(model.launchAtLogin)
    }

    func testEnablingAModuleWithoutPermissionsNeverAsks() async {
        model.setModuleEnabled("media", false)
        model.setModuleEnabled("clock", true)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testPermissionsAreRequestedOnlyWhenTheModuleIsTurnedOn() async {
        XCTAssertTrue(permissions.requests.isEmpty)

        await model.enableModuleAfterPermissionExplanation("media")

        XCTAssertEqual(permissions.requests, [.automation])
        XCTAssertEqual(model.activeModules.map(\.id), ["clock", "media"])
        XCTAssertTrue(media.isEnabled)
    }

    func testAlreadyGrantedPermissionIsNotRequestedAgain() async {
        permissions.statuses[.automation] = .granted
        await model.enableModuleAfterPermissionExplanation("media")
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testADeniedPermissionStillEnablesTheModuleDegraded() async {
        permissions.requestResult = .denied
        await model.enableModuleAfterPermissionExplanation("media")

        XCTAssertEqual(permissions.requests, [.automation])
        XCTAssertTrue(model.activeModules.contains { $0.id == "media" })
    }

    func testReenablingDoesNotAskAgainAfterAGrant() async {
        await model.enableModuleAfterPermissionExplanation("media")
        model.setModuleEnabled("media", false)
        await model.enableModuleAfterPermissionExplanation("media")

        XCTAssertEqual(permissions.requests, [.automation])
    }

    func testReenablingAfterADenialAsksAgain() async {
        permissions.requestResult = .denied
        await model.enableModuleAfterPermissionExplanation("media")
        model.setModuleEnabled("media", false)
        await model.enableModuleAfterPermissionExplanation("media")

        XCTAssertEqual(permissions.requests, [.automation, .automation])
    }

    func testMovingAModuleChangesPanelOrderAndPersists() async {
        await model.enableModuleAfterPermissionExplanation("media")
        XCTAssertEqual(model.activeModules.map(\.id), ["clock", "media"])

        model.moveModule(id: "media", by: -1)

        XCTAssertEqual(model.activeModules.map(\.id), ["media", "clock"])
        XCTAssertEqual(store.stored.enabledModules, ["media", "clock"])
    }

    func testMovingBeyondTheEndsIsIgnored() {
        model.moveModule(id: "clock", by: -1)
        XCTAssertEqual(model.activeModules.map(\.id), ["clock"])
    }

    func testSettingsAreSavedOnChange() {
        model.settings.hoverDelay = 0.5
        XCTAssertEqual(store.stored.hoverDelay, 0.5)
    }

    func testPanelActivityIsForwardedOnceAcrossScreens() {
        model.setPanelActive(screenID: "built-in", active: true)
        XCTAssertEqual(clock.panelActiveHistory, [true])

        model.setPanelActive(screenID: "external", active: true)
        XCTAssertEqual(clock.panelActiveHistory, [true])

        model.setPanelActive(screenID: "built-in", active: false)
        XCTAssertEqual(clock.panelActiveHistory, [true])

        model.setPanelActive(screenID: "external", active: false)
        XCTAssertEqual(clock.panelActiveHistory, [true, false])
    }

    func testPreferredPlayerIsForwardedAndPersisted() {
        let mediaModule = FakeMediaControllingModule()
        let scoped = AppModel(
            store: store,
            loginItems: loginItems,
            registry: ModuleRegistry(modules: [mediaModule]),
            permissions: permissions
        )

        scoped.setPreferredPlayer("com.apple.Music")

        XCTAssertEqual(store.stored.preferredPlayerBundleID, "com.apple.Music")
        XCTAssertEqual(mediaModule.appliedPreferences.last, "com.apple.Music")
        XCTAssertEqual(scoped.mediaSources, [.music])

        scoped.setPreferredPlayer("")

        XCTAssertNil(store.stored.preferredPlayerBundleID)
        XCTAssertNil(mediaModule.appliedPreferences.last ?? nil)
    }

    func testRequestingAutomationUpdatesTheStatus() async {
        permissions.requestResult = .granted
        await model.requestAutomationPermission()

        XCTAssertEqual(model.automationStatus, .granted)
        XCTAssertEqual(permissions.requests, [.automation])
    }

    func testEnablingTheMediaModuleRefreshesAutomationStatus() async {
        permissions.requestResult = .denied
        await model.enableModuleAfterPermissionExplanation("media")

        XCTAssertEqual(model.automationStatus, .denied)
    }
}
