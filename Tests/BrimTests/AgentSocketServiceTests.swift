import Darwin
import XCTest
@testable import BrimKit

@MainActor
final class AgentSocketServiceTests: XCTestCase {
    private var directory: URL!
    private var socketPath: String!
    private var service: AgentSocketService!

    override func setUp() async throws {
        // Unix socket paths are limited to ~104 bytes; the system temp directory is often longer than that.
        directory = URL(fileURLWithPath: "/tmp", isDirectory: true)
            .appendingPathComponent("brim-agent-\(UUID().uuidString.prefix(12))", isDirectory: true)
        socketPath = directory.appendingPathComponent("agent.sock").path
        service = AgentSocketService(socketPath: socketPath)
    }

    override func tearDown() async throws {
        service.stop()
        try? FileManager.default.removeItem(at: directory)
    }

    func testStartAndStopManageTheSocketFile() throws {
        service.start()

        XCTAssertTrue(service.isListening)
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
        let attributes = try FileManager.default.attributesOfItem(atPath: socketPath)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)

        service.stop()

        XCTAssertFalse(service.isListening)
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
    }

    func testReceivesAJsonLine() async throws {
        let expectation = expectation(description: "event")
        service.onEvent = { event in
            XCTAssertEqual(event.agentID, "claude-code")
            XCTAssertEqual(event.sessionID, "abc")
            XCTAssertEqual(event.status, .working)
            XCTAssertEqual(event.title, "Fix parser")
            expectation.fulfill()
        }
        service.start()

        await send(#"{"agent":"claude-code","session":"abc","status":"working","title":"Fix parser"}"# + "\n")

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testReceivesMultipleLinesFromOneWrite() async throws {
        let expectation = expectation(description: "events")
        expectation.expectedFulfillmentCount = 2
        service.onEvent = { _ in expectation.fulfill() }
        service.start()

        await send("""
        {"agent":"a","session":"one","status":"working"}
        {"agent":"a","session":"two","status":"done"}

        """)

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testProcessesAFinalLineWithoutANewlineOnEOF() async throws {
        let expectation = expectation(description: "event")
        service.onEvent = { event in
            XCTAssertEqual(event.sessionID, "abc")
            expectation.fulfill()
        }
        service.start()

        await send(#"{"agent":"a","session":"abc","status":"working"}"#)

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testMalformedInputDoesNotBlockTheNextEvent() async throws {
        let expectation = expectation(description: "valid event")
        var received: [String] = []
        service.onEvent = { event in
            received.append(event.sessionID)
            expectation.fulfill()
        }
        service.start()

        await send("not json\n" + #"{"agent":"a","session":"valid","status":"working"}"# + "\n")

        await fulfillment(of: [expectation], timeout: 2)
        XCTAssertEqual(received, ["valid"])
    }

    func testAnOversizedLineClosesOnlyThatConnection() async throws {
        let expectation = expectation(description: "next connection")
        service.onEvent = { event in
            XCTAssertEqual(event.sessionID, "valid")
            expectation.fulfill()
        }
        service.start()

        await send(String(repeating: "x", count: AgentEventDecoder.maxLineBytes + 100) + "\n")
        await send(#"{"agent":"a","session":"valid","status":"working"}"# + "\n")

        await fulfillment(of: [expectation], timeout: 2)
    }

    func testManySmallLinesInOneWriteAreNotTreatedAsOversized() async throws {
        let expectation = expectation(description: "small events")
        expectation.expectedFulfillmentCount = 60
        service.onEvent = { _ in expectation.fulfill() }
        service.start()

        let lines = (0..<60).map { index in
            #"{"agent":"a","session":"batch-\#(index)","status":"working","detail":"\#(String(repeating: "x", count: 120))"}"#
        }
        await send(lines.joined(separator: "\n") + "\n")

        await fulfillment(of: [expectation], timeout: 3)
    }

    func testRestartAfterStop() async throws {
        service.start()
        service.stop()

        let expectation = expectation(description: "event after restart")
        service.onEvent = { _ in expectation.fulfill() }
        service.start()

        await send(#"{"agent":"a","session":"again","status":"working"}"# + "\n")

        await fulfillment(of: [expectation], timeout: 2)
    }

    // MARK: - Helper

    /// Writes off the main actor: the listener accepts and drains on the main actor, so a large write
    /// must not block the test while it waits.
    private func send(_ text: String) async {
        let path = socketPath!
        await Task.detached(priority: .userInitiated) {
            SocketTestClient.send(text, to: path)
        }.value
    }
}

private enum SocketTestClient {
    static func send(_ text: String, to path: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: Array(path.utf8))
        }
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else { return }

        let data = Data(text.utf8)
        var offset = 0
        while offset < data.count {
            let written = data.withUnsafeBytes { buffer in
                write(fd, buffer.baseAddress!.advanced(by: offset), data.count - offset)
            }
            guard written > 0 else { return }
            offset += written
        }
    }
}
