import Foundation

extension AppState {
    /// What the main window's record control should show right now.
    var recordingConsole: RecordingConsole {
        RecordingConsole.resolve(RecordingConsole.Input(
            isWatching: isWatching,
            isRecording: watching.isRecording,
            manualPendingOrActive: watching.isManualRecording,
            canStopManual: isManualRecording,
            noMic: settings.noMic,
            sessionTitle: currentStatus?.meeting?.title,
        ))
    }

    /// When the capture in progress actually started, so the window's timer
    /// counts the recording and not the moment the window was opened.
    var recordingStartedAt: Date? {
        watching.watchLoop?.captureStartedAt
    }
}
