@testable import MeetingTranscriber
import XCTest

final class RecordingConsoleTests: XCTestCase {
    func testIdleOffersTheMicrophoneAndTheOtherWaysToCapture() {
        let console = RecordingConsole.resolve(input())
        XCTAssertEqual(console.primary, .recordMicrophone)
        XCTAssertTrue(console.primaryEnabled)
        XCTAssertEqual(console.primaryLabel, "Record")
        XCTAssertEqual(console.status, "Ready")
        XCTAssertFalse(console.isStop)
        XCTAssertFalse(console.showsTimer)
        XCTAssertTrue(console.recordAppEnabled)
        XCTAssertFalse(console.watchOn)
        XCTAssertTrue(console.watchEnabled)
    }

    func testNoMicrophoneDisablesRecordAndSaysWhy() {
        var source = input()
        source.noMic = true
        let console = RecordingConsole.resolve(source)
        XCTAssertNil(console.primary)
        XCTAssertFalse(console.primaryEnabled)
        XCTAssertEqual(
            console.detail,
            MicrophoneRecordingAvailability.blockedByNoMicSetting.disabledReason,
        )
        XCTAssertTrue(console.recordAppEnabled)
    }

    func testManualRecordingBecomesStopAndHoldsTheOtherStarts() {
        var source = input()
        source.isRecording = true
        source.manualPendingOrActive = true
        source.canStopManual = true
        source.sessionTitle = "Microphone Recording"
        let console = RecordingConsole.resolve(source)
        XCTAssertEqual(console.primary, .stopManual)
        XCTAssertTrue(console.isStop)
        XCTAssertEqual(console.status, "Recording")
        XCTAssertEqual(console.detail, "Microphone Recording")
        XCTAssertTrue(console.showsTimer)
        XCTAssertFalse(console.recordAppEnabled)
        XCTAssertFalse(console.watchEnabled)
    }

    func testManualStartInFlightDoesNotOfferStopOrAnotherStart() {
        var source = input()
        source.manualPendingOrActive = true
        let console = RecordingConsole.resolve(source)
        XCTAssertNil(console.primary)
        XCTAssertEqual(console.status, "Starting…")
        XCTAssertFalse(console.primaryEnabled)
        XCTAssertFalse(console.recordAppEnabled)
        XCTAssertFalse(console.watchEnabled)
        XCTAssertFalse(console.showsTimer)
    }

    func testWatchingLeavesRecordAvailable() {
        var source = input()
        source.isWatching = true
        let console = RecordingConsole.resolve(source)
        XCTAssertEqual(console.primary, .recordMicrophone)
        XCTAssertEqual(console.status, "Watching for meetings")
        XCTAssertTrue(console.watchOn)
        XCTAssertTrue(console.watchEnabled)
        XCTAssertTrue(console.recordAppEnabled)
    }

    func testDetectedMeetingRecordingStopsWatching() {
        var source = input()
        source.isWatching = true
        source.isRecording = true
        source.sessionTitle = "Weekly sync"
        let console = RecordingConsole.resolve(source)
        XCTAssertEqual(console.primary, .stopWatching)
        XCTAssertEqual(console.detail, "Weekly sync")
        XCTAssertTrue(console.showsTimer)
        XCTAssertTrue(console.watchOn)
        XCTAssertFalse(console.watchEnabled)
        XCTAssertFalse(console.recordAppEnabled)
    }

    func testElapsedText() {
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(RecordingConsole.elapsedText(since: start, now: start), "0:00")
        XCTAssertEqual(
            RecordingConsole.elapsedText(since: start, now: start.addingTimeInterval(65)),
            "1:05",
        )
        XCTAssertEqual(
            RecordingConsole.elapsedText(since: start, now: start.addingTimeInterval(3661)),
            "1:01:01",
        )
    }

    private func input() -> RecordingConsole.Input {
        RecordingConsole.Input(
            isWatching: false,
            isRecording: false,
            manualPendingOrActive: false,
            canStopManual: false,
            noMic: false,
            sessionTitle: nil,
        )
    }
}
