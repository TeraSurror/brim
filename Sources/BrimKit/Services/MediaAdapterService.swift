import Foundation

/// The MediaRemote helper as seen by the coordinator. Abstracted so the coordinator can be tested without
/// spawning Perl processes.
@MainActor
public protocol MediaAdapterStreaming: AnyObject {
    /// `nil` means the helper is running but nothing is playing.
    var onUpdate: ((NowPlaying?) -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    var isAvailable: Bool { get }
    var isRunning: Bool { get }
    func start()
    func stop()
    func send(_ command: PlayerCommand)
    func seek(to position: TimeInterval)
}

/// Where the bundled helper lives. `mediaremote-adapter.pl` is run by `/usr/bin/perl`, which macOS trusts
/// to use MediaRemote; the framework is loaded by the script, never linked into Brim.
public struct MediaAdapterLocation: Sendable {
    public let scriptURL: URL
    public let frameworkURL: URL

    public init(scriptURL: URL, frameworkURL: URL) {
        self.scriptURL = scriptURL
        self.frameworkURL = frameworkURL
    }

    /// `BRIM_MEDIA_ADAPTER_PATH` makes `swift run` usable without packaging an app bundle.
    public static func bundled(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> MediaAdapterLocation? {
        var candidates: [URL] = []
        if let override = environment["BRIM_MEDIA_ADAPTER_PATH"], !override.isEmpty {
            candidates.append(URL(fileURLWithPath: override, isDirectory: true))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("MediaAdapter", isDirectory: true))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("MediaAdapter", isDirectory: true))

        for directory in candidates {
            let script = directory.appendingPathComponent("mediaremote-adapter.pl")
            let framework = directory.appendingPathComponent("MediaRemoteAdapter.framework")
            let executable = framework.appendingPathComponent("MediaRemoteAdapter")
            if fileManager.fileExists(atPath: script.path),
               fileManager.fileExists(atPath: executable.path) {
                return MediaAdapterLocation(scriptURL: script, frameworkURL: framework)
            }
        }
        return nil
    }
}

/// Runs the helper once for a command and a long-lived process for the stream. All process output is
/// decoded off the main actor; only finished snapshots cross back.
@MainActor
public final class MediaAdapterService: MediaAdapterStreaming {
    public var onUpdate: ((NowPlaying?) -> Void)?
    public var onFailure: ((String) -> Void)?

    private let location: MediaAdapterLocation?
    private var stream: Process?
    private var streamPipe: Pipe?
    private var stderrTask: Task<Void, Never>?
    private var readerTask: Task<Void, Never>?
    private var generation = 0
    private var runningCommands: [Process] = []

    public init(location: MediaAdapterLocation? = MediaAdapterLocation.bundled()) {
        self.location = location
        if location == nil {
            Log.media.info("MediaRemote helper is not bundled; media will be unavailable")
        }
    }

    public var isAvailable: Bool { location != nil }
    public var isRunning: Bool { stream?.isRunning == true }

    public func start() {
        guard stream == nil, let location else { return }
        generation += 1
        let generation = self.generation

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [
            location.scriptURL.path,
            location.frameworkURL.path,
            "stream",
            "--debounce=150",
        ]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            Log.media.error("Could not start the MediaRemote helper: \(error.localizedDescription)")
            onFailure?("The MediaRemote helper could not start.")
            return
        }

        stream = process
        streamPipe = stdout
        Log.media.info("MediaRemote helper started (pid \(process.processIdentifier, privacy: .public))")

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                self?.streamExited(status: status, generation: generation)
            }
        }

        stderrTask = Self.drain(stderr.fileHandleForReading)

        let handle = stdout.fileHandleForReading
        readerTask = Task.detached(priority: .utility) { [weak self] in
            var decoder = MediaAdapterDecoder()
            do {
                for try await line in handle.bytes.lines {
                    let event = decoder.consume(line: line)
                    switch event {
                    case .ignored:
                        continue
                    case .noMedia:
                        await self?.deliver(nil, generation: generation)
                    case .update(let track):
                        await self?.deliver(track, generation: generation)
                    }
                }
            } catch {
                // Closing the pipe during stop is expected; a read error while running is logged below.
                await self?.readerFailed(generation: generation)
            }
        }
    }

    public func stop() {
        generation += 1
        readerTask?.cancel()
        readerTask = nil
        stderrTask?.cancel()
        stderrTask = nil

        if let stream {
            stream.terminationHandler = nil
            if stream.isRunning { stream.terminate() }
            Log.media.info("MediaRemote helper stopped")
        }
        stream = nil
        try? streamPipe?.fileHandleForReading.close()
        streamPipe = nil
    }

    public func send(_ command: PlayerCommand) {
        let identifier: String
        switch command {
        case .play: identifier = "0"
        case .pause: identifier = "1"
        case .togglePlayPause: identifier = "2"
        case .next: identifier = "4"
        case .previous: identifier = "5"
        }
        run(["send", identifier], label: "send \(identifier)")
    }

    public func seek(to position: TimeInterval) {
        let micros = Int((max(0, position) * 1_000_000).rounded())
        run(["seek", String(micros)], label: "seek")
    }

    // MARK: - Process plumbing

    private func run(_ arguments: [String], label: String) {
        guard let location else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = [location.scriptURL.path, location.frameworkURL.path] + arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        runningCommands.append(process)
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                self?.runningCommands.removeAll { $0 === finished }
                if status != 0 {
                    Log.media.error("MediaRemote \(label, privacy: .public) failed with exit \(status, privacy: .public)")
                }
            }
        }

        do {
            try process.run()
        } catch {
            runningCommands.removeAll { $0 === process }
            Log.media.error("Could not run MediaRemote \(label, privacy: .public): \(error.localizedDescription)")
        }
    }

    private func deliver(_ track: NowPlaying?, generation: Int) {
        guard generation == self.generation, stream != nil else { return }
        onUpdate?(track)
    }

    private func streamExited(status: Int32, generation: Int) {
        guard generation == self.generation else { return }
        stream = nil
        streamPipe = nil
        readerTask?.cancel()
        readerTask = nil
        stderrTask?.cancel()
        stderrTask = nil
        Log.media.error("MediaRemote helper exited with status \(status, privacy: .public)")
        onFailure?("The MediaRemote helper stopped (exit \(status)).")
    }

    private func readerFailed(generation: Int) {
        guard generation == self.generation, stream != nil else { return }
        Log.media.error("MediaRemote helper output closed unexpectedly")
        onFailure?("The MediaRemote helper output stopped.")
    }

    private nonisolated static func drain(_ handle: FileHandle) -> Task<Void, Never> {
        Task.detached(priority: .utility) {
            do {
                for try await line in handle.bytes.lines where !line.isEmpty {
                    Log.media.debug("adapter: \(line, privacy: .public)")
                }
            } catch {
                // The pipe closes when the helper exits; nothing useful to report here.
            }
        }
    }
}
