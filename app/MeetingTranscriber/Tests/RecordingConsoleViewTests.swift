@testable import MeetingTranscriber
import ViewInspector
import XCTest

@MainActor
final class RecordingConsoleViewTests: XCTestCase {
    func testRecordButtonCallsThePrimaryAction() throws {
        var recorded = false
        let view = RecordingConsoleView(
            recording: RecordingConsole.resolve(.idle),
            startedAt: nil,
            onPrimary: { recorded = true },
            onRecordApp: {},
            onToggleWatch: {},
        )
        let button = try view.inspect()
            .find(viewWithAccessibilityIdentifier: A11yID.homeRecordButton)
            .find(ViewType.Button.self)
        try button.tap()
        XCTAssertTrue(recorded)
    }

    func testRecordAppButtonCallsItsAction() throws {
        var opened = false
        let view = RecordingConsoleView(
            recording: RecordingConsole.resolve(.idle),
            startedAt: nil,
            onPrimary: {},
            onRecordApp: { opened = true },
            onToggleWatch: {},
        )
        try view.inspect().find(button: "Record App…").tap()
        XCTAssertTrue(opened)
    }
}

private extension RecordingConsole.Input {
    static let idle = RecordingConsole.Input(
        isWatching: false,
        isRecording: false,
        manualPendingOrActive: false,
        canStopManual: false,
        noMic: false,
        sessionTitle: nil,
    )
}
