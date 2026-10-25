import Combine
import SwiftUI

/// Narrow surface `AppModel` needs from the media module: the installed players for the settings picker
/// and a way to apply the persisted preference without knowing the concrete module type in tests.
@MainActor
public protocol MediaModuleControlling: AnyObject {
    var sources: [NowPlayingSource] { get }
    func applyPreferredPlayer(_ sourceID: String?)
}

/// The M2 module. It owns no timers itself: the coordinator starts the helper only while a panel is open,
/// and SwiftUI's `TimelineView` interpolates the progress bar only while it is on screen.
@MainActor
public final class MediaModule: BrimModule, MediaModuleControlling, ObservableObject {
    public static let moduleID = "media"

    public let id = MediaModule.moduleID
    public let title = "Now Playing"
    public let symbolName = "play.circle.fill"
    public let requiredPermissions: [PermissionKind] = [.automation]
    public let permissionExplanation = """
        Brim can follow and control Spotify and Music directly, which also lets you choose between players \
        when more than one is playing. That uses macOS Automation. Without it, Brim still shows whatever \
        macOS reports as Now Playing, including Safari, and keeps working in a limited form.
        """

    @Published public private(set) var nowPlaying: NowPlaying?
    @Published public private(set) var sources: [NowPlayingSource] = []
    @Published public private(set) var preferredSourceID: String?

    public private(set) var isEnabled = false
    /// Set by `AppController` so the module can persist a choice made in the panel; settings stays the
    /// single source of truth.
    public var onPreferredPlayerChange: ((String?) -> Void)?

    private let service: NowPlayingProviding
    private let scheduler: Scheduling
    private var panelActive = false
    private var monitoring = false
    private var stopTask: TaskHandle?

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
        }
        service.onSourcesChange = { [weak self] sources in
            self?.sources = sources
        }
    }

    // MARK: - BrimModule

    public func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        if enabled {
            if panelActive { start() }
        } else {
            stopTask?.cancel()
            stopTask = nil
            stop()
        }
    }

    /// The shell reports when any panel is open. A one-second grace makes a twitchy hover out/in cheap.
    public func setPanelActive(_ active: Bool) {
        guard active != panelActive else { return }
        panelActive = active
        guard isEnabled else { return }

        if active {
            stopTask?.cancel()
            stopTask = nil
            start()
        } else {
            scheduleStop()
        }
    }

    public func compactView() -> AnyView {
        AnyView(MediaCompactView(module: self))
    }

    public func expandedView() -> AnyView {
        AnyView(MediaExpandedView(module: self))
    }

    // MARK: - Player preference and controls

    public func applyPreferredPlayer(_ sourceID: String?) {
        preferredSourceID = sourceID
        service.follow(sourceID)
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

    private func start() {
        guard isEnabled, panelActive, !monitoring else { return }
        monitoring = true
        service.startMonitoring()
    }

    private func stop() {
        guard monitoring else { return }
        monitoring = false
        service.stopMonitoring()
        nowPlaying = nil
        ArtworkImageCache.shared.clear()
    }

    private func scheduleStop() {
        stopTask?.cancel()
        stopTask = scheduler.schedule(after: 1.0) { [weak self] in
            guard let self, !self.panelActive else { return }
            self.stopTask = nil
            self.stop()
        }
    }
}
