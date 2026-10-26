import XCTest
@testable import BrimKit

@MainActor
final class AgentModuleTests: XCTestCase {
    private var listener: FakeAgentListener!
    private var notifier: FakeAgentNotifier!
    private var workspace: FakeWorkspace!
    private var alerts: FakeAgentAlertPresenter!
    private var module: AgentModule!
    private let base = Date(timeIntervalSince1970: 1_000)
    private var now = Date(timeIntervalSince1970: 1_000)

    override func setUp() async throws {
        now = base
        listener = FakeAgentListener()
        notifier = FakeAgentNotifier()
        workspace = FakeWorkspace()
        alerts = FakeAgentAlertPresenter()
        module = AgentModule(
            listener: listener,
            notifier: notifier,
            workspace: workspace,
            alertPresenter: alerts,
            retentionMinutes: 10,
            now: { [unowned self] in self.now }
        )
    }

    private func event(
        session: String = "s1",
        status: AgentStatus = .working,
        title: String? = "Fix parser",
        detail: String? = "Running tests",
        cwd: String? = "/tmp/project",
        app: String? = nil,
        at offset: TimeInterval = 0
    ) throws -> AgentEvent {
        try XCTUnwrap(AgentEvent(
            agentID: "claude-code",
            sessionID: session,
            status: status,
            title: title,
            detail: detail,
            cwd: cwd,
            app: app,
            timestamp: base.addingTimeInterval(offset)
        ))
    }

    func testEnablingStartsTheSocketAndDisablingStopsIt() {
        module.setEnabled(true)
        XCTAssertTrue(module.isEnabled)
        XCTAssertTrue(module.isListening)
        XCTAssertEqual(listener.startCount, 1)

        module.setEnabled(false)
        XCTAssertFalse(module.isEnabled)
        XCTAssertFalse(module.isListening)
        XCTAssertEqual(listener.stopCount, 1)
    }

    func testEventsFromTheListenerReachTheModule() throws {
        module.setEnabled(true)
        listener.emit(try event())

        XCTAssertEqual(module.sessions.count, 1)
        XCTAssertEqual(module.sessions.first?.status, .working)
        XCTAssertEqual(module.sessionCount, 1)
    }

    func testEventsAreIgnoredWhileTheModuleIsDisabled() throws {
        listener.emit(try event())
        XCTAssertTrue(module.sessions.isEmpty)
    }

    func testDisablingClearsSessions() throws {
        module.setEnabled(true)
        listener.emit(try event())
        module.setEnabled(false)

        XCTAssertTrue(module.sessions.isEmpty)
    }

    func testOpeningThePanelPrunesExpiredFinishedSessions() throws {
        module.setEnabled(true)
        module.ingest(try event(status: .done, at: 0))
        now = base.addingTimeInterval(11 * 60)

        module.setPanelActive(true)

        XCTAssertTrue(module.sessions.isEmpty)
    }

    func testWorkingSessionsSurvivePruning() throws {
        module.setEnabled(true)
        module.ingest(try event(status: .working, at: 0))
        now = base.addingTimeInterval(24 * 60 * 60)

        module.setPanelActive(true)

        XCTAssertEqual(module.sessions.count, 1)
    }

    func testChangingRetentionPrunesImmediately() throws {
        module.setEnabled(true)
        module.ingest(try event(status: .done, at: 0))
        now = base.addingTimeInterval(2 * 60)

        module.applyRetention(minutes: 1)

        XCTAssertEqual(module.retentionMinutes, 1)
        XCTAssertTrue(module.sessions.isEmpty)
    }

    func testRetentionIsClampedToTheSettingsRange() {
        module.applyRetention(minutes: 0)
        XCTAssertEqual(module.retentionMinutes, Settings.agentRetentionRange.lowerBound)

        module.applyRetention(minutes: 500)
        XCTAssertEqual(module.retentionMinutes, Settings.agentRetentionRange.upperBound)
    }

    func testDismissAndClearCommands() throws {
        module.setEnabled(true)
        module.ingest(try event(session: "one"))
        module.ingest(try event(session: "two"))

        module.handle(.dismiss(agentID: "claude-code", sessionID: "one"))
        XCTAssertEqual(module.sessions.map(\.sessionID), ["two"])

        module.handle(.clear)
        XCTAssertTrue(module.sessions.isEmpty)
    }

    func testClearFinishedKeepsWaitingSessions() throws {
        module.setEnabled(true)
        module.ingest(try event(session: "waiting", status: .waiting))
        module.ingest(try event(session: "done", status: .done))

        module.clearFinished()

        XCTAssertEqual(module.sessions.map(\.sessionID), ["waiting"])
        XCTAssertEqual(module.finishedCount, 0)
    }

    func testSummaryIsExposedForThePeekAndDiagnostics() throws {
        module.setEnabled(true)
        module.ingest(try event(session: "waiting", status: .waiting))
        module.ingest(try event(session: "working", status: .working))

        XCTAssertEqual(module.summary.headline, .waiting)
        XCTAssertEqual(module.summary.waiting, 1)
        XCTAssertEqual(module.summary.working, 1)
        XCTAssertEqual(module.sessionCount, 2)
    }

    // MARK: - Live notch

    func testWaitingAndFailuresAskForAttentionAndWorkingIsAmbient() throws {
        module.setEnabled(true)
        XCTAssertNil(module.liveActivity)

        listener.emit(try event(session: "a", status: .working))
        XCTAssertEqual(module.liveActivity, LiveActivity(priority: .ambient))
        XCTAssertEqual(module.liveStatus, .working)

        listener.emit(try event(session: "b", status: .waiting, at: 1))
        XCTAssertEqual(module.liveActivity, LiveActivity(priority: .attention))
        XCTAssertEqual(module.liveStatus, .waiting)
        XCTAssertEqual(module.liveCount, 1)

        listener.emit(try event(session: "b", status: .done, at: 2))
        listener.emit(try event(session: "a", status: .done, at: 3))
        XCTAssertNil(module.liveActivity)
    }

    func testOpeningThePanelAcknowledgesFailures() throws {
        module.setEnabled(true)
        listener.emit(try event(session: "a", status: .error))
        XCTAssertEqual(module.liveStatus, .error)

        module.setPanelActive(true)
        module.setPanelActive(false)
        XCTAssertNil(module.liveActivity)
        XCTAssertEqual(module.sessions.count, 1)

        // Failing again after recovering lights the notch again.
        listener.emit(try event(session: "a", status: .working, at: 1))
        listener.emit(try event(session: "a", status: .error, at: 2))
        XCTAssertEqual(module.liveStatus, .error)
    }

    func testWaitingIsNotAcknowledgedByOpeningThePanel() throws {
        module.setEnabled(true)
        listener.emit(try event(session: "a", status: .waiting))
        module.setPanelActive(true)
        module.setPanelActive(false)
        XCTAssertEqual(module.liveStatus, .waiting)
    }

    func testLiveCountsSessionsSharingTheStatus() throws {
        module.setEnabled(true)
        listener.emit(try event(session: "a", status: .waiting))
        listener.emit(try event(session: "b", status: .waiting))
        listener.emit(try event(session: "c", status: .working))
        XCTAssertEqual(module.liveCount, 2)
    }

    func testDisablingClearsTheLiveNotch() throws {
        module.setEnabled(true)
        listener.emit(try event(status: .waiting))
        module.setEnabled(false)
        XCTAssertNil(module.liveActivity)
    }

    func testTheTestSessionWaitsForInput() {
        module.setEnabled(true)
        module.showTestSession()
        XCTAssertEqual(module.sessions.first?.status, .waiting)
        XCTAssertEqual(module.sessions.first?.agentName, "Brim")
        XCTAssertEqual(module.liveStatus, .waiting)
    }

    func testSocketPathIsForwardedForSettings() {
        XCTAssertEqual(module.socketPath, listener.socketPath)
    }

    func testNotificationsAreOffByDefault() throws {
        module.setEnabled(true)
        module.ingest(try event(status: .waiting))

        XCTAssertFalse(module.notificationsEnabled)
        XCTAssertTrue(notifier.posted.isEmpty)
        XCTAssertTrue(alerts.presented.isEmpty)
    }

    func testWaitingNotifiesOnceAndAgainAfterWorkResumes() throws {
        module.setNotificationsEnabled(true)
        module.setEnabled(true)

        module.ingest(try event(status: .working))
        module.ingest(try event(status: .waiting, at: 1))
        XCTAssertEqual(notifier.posted.count, 1)
        XCTAssertTrue(notifier.posted[0].title.contains("needs your input"))
        XCTAssertEqual(notifier.posted[0].target.cwd, "/tmp/project")

        module.ingest(try event(status: .waiting, at: 2))
        XCTAssertEqual(notifier.posted.count, 1)

        module.ingest(try event(status: .working, at: 3))
        module.ingest(try event(status: .waiting, at: 4))
        XCTAssertEqual(notifier.posted.count, 2)
        XCTAssertTrue(alerts.presented.isEmpty)
    }

    func testFailureNotifiesWhenEnabled() throws {
        module.setNotificationsEnabled(true)
        module.setEnabled(true)

        module.ingest(try event(status: .error))

        XCTAssertEqual(notifier.posted.count, 1)
        XCTAssertTrue(notifier.posted[0].title.contains("failed"))
    }

    func testAnOpenPanelSuppressesNotifications() throws {
        module.setNotificationsEnabled(true)
        module.setEnabled(true)
        module.setPanelActive(true)

        module.ingest(try event(status: .waiting))

        XCTAssertTrue(notifier.posted.isEmpty)
        XCTAssertTrue(alerts.presented.isEmpty)
    }

    func testDeniedSystemAuthorizationFallsBackToTheNotchAlert() throws {
        notifier.authorization = .denied
        module.setNotificationsEnabled(true)
        module.setEnabled(true)

        module.ingest(try event(status: .waiting))

        XCTAssertTrue(notifier.posted.isEmpty)
        XCTAssertEqual(alerts.presented.count, 1)
        XCTAssertEqual(alerts.presented[0].status, .waiting)
        XCTAssertEqual(alerts.presented[0].target.cwd, "/tmp/project")
    }

    func testTheNotchAlertOpensTheProject() throws {
        notifier.authorization = .denied
        module.setNotificationsEnabled(true)
        module.setEnabled(true)
        module.ingest(try event(status: .waiting))

        alerts.openLatest()

        XCTAssertEqual(workspace.openedPaths, ["/tmp/project"])
    }

    func testDisablingAlertsDismissesTheNotchAlert() {
        module.setNotificationsEnabled(true)
        module.setNotificationsEnabled(false)

        XCTAssertEqual(alerts.dismissCount, 1)
    }

    func testRequestingNotificationAuthorizationUpdatesTheModule() async {
        notifier.requestResult = .authorized

        let status = await module.requestNotificationAuthorization()

        XCTAssertEqual(status, .authorized)
        XCTAssertEqual(module.notificationAuthorization, .authorized)
        XCTAssertEqual(notifier.requestCount, 1)
    }

    func testOpeningAProjectUsesTheWorkspace() throws {
        module.setEnabled(true)
        module.ingest(try event(cwd: "/tmp/project"))
        let session = try XCTUnwrap(module.sessions.first)

        module.open(session)

        XCTAssertEqual(workspace.openedPaths, ["/tmp/project"])
    }

    func testOpeningASessionPrefersItsApp() throws {
        workspace.installedApps = ["com.apple.Terminal"]
        module.setEnabled(true)
        module.ingest(try event(cwd: "/tmp/project", app: "com.apple.Terminal"))

        module.open(try XCTUnwrap(module.sessions.first))

        XCTAssertEqual(workspace.activatedApps, ["com.apple.Terminal"])
        XCTAssertTrue(workspace.openedPaths.isEmpty)
    }

    func testAnUninstalledAppFallsBackToTheFolder() throws {
        module.setEnabled(true)
        module.ingest(try event(cwd: "/tmp/project", app: "com.example.gone"))

        module.open(try XCTUnwrap(module.sessions.first))

        XCTAssertTrue(workspace.activatedApps.isEmpty)
        XCTAssertEqual(workspace.openedPaths, ["/tmp/project"])
    }

    func testTheNotchAlertOpensTheApp() throws {
        workspace.installedApps = ["com.googlecode.iterm2"]
        notifier.authorization = .denied
        module.setNotificationsEnabled(true)
        module.setEnabled(true)
        module.ingest(try event(status: .waiting, app: "com.googlecode.iterm2"))

        alerts.openLatest()

        XCTAssertEqual(workspace.activatedApps, ["com.googlecode.iterm2"])
    }

    func testOpeningThePanelDismissesTheNotchAlert() throws {
        module.setEnabled(true)
        let before = alerts.dismissCount
        module.setPanelActive(true)
        XCTAssertEqual(alerts.dismissCount, before + 1)
    }

    func testNotificationClickOpensTheTarget() {
        workspace.installedApps = ["com.microsoft.VSCode"]
        notifier.onOpen?(AgentOpenTarget(app: "com.microsoft.VSCode", cwd: "/tmp/clicked-project"))
        notifier.onOpen?(AgentOpenTarget(app: nil, cwd: "/tmp/other"))

        XCTAssertEqual(workspace.activatedApps, ["com.microsoft.VSCode"])
        XCTAssertEqual(workspace.openedPaths, ["/tmp/other"])
    }

    func testAFailedSocketReportsNotListening() {
        let failing = FailingAgentListener()
        let scoped = AgentModule(
            listener: failing,
            notifier: FakeAgentNotifier(),
            workspace: FakeWorkspace()
        )
        scoped.setEnabled(true)

        XCTAssertFalse(scoped.isListening)
    }
}

@MainActor
private final class FailingAgentListener: AgentEventListening {
    let socketPath = "/tmp/brim-unavailable.sock"
    var isListening = false
    var onEvent: ((AgentEvent) -> Void)?

    func start() {}
    func stop() {}
}
