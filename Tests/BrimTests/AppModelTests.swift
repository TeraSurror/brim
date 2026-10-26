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

    private let controlOptionSpace = HotKey(keyCode: 49, modifiers: [.control, .option], keyLabel: "Space")

    private func makeModel(hotKeys: FakeHotKeys, shortcut: HotKey?) -> AppModel {
        var settings = Settings()
        settings.openPanelShortcut = shortcut
        return AppModel(
            store: FakeSettingsStore(settings),
            loginItems: loginItems,
            registry: ModuleRegistry(modules: [clock]),
            permissions: permissions,
            hotKeys: hotKeys
        )
    }

    func testTheSavedShortcutIsRegisteredAtLaunchAndPressesAreForwarded() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys, shortcut: controlOptionSpace)
        XCTAssertEqual(hotKeys.registered[.openPanel], controlOptionSpace)

        var pressed: [HotKeyAction] = []
        model.onShortcut = { pressed.append($0) }
        hotKeys.press(.openPanel)
        XCTAssertEqual(pressed, [.openPanel])
    }

    func testNoShortcutIsRegisteredByDefault() {
        let hotKeys = FakeHotKeys()
        _ = makeModel(hotKeys: hotKeys, shortcut: nil)
        XCTAssertTrue(hotKeys.registered.isEmpty)
    }

    func testChangingAndClearingTheShortcutReRegisters() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys, shortcut: controlOptionSpace)
        let commandB = HotKey(keyCode: 11, modifiers: [.command, .shift], keyLabel: "B")

        model.setOpenPanelShortcut(commandB)
        XCTAssertEqual(hotKeys.registered[.openPanel], commandB)
        XCTAssertEqual(model.settings.openPanelShortcut, commandB)

        model.setOpenPanelShortcut(nil)
        XCTAssertNil(hotKeys.registered[.openPanel])
        XCTAssertNil(model.settings.openPanelShortcut)
    }

    func testARefusedShortcutIsReportedAndClearsWhenFixed() {
        let hotKeys = FakeHotKeys()
        hotKeys.refused = [controlOptionSpace]
        let model = makeModel(hotKeys: hotKeys, shortcut: nil)

        model.setOpenPanelShortcut(controlOptionSpace)
        XCTAssertNotNil(model.shortcutError)
        XCTAssertTrue(model.shortcutError?.contains("⌃⌥Space") == true)

        model.setOpenPanelShortcut(HotKey(keyCode: 11, modifiers: [.command, .shift], keyLabel: "B"))
        XCTAssertNil(model.shortcutError)
    }

    func testRecordingPausesTheShortcut() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys, shortcut: controlOptionSpace)

        model.isRecordingShortcut = true
        XCTAssertNil(hotKeys.registered[.openPanel])

        model.isRecordingShortcut = false
        XCTAssertEqual(hotKeys.registered[.openPanel], controlOptionSpace)
    }

    func testAnInvalidShortcutIsNotSaved() {
        let hotKeys = FakeHotKeys()
        let model = makeModel(hotKeys: hotKeys, shortcut: nil)
        model.setOpenPanelShortcut(HotKey(keyCode: 0, modifiers: [.shift], keyLabel: "A"))
        XCTAssertNil(model.settings.openPanelShortcut)
        XCTAssertTrue(hotKeys.registered.isEmpty)
    }

    private func makeQuickPromptModel(
        enabled: [String],
        cliPath: String? = nil
    ) -> (AppModel, QuickPromptModule, FakePromptRunner) {
        let runner = FakePromptRunner()
        let prompt = QuickPromptModule(
            runner: runner,
            locator: FakeCLILocator(),
            scratchDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        var settings = Settings()
        settings.enabledModules = enabled
        settings.quickPromptCLIPath = cliPath
        let model = AppModel(
            store: FakeSettingsStore(settings),
            loginItems: loginItems,
            registry: ModuleRegistry(modules: [clock, prompt]),
            permissions: permissions
        )
        return (model, prompt, runner)
    }

    func testBarModulesAreSeparateFromCards() {
        let (model, _, _) = makeQuickPromptModel(enabled: ["prompt", "clock"])
        XCTAssertEqual(model.cardModules.map(\.id), ["clock"])
        XCTAssertEqual(model.barModules.map(\.id), ["prompt"])
    }

    func testAShowingConversationTakesOverThePanel() {
        let (model, prompt, _) = makeQuickPromptModel(enabled: ["clock", "prompt"])
        XCTAssertNil(model.fullPanelModuleID)

        prompt.draft = "Hi"
        prompt.send()
        XCTAssertEqual(model.fullPanelModuleID, "prompt")

        prompt.closeConversation()
        XCTAssertNil(model.fullPanelModuleID)
    }

    func testQuickPromptExplainsBeforeEnablingButAsksNoPermission() async {
        let (model, prompt, _) = makeQuickPromptModel(enabled: ["clock"])
        await model.enableModuleAfterPermissionExplanation("prompt")
        XCTAssertTrue(prompt.isEnabled)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testQuickPromptSettingsReachTheModuleAndRecentFoldersComeBack() {
        let (model, prompt, runner) = makeQuickPromptModel(enabled: ["prompt"], cliPath: "/custom/claude")
        XCTAssertEqual(model.quickPromptCLIPath, "/custom/claude")
        prompt.draft = "Hi"
        prompt.send()
        XCTAssertEqual(runner.executables.last?.path, "/custom/claude")

        model.setQuickPromptCLIPath(nil)
        XCTAssertEqual(model.quickPromptCLIPath, "/usr/local/bin/claude")

        let folder = FileManager.default.temporaryDirectory
        prompt.onRecentFoldersChange = { [weak model] in model?.setQuickPromptRecentFolders($0) }
        prompt.choose(.folder(folder))
        XCTAssertEqual(model.settings.quickPromptRecentFolders, [folder.path])
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

    // MARK: - Live notch

    func testTheHighestPriorityEnabledModuleOwnsTheLiveNotch() {
        model.settings.enabledModules = ["clock", "media"]
        XCTAssertNil(model.liveModuleID)

        clock.liveActivity = LiveActivity(priority: .ambient)
        XCTAssertEqual(model.liveModuleID, "clock")

        media.liveActivity = LiveActivity(priority: .media)
        XCTAssertEqual(model.liveModuleID, "media")
        XCTAssertEqual(model.liveModule?.id, "media")

        media.liveActivity = nil
        XCTAssertEqual(model.liveModuleID, "clock")
    }

    func testDisabledModulesNeverOwnTheLiveNotch() {
        media.liveActivity = LiveActivity(priority: .attention)
        XCTAssertNil(model.liveModuleID)

        model.settings.enabledModules = ["clock", "media"]
        XCTAssertEqual(model.liveModuleID, "media")
    }

    func testTurningTheLiveNotchOffClearsItAndTellsMedia() {
        let mediaModule = FakeMediaControllingModule()
        let scoped = AppModel(
            store: FakeSettingsStore(),
            loginItems: loginItems,
            registry: ModuleRegistry(modules: [clock, mediaModule]),
            permissions: permissions
        )
        scoped.settings.enabledModules = ["clock"]
        clock.liveActivity = LiveActivity(priority: .media)
        XCTAssertEqual(scoped.liveModuleID, "clock")
        XCTAssertEqual(mediaModule.liveEnabledHistory, [true])

        scoped.settings.showLiveActivity = false
        XCTAssertNil(scoped.liveModuleID)
        XCTAssertEqual(mediaModule.liveEnabledHistory, [true, false])
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

    // MARK: - First run and setup

    private func makeModel(store: FakeSettingsStore, hook: FakeClaudeHook? = nil) -> AppModel {
        AppModel(
            store: store,
            loginItems: loginItems,
            registry: ModuleRegistry(modules: [clock, media, agent]),
            permissions: permissions,
            claudeHook: hook
        )
    }

    func testTheFirstLaunchIsDetectedAndSavedOnce() {
        let fresh = FakeSettingsStore(hasSaved: false)
        let first = makeModel(store: fresh)
        XCTAssertTrue(first.isFirstLaunch)
        XCTAssertTrue(first.showsWelcome)
        XCTAssertTrue(fresh.hasSavedSettings)

        let second = makeModel(store: fresh)
        XCTAssertFalse(second.isFirstLaunch)
        XCTAssertFalse(second.showsWelcome)
        XCTAssertFalse(model.isFirstLaunch)
    }

    func testShowingATabOpensSettingsThere() {
        var opened = 0
        model.openSettings = { opened += 1 }
        model.showSettings(.agents)
        XCTAssertEqual(model.settingsTab, .agents)
        XCTAssertEqual(opened, 1)
    }

    func testChoosingAPlayerInThePanelWithoutAutomationOpensMediaSettings() {
        var opened = 0
        model.openSettings = { opened += 1 }

        model.choosePlayerFromPanel(nil)
        XCTAssertEqual(opened, 0)

        model.choosePlayerFromPanel(ScriptablePlayer.spotify.rawValue)
        XCTAssertEqual(store.stored.preferredPlayerBundleID, ScriptablePlayer.spotify.rawValue)
        XCTAssertEqual(model.settingsTab, .media)
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(permissions.requests.isEmpty)
    }

    func testChoosingAPlayerWithAutomationStaysInThePanel() {
        permissions.statuses[.automation] = .granted
        var opened = 0
        model.openSettings = { opened += 1 }
        model.choosePlayerFromPanel(ScriptablePlayer.music.rawValue)
        XCTAssertEqual(opened, 0)
    }

    func testClaudeHookInstallAndRemovalUpdateTheStatus() {
        let hook = FakeClaudeHook()
        let scoped = makeModel(store: FakeSettingsStore(), hook: hook)
        XCTAssertEqual(scoped.claudeHookStatus, .notInstalled)

        scoped.installClaudeHook()
        XCTAssertEqual(scoped.claudeHookStatus, .installed)
        XCTAssertNil(scoped.claudeHookError)

        scoped.removeClaudeHook()
        XCTAssertEqual(scoped.claudeHookStatus, .notInstalled)
        XCTAssertEqual(hook.installCount, 1)
        XCTAssertEqual(hook.uninstallCount, 1)
    }

    func testClaudeHookFailuresAreReported() {
        let hook = FakeClaudeHook()
        hook.failure = .unreadableSettings
        let scoped = makeModel(store: FakeSettingsStore(), hook: hook)

        scoped.installClaudeHook()
        XCTAssertEqual(scoped.claudeHookError, ClaudeHookError.unreadableSettings.errorDescription)
        XCTAssertEqual(scoped.claudeHookStatus, .notInstalled)
    }

    func testTestSessionGoesThroughTheAgentModule() {
        model.showTestAgentSession()
        XCTAssertEqual(agent.testSessionCount, 1)
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
