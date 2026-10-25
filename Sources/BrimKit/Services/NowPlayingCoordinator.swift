import Foundation

/// Resolves the two data paths into one current track: the MediaRemote helper (everything, artwork) and
/// direct Apple Events for the player the user chose (Spotify or Music).
///
/// The helper is only started while a panel is visible. The preferred-player poll is also only active
/// then, and it stops entirely if the player is not running or Automation was not granted.
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
        adapter.stop()
        adapterSnapshot = nil
        automatedSnapshot = nil
        publish(nil)
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

        // One second while following a live player; a slower retry while waiting for it to launch.
        let ready = discovery.isRunning(player) && automation.isPermitted(for: player)
        pollTask = scheduler.schedule(after: ready ? 1 : 2) { [weak self] in
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
