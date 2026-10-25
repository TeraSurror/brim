import XCTest
@testable import BrimKit

@MainActor
final class MediaAdapterServiceTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A stand-in for the Perl adapter: prints one stream envelope and then waits to be terminated.
    private func makeStubAdapter() throws -> MediaAdapterLocation {
        let script = directory.appendingPathComponent("mediaremote-adapter.pl")
        let framework = directory.appendingPathComponent("MediaRemoteAdapter.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)

        let source = """
            #!/usr/bin/perl
            use strict;
            use warnings;
            $| = 1;
            my $now = time;
            print '{"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Safari",' .
                  '"playing":true,"title":"Stub track","artist":"Stub artist","duration":120,' .
                  '"elapsedTime":3,"timestamp":' . $now . '}}' . "\\n";
            $SIG{TERM} = sub { exit 0 };
            sleep 60;
            """
        try source.write(to: script, atomically: true, encoding: .utf8)
        return MediaAdapterLocation(scriptURL: script, frameworkURL: framework)
    }

    func testStreamOutputBecomesANowPlayingUpdate() async throws {
        let service = MediaAdapterService(location: try makeStubAdapter())
        let update = expectation(description: "track")
        var received: NowPlaying?
        service.onUpdate = { track in
            received = track
            update.fulfill()
        }
        service.onFailure = { message in
            XCTFail("Unexpected failure: \(message)")
        }

        service.start()
        await fulfillment(of: [update], timeout: 5)
        service.stop()

        XCTAssertEqual(received?.title, "Stub track")
        XCTAssertEqual(received?.artist, "Stub artist")
        XCTAssertEqual(received?.source, .safari)
        XCTAssertEqual(received?.duration, 120)
        XCTAssertFalse(service.isRunning)
    }

    func testStartIsIdempotentAndStopIsSafe() throws {
        let service = MediaAdapterService(location: try makeStubAdapter())
        service.start()
        service.start()
        XCTAssertTrue(service.isRunning)

        service.stop()
        service.stop()
        XCTAssertFalse(service.isRunning)
    }

    func testMissingResourcesReportUnavailable() {
        let service = MediaAdapterService(location: nil)
        XCTAssertFalse(service.isAvailable)
        service.start()
        XCTAssertFalse(service.isRunning)
    }
}
