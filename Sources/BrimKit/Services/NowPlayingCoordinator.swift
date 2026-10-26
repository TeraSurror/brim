import Foundation

/// Resolves the two data paths into one current track: the MediaRemote helper (everything, artwork) and
/// direct Apple Events for the player the user chose (Spotify or Music).
///
/// The helper runs while the media module needs it (the live notch or an open panel). The preferred-player
/// poll runs only then too: every second with the panel open, every three seconds while it is closed, and
/// slower still while the player is not running or Automation was not granted. A helper that exits is
/// restarted with a backoff, because with the live notch on nothing else would restart it.
@MainActor
public final class NowPlayingCoordinator: NowPlayingProviding {
    public private(set) var current: NowPlaying?
    public private(set) var sources: [NowPlayingSource]
    public private(set) var isAvailable: Bool

    public var onUpdate: ((NowPlaying?) -> Void)?
    public var onSourcesChange: (([NowPlayingSource]) -> Void)?

    private let adapter: MediaAdapterStreaming
    private let automation: PlayerAutomationControlling
    private let discovery: PlayerDiscovering
    private let scheduler: Scheduling

    private var preferredBundleID: String?
    private var isMonitoring = false
    private var adapterSnapshot: NowPlaying?
    private var automatedSnapshot: NowPlaying?
    private var adapterFailed = false
    private var pollTask: TaskHandle?
    private var restartTask: TaskHandle?
    private var restartAttempts = 0
    private var panelVisible = false

    /// Delays before restarting an exited helper; the last one repeats.
    public static let restartBackoff: [TimeInterval] = [5, 30, 300]

    public init(
        adapter: MediaAdapterStreaming,
        automation: PlayerAutomationControlling,
        discovery: PlayerDiscovering = InstalledPlayerDiscovery(),
        scheduler: Scheduling
    ) {
        self.adapter = adapter
        self.automation = automation
        self.discovery = discovery
        self.scheduler = scheduler
        self.sources = discovery.installedPlayers.map(\.source)
        self.isAvailable = adapter.isAvailable

        adapter.onUpdate = { [weak self] track in
            self?.adapterDidUpdate(track)
        }
        adapter.onFailure = { [weak self] message in
            self?.adapterDidFail(message)
        }
    }

    // MARK: - Monitoring

    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        adapterFailed = false
        restartAttempts = 0
        updateAvailability()
        refreshSources()
        adapter.start()
        refreshAutomation()
    }

    public func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        restartTask?.cancel()
        restartTask = nil
        adapter.stop()
        adapterSnapshot = nil
        automatedSnapshot = nil
        publish(nil)
    }

    public func setPanelVisible(_ visible: Bool) {
        guard visible != panelVisible else { return }
        panelVisible = visible
        // Pick up the faster cadence right away instead of after the current slow wait.
        if visible { refreshAutomation() }
    }

    public func follow(_ sourceID: String?) {
        preferredBundleID = sourceID
        automatedSnapshot = nil
        refreshAutomation()
    }

    // MARK: - Commands

    public func send(_ command: PlayerCommand) {
        if let player = routeToAutomation {
            automation.send(command, to: player)
        } else {
            adapter.send(command)
        }
    }

    public func seek(to position: TimeInterval) {
        if let player = routeToAutomation {
            automation.seek(to: position, in: player)
        } else {
            adapter.seek(to: position)
        }
    }

    // MARK: - Resolution

    private var preferredPlayer: ScriptablePlayer? {
        preferredBundleID.flatMap(ScriptablePlayer.init(rawValue:))
    }

    /// When the system-wide helper already reports the chosen player, prefer it: it has artwork and
    /// lower latency than polling Apple Events.
    private var routeToAutomation: ScriptablePlayer? {
        guard let player = preferredPlayer else { return nil }
        if adapterSnapshot?.source.id == player.rawValue { return nil }
        return automatedSnapshot != nil ? player : nil
    }

    private func adapterDidUpdate(_ track: NowPlaying?) {
        guard isMonitoring else { return }
        adapterSnapshot = track
        adapterFailed = false
        restartAttempts = 0
        updateAvailability()
        recompute()
    }

    private func adapterDidFail(_ message: String) {
        guard isMonitoring else { return }
        adapterFailed = true
        adapterSnapshot = nil
        updateAvailability()
        recompute()
        Log.media.error("Now Playing is falling back: \(message, privacy: .public)")
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard isMonitoring, adapter.isAvailable, restartTask == nil else { return }
        let backoff = Self.restartBackoff
        let delay = backoff[min(restartAttempts, backoff.count - 1)]
        restartAttempts += 1
        restartTask = scheduler.schedule(after: delay) { [weak self] in
            guard let self else { return }
            self.restartTask = nil
            guard self.isMonitoring else { return }
            Log.media.info("Restarting the MediaRemote helper")
            self.adapter.start()
        }
    }

    private func refreshAutomation() {
        guard isMonitoring, let player = preferredPlayer else {
            automatedSnapshot = nil
            recompute()
            schedulePoll()
            return
        }

        if discovery.isRunning(player), automation.isPermitted(for: player) {
            automatedSnapshot = automation.snapshot(of: player)
        } else {
            automatedSnapshot = nil
        }
        recompute()
        schedulePoll()
    }

    private func schedulePoll() {
        pollTask?.cancel()
        pollTask = nil
        guard isMonitoring, let player = preferredPlayer else { return }

        // Fast enough for the progress bar while the panel is open; the live notch only needs play state.
        let ready = discovery.isRunning(player) && automation.isPermitted(for: player)
        let interval: TimeInterval = ready ? (panelVisible ? 1 : 3) : (panelVisible ? 2 : 10)
        pollTask = scheduler.schedule(after: interval) { [weak self] in
            guard let self else { return }
            self.pollTask = nil
            self.refreshAutomation()
        }
    }

    private func recompute() {
        let next: NowPlaying?
        if let player = preferredPlayer {
            if let adapterSnapshot, adapterSnapshot.source.id == player.rawValue {
                next = adapterSnapshot
            } else {
                next = automatedSnapshot ?? adapterSnapshot
            }
        } else {
            next = adapterSnapshot
        }
        publish(next)
    }

    private func publish(_ track: NowPlaying?) {
        guard track != current else { return }
        current = track
        onUpdate?(track)
    }

    private func refreshSources() {
        let next = discovery.installedPlayers.map(\.source)
        guard next != sources else { return }
        sources = next
        onSourcesChange?(next)
    }

    private func updateAvailability() {
        // The media module's empty state is about the helper. Automation for a preferred player can still
        // provide a track while the helper is unhealthy, but that shows up as `current`, not availability.
        isAvailable = adapter.isAvailable && !adapterFailed
    }
}
