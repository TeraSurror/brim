import Darwin
import Foundation

public enum AgentSocketLocation {
    /// Stable enough for a hook to hard-code, and inside Brim's own Application Support directory so the
    /// socket file inherits a private directory.
    public static var defaultPath: String {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Brim", isDirectory: true)
            .appendingPathComponent("agent.sock")
            .path
    }
}

/// A tiny line-delimited Unix-socket server. It uses POSIX sockets rather than Network.framework because
/// Brim only needs a local listener, and this keeps the accepted connection path explicit and testable.
@MainActor
public final class AgentSocketService: AgentEventListening {
    public let socketPath: String
    public private(set) var isListening = false
    public var onEvent: ((AgentEvent) -> Void)?

    private struct Client {
        let id: UUID
        let source: DispatchSourceRead
        var buffer = Data()

        init(id: UUID, source: DispatchSourceRead) {
            self.id = id
            self.source = source
        }
    }

    private let queue = DispatchQueue(label: "com.harshshelar.brim.agent-socket", qos: .utility)
    private let maxClients = 16
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var clients: [Int32: Client] = [:]

    public init(socketPath: String = AgentSocketLocation.defaultPath) {
        self.socketPath = socketPath
    }

    public func start() {
        guard !isListening else { return }

        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            Log.agent.error("Cannot create agent socket directory: \(error.localizedDescription)")
            return
        }
        directory.path.withCString { _ = chmod($0, 0o700) }

        // A stale socket from a crash would make bind fail; unlinking is safe because Brim is single-instance.
        socketPath.withCString { _ = unlink($0) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            logErrno("socket")
            return
        }
        // The read source can fire while several clients are queued; a non-blocking accept lets the
        // loop drain them without ever parking the main actor.
        let flags = fcntl(fd, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        }

        let pathBytes = Array(socketPath.utf8)
        let capacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)
        guard pathBytes.count < capacity else {
            Log.agent.error("Agent socket path is too long")
            close(fd)
            return
        }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        guard bound == 0 else {
            logErrno("bind")
            close(fd)
            return
        }

        socketPath.withCString { _ = chmod($0, 0o600) }
        guard listen(fd, 8) == 0 else {
            logErrno("listen")
            close(fd)
            socketPath.withCString { _ = unlink($0) }
            return
        }

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.acceptConnections() }
        }
        source.resume()
        acceptSource = source
        isListening = true
        Log.agent.info("Agent socket listening at \(self.socketPath, privacy: .public)")
    }

    public func stop() {
        guard isListening || listenFD >= 0 else { return }

        acceptSource?.cancel()
        acceptSource = nil
        for (fd, client) in clients {
            client.source.cancel()
            close(fd)
        }
        clients.removeAll()

        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }
        isListening = false
        socketPath.withCString { _ = unlink($0) }
        Log.agent.info("Agent socket stopped")
    }

    // MARK: - Accept and read

    private func acceptConnections() {
        guard listenFD >= 0 else { return }

        while true {
            var address = sockaddr_un()
            var length = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFD = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.accept(listenFD, sockaddrPointer, &length)
                }
            }
            guard clientFD >= 0 else { return }

            guard clients.count < maxClients, belongsToCurrentUser(clientFD) else {
                close(clientFD)
                continue
            }
            let clientFlags = fcntl(clientFD, F_GETFL, 0)
            if clientFlags >= 0 {
                _ = fcntl(clientFD, F_SETFL, clientFlags | O_NONBLOCK)
            }

            let source = DispatchSource.makeReadSource(fileDescriptor: clientFD, queue: queue)
            let clientID = UUID()
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.readClient(clientFD, id: clientID) }
            }
            clients[clientFD] = Client(id: clientID, source: source)
            source.resume()
        }
    }

    private func readClient(_ fd: Int32, id: UUID) {
        guard let current = clients[fd], current.id == id else { return }
        var client = current

        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = bytes.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }

        if count > 0 {
            client.buffer.append(contentsOf: bytes.prefix(count))
            guard processLines(in: &client) else {
                Log.agent.error("Agent event line is too long; closing the connection")
                removeClient(fd)
                return
            }
            clients[fd] = client
        } else if count == 0 {
            // A hook may write one object and close without a trailing newline.
            if !client.buffer.isEmpty {
                handleLine(client.buffer)
            }
            removeClient(fd)
        } else if errno != EAGAIN && errno != EWOULDBLOCK {
            removeClient(fd)
        }
    }

    /// Returns false when a line exceeds the cap. The cap is per line, not per read: a burst of many
    /// small events must not be mistaken for one oversized event.
    private func processLines(in client: inout Client) -> Bool {
        while let newline = client.buffer.firstIndex(of: 0x0A) {
            let line = Data(client.buffer[client.buffer.startIndex..<newline])
            client.buffer.removeSubrange(client.buffer.startIndex...newline)
            guard line.count <= AgentEventDecoder.maxLineBytes else { return false }
            handleLine(line)
        }
        return client.buffer.count <= AgentEventDecoder.maxLineBytes
    }

    private func handleLine(_ data: Data) {
        var line = data
        if line.last == 0x0D { line.removeLast() }
        guard !line.isEmpty else { return }
        guard let event = AgentEventDecoder.decode(line: line) else {
            Log.agent.error("Rejected a malformed agent event")
            return
        }
        onEvent?(event)
    }

    private func removeClient(_ fd: Int32) {
        guard let client = clients.removeValue(forKey: fd) else { return }
        client.source.cancel()
        close(fd)
    }

    private func belongsToCurrentUser(_ fd: Int32) -> Bool {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        return uid == getuid()
    }

    private func logErrno(_ operation: String) {
        Log.agent.error("Agent socket \(operation, privacy: .public) failed: \(String(cString: strerror(errno)), privacy: .public)")
    }
}
