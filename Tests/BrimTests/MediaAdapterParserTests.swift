import XCTest
@testable import BrimKit

final class MediaAdapterParserTests: XCTestCase {
    private var decoder = MediaAdapterDecoder()

    private let receivedAt = Date(timeIntervalSince1970: 1_700_000_010)

    private func line(_ payload: String, diff: Bool = false) -> String {
        #"{"type":"data","diff":\#(diff),"payload":\#(payload)}"#
    }

    private let fullPayload = #"{"bundleIdentifier":"com.spotify.client","playing":true,"title":"Track","artist":"Artist","album":"Album","duration":210.5,"elapsedTime":42,"timestamp":1700000000,"artworkMimeType":"image/jpeg","artworkData":"aGVsbG8="}"#

    func testFullPayloadBecomesATrack() {
        let event = decoder.consume(line: line(fullPayload), receivedAt: receivedAt)

        guard case .update(let track) = event else {
            return XCTFail("Expected a track, got \(event)")
        }
        XCTAssertEqual(track.title, "Track")
        XCTAssertEqual(track.artist, "Artist")
        XCTAssertEqual(track.album, "Album")
        XCTAssertEqual(track.duration, 210.5)
        XCTAssertEqual(track.elapsed, 42)
        XCTAssertEqual(track.capturedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(track.isPlaying)
        XCTAssertEqual(track.source, .spotify)
        XCTAssertEqual(track.artwork?.data, Data("hello".utf8))
        XCTAssertEqual(track.artwork?.mimeType, "image/jpeg")
    }

    func testDiffKeepsUnchangedFields() {
        _ = decoder.consume(line: line(fullPayload), receivedAt: receivedAt)
        let event = decoder.consume(
            line: line(#"{"elapsedTime":50,"timestamp":1700000010}"#, diff: true),
            receivedAt: receivedAt
        )

        guard case .update(let track) = event else {
            return XCTFail("Expected a track, got \(event)")
        }
        XCTAssertEqual(track.title, "Track")
        XCTAssertEqual(track.elapsed, 50)
        XCTAssertEqual(track.position(at: receivedAt), 50, accuracy: 0.001)
    }

    func testDiffNullRemovesAField() {
        _ = decoder.consume(line: line(fullPayload), receivedAt: receivedAt)
        let event = decoder.consume(
            line: line(#"{"album":null}"#, diff: true),
            receivedAt: receivedAt
        )

        guard case .update(let track) = event else {
            return XCTFail("Expected a track, got \(event)")
        }
        XCTAssertEqual(track.album, "")
        XCTAssertEqual(track.title, "Track")
    }

    func testEmptyPayloadMeansNothingIsPlaying() {
        XCTAssertEqual(decoder.consume(line: line("{}")), .noMedia)
    }

    func testDiffCanClearTheTrack() {
        _ = decoder.consume(line: line(fullPayload), receivedAt: receivedAt)
        XCTAssertEqual(decoder.consume(line: line("{}", diff: false), receivedAt: receivedAt), .noMedia)
    }

    func testMalformedAndNonDataLinesAreIgnored() {
        XCTAssertEqual(decoder.consume(line: "not json", receivedAt: receivedAt), .ignored)
        XCTAssertEqual(decoder.consume(line: #"{"type":"other","payload":{}}"#), .ignored)
    }

    func testPlayerWithoutBundleIdentifierIsIgnored() {
        let event = decoder.consume(
            line: line(#"{"title":"Test Client","playing":true}"#),
            receivedAt: receivedAt
        )
        XCTAssertEqual(event, .noMedia)
    }

    func testTitlelessMediaIsIgnored() {
        let event = decoder.consume(
            line: line(#"{"bundleIdentifier":"com.apple.Safari","playing":true,"title":"  "}"#),
            receivedAt: receivedAt
        )
        XCTAssertEqual(event, .noMedia)
    }

    func testUnknownPlayerGetsAReadableName() {
        let event = decoder.consume(
            line: line(#"{"bundleIdentifier":"com.example.my-player","playing":false,"title":"Track"}"#),
            receivedAt: receivedAt
        )

        guard case .update(let track) = event else {
            return XCTFail("Expected a track, got \(event)")
        }
        XCTAssertEqual(track.source.name, "my player")
        XCTAssertFalse(track.isPlaying)
    }

    func testArtworkIsReplacedWhenADiffSendsNewData() {
        _ = decoder.consume(line: line(fullPayload), receivedAt: receivedAt)
        let event = decoder.consume(
            line: line(#"{"artworkData":"d29ybGQ=","artworkMimeType":"image/png"}"#, diff: true),
            receivedAt: receivedAt
        )

        guard case .update(let track) = event else {
            return XCTFail("Expected a track, got \(event)")
        }
        XCTAssertEqual(track.artwork?.data, Data("world".utf8))
        XCTAssertEqual(track.artwork?.mimeType, "image/png")
    }

    func testTimestampFallsBackToReceiveTimeWhenMissing() {
        let event = decoder.consume(
            line: line(#"{"bundleIdentifier":"com.apple.Music","playing":true,"title":"Track","elapsedTime":5}"#),
            receivedAt: receivedAt
        )

        guard case .update(let track) = event else {
            return XCTFail("Expected a track, got \(event)")
        }
        XCTAssertEqual(track.capturedAt, receivedAt)
        XCTAssertEqual(track.position(at: receivedAt), 5, accuracy: 0.001)
    }
}
