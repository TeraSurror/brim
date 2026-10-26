import Combine
import SwiftUI

/// Narrow surface `AppModel` needs from the media module: the installed players for the settings picker,
/// a way to apply the persisted preference, and the live notch switch, without knowing the concrete module
/// type in tests.
@MainActor
public protocol MediaModuleControlling: AnyObject {
    var sources: [NowPlayingSource] { get }
    func applyPreferredPlayer(_ sourceID: String?)
    /// While on, the helper keeps running with the panel closed so the notch can show what is playing.
    func setLiveActivityEnabled(_ enabled: Bool)
}

/// The Now Playing module. The helper runs while the live notch needs it or a panel is open; SwiftUI's
/// `TimelineView` interpolates the progress bar only while it is on screen.
@MainActor
public final class MediaModule: BrimModule, MediaModuleControlling, ObservableObject {
    public static let moduleID = "media"

    public let id = MediaModule.moduleID
    public let title = "Now Playing"
    public let symbolName = "play.circle.fill"
    /// Showing what macOS reports as Now Playing needs no permission. Automation is optional and asked for
    /// only when the user chooses to follow Spotify or Music (Settings → Media).
    public let requiredPermissions: [PermissionKind] = []
    public let permissionExplanation = ""

    @Published public private(set) var nowPlaying: NowPlaying?
    @Published public private(set) var sources: [NowPlayingSource] = []
    @Published public private(set) var preferredSourceID: String?
    @Published public private(set) var liveActivity: LiveActivity?

    public private(set) var isEnabled = false
    /// Set by `AppController` so the module can persist a choice made in the panel; settings stays the
    /// single source of truth.
    public var onPreferredPlayerChange: ((String?) -> Void)?

    /// How long the live notch stays after playback pauses or stops, so a track change does not flicker.
    public static let liveGracePeriod: TimeInterval = 3

    private let service: NowPlayingProviding
    private let scheduler: Scheduling
    private var panelActive = false
    private var liveEnabled = false
    private var monitoring = false
    private var stopTask: TaskHandle?
    private var hideLiveTask: TaskHandle?

    public init(
        service: NowPlayingProviding,
        scheduler: Scheduling = DispatchScheduler()
    ) {
        self.service = service
        self.scheduler = scheduler
        self.nowPlaying = service.current
        self.sources = service.sources

        service.onUpdate = { [weak self] track in
            self?.nowPlaying = track
            self?.updateLiveActivity(for: track)
        }
        service.onSourcesChange = { [weak self] sources in
            self?.sources = sources
        }
    }

    // MARK: - BrimModule

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        updateMonitoring(stopImmediately: true)
        updateLiveActivity(for: nowPlaying)
    }

    /// The shell reports when any panel is open. A one-second grace makes a twitchy hover out/in cheap.
    public func setPanelActive(_ active: Bool) {
        guard active != panelActive else { return }
        panelActive = active
        service.setPanelVisible(active)
        updateMonitoring(stopImmediately: false)
    }

    public var liveActivityPublisher: AnyPublisher<LiveActivity?, Never> {
        $liveActivity.eraseToAnyPublisher()
    }

    public func liveView(_ edge: LiveActivityEdge) -> AnyView {
        AnyView(MediaLiveView(module: self, edge: edge))
    }

    public func expandedView() -> AnyView {
        AnyView(MediaExpandedView(module: self))
    }

    // MARK: - Player preference and controls

    public func applyPreferredPlayer(_ sourceID: String?) {
        preferredSourceID = sourceID
        service.follow(sourceID)
    }

    public func setLiveActivityEnabled(_ enabled: Bool) {
        guard enabled != liveEnabled else { return }
        liveEnabled = enabled
        updateMonitoring(stopImmediately: false)
        updateLiveActivity(for: nowPlaying)
    }

    /// Called from the panel's source menu. Without a host closure (tests) the change stays local.
    public func choosePlayer(_ sourceID: String?) {
        if let onPreferredPlayerChange {
            onPreferredPlayerChange(sourceID)
        } else {
            applyPreferredPlayer(sourceID)
        }
    }

    public func send(_ command: PlayerCommand) {
        service.send(command)
    }

    public func seek(to position: TimeInterval) {
        service.seek(to: position)
    }

    // MARK: - Monitoring

    private var shouldMonitor: Bool {
        isEnabled && (panelActive || liveEnabled)
    }

    private func updateMonitoring(stopImmediately: Bool) {
        if shouldMonitor {
            stopTask?.cancel()
            stopTask = nil
            start()
        } else if stopImmediately {
            stopTask?.cancel()
            stopTask = nil
            stop()
        } else if monitoring {
            scheduleStop()
        }
    }

    private func start() {
        guard shouldMonitor, !monitoring else { return }
        monitoring = true
        service.startMonitoring()
    }

    private func stop() {
        guard monitoring else { return }
        monitoring = false
        service.stopMonitoring()
        nowPlaying = nil
        updateLiveActivity(for: nil)
        ArtworkImageCache.shared.clear()
    }

    private func scheduleStop() {
        stopTask?.cancel()
        stopTask = scheduler.schedule(after: 1.0) { [weak self] in
            guard let self, !self.shouldMonitor else { return }
            self.stopTask = nil
            self.stop()
        }
    }

    // MARK: - Live notch

    private func updateLiveActivity(for track: NowPlaying?) {
        guard isEnabled, liveEnabled else {
            hideLiveTask?.cancel()
            hideLiveTask = nil
            if liveActivity != nil { liveActivity = nil }
            return
        }
        if track?.isPlaying == true {
            hideLiveTask?.cancel()
            hideLiveTask = nil
            if liveActivity == nil { liveActivity = LiveActivity(priority: .media) }
        } else if liveActivity != nil, hideLiveTask == nil {
            hideLiveTask = scheduler.schedule(after: Self.liveGracePeriod) { [weak self] in
                guard let self else { return }
                self.hideLiveTask = nil
                if self.nowPlaying?.isPlaying != true { self.liveActivity = nil }
            }
        }
    }
}
