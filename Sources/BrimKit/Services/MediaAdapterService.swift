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
    private var stderrPipe: Pipe?
    private var reader: AdapterLineReader?
    private var generation = 0
    private var runningCommands: [Process] = []

    /// Runs the helper under a shell that watches Brim's PID. A normal quit terminates the supervisor;
    /// if Brim crashes or is killed, the supervisor notices within a second and takes the helper with it,
    /// so a stale 25 MB Perl process can never outlive the app.
    private static let supervisorScript = """
        parent="$1"
        shift
        "$@" &
        child=$!
        trap 'kill "$child" 2>/dev/null; wait "$child" 2>/dev/null; exit 0' TERM INT HUP
        while kill -0 "$child" 2>/dev/null; do
            if ! kill -0 "$parent" 2>/dev/null; then
                kill "$child" 2>/dev/null
                exit 0
            fi
            sleep 1
        done
        wait "$child"
        exit $?
        """

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
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            Self.supervisorScript,
            "brim-media-supervisor",
            String(ProcessInfo.processInfo.processIdentifier),
            "/usr/bin/perl",
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
        stderrPipe = stderr
        Log.media.info("MediaRemote helper started (supervisor pid \(process.processIdentifier, privacy: .public))")

        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            Task { @MainActor in
                self?.streamExited(status: status, generation: generation)
            }
        }

        let reader = AdapterLineReader { [weak self] event in
            Task { @MainActor in
                self?.handle(event, generation: generation)
            }
        }
        reader.start(stdout.fileHandleForReading)
        self.reader = reader

        // Drain stderr so the helper can never block on a full pipe; the messages are diagnostics only.
        stderrPipe?.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            if let line = String(data: data, encoding: .utf8) {
                Log.media.debug("adapter: \(line, privacy: .public)")
            }
        }
    }

    public func stop() {
        generation += 1
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        reader?.stop()
        reader = nil

        if let stream {
            stream.terminationHandler = nil
            if stream.isRunning { stream.terminate() }
            Log.media.info("MediaRemote helper stopped")
        }
        stream = nil
        // Do not close the read ends while a handler may still be reading; terminating the helper closes
        // the write ends and the handlers finish with EOF.
        streamPipe = nil
        stderrPipe = nil
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

    private func handle(_ event: MediaAdapterEvent, generation: Int) {
        guard generation == self.generation, stream != nil else { return }
        switch event {
        case .ignored:
            return
        case .noMedia:
            onUpdate?(nil)
        case .update(let track):
            onUpdate?(track)
        }
    }

    private func streamExited(status: Int32, generation: Int) {
        guard generation == self.generation else { return }
        streamPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        reader?.stop()
        reader = nil
        stream = nil
        streamPipe = nil
        stderrPipe = nil
        Log.media.error("MediaRemote helper exited with status \(status, privacy: .public)")
        onFailure?("The MediaRemote helper stopped (exit \(status)).")
    }
}

/// Splits the helper's stdout into newline-delimited JSON on a private queue, keeping the decoder state off
/// the main actor. FileHandle readability handlers are used instead of an async byte sequence so stopping
/// the helper never has to close a descriptor that a reader is blocked on.
private final class AdapterLineReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.harshshelar.brim.media-adapter-reader")
    private let onEvent: (MediaAdapterEvent) -> Void
    private var buffer = Data()
    private var decoder = MediaAdapterDecoder()
    private var handle: FileHandle?

    init(onEvent: @escaping (MediaAdapterEvent) -> Void) {
        self.onEvent = onEvent
    }

    func start(_ handle: FileHandle) {
        self.handle = handle
        handle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.queue.async {
                self.consume(data)
            }
        }
    }

    func stop() {
        handle?.readabilityHandler = nil
        handle = nil
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
            onEvent(decoder.consume(line: line))
        }
    }
}
