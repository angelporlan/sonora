import Foundation

/// What the main window's record control shows, and which press it will make.
///
/// The window has three ways to capture — the microphone, one app, and watching
/// for a meeting — and they do not all mean "start" at the same time. A press
/// during a recording stops that recording; a second start is refused. This
/// value is that decision, so the button cannot disagree with the controls
/// underneath it.
struct RecordingConsole: Equatable {
    enum Primary: Equatable {
        case recordMicrophone
        case stopManual
        case stopWatching
    }

    struct Input: Equatable {
        var isWatching: Bool
        /// The watch loop is in `.recording`, manual or detected.
        var isRecording: Bool
        /// A manual recording owns the loop, or a start is still on its way there.
        var manualPendingOrActive: Bool
        /// A manual loop exists and can be stopped. False during the start that
        /// has not built the loop yet, where Stop would find nothing to stop.
        var canStopManual: Bool
        var noMic: Bool
        var sessionTitle: String?
    }

    var primary: Primary?
    var primaryEnabled: Bool
    /// VoiceOver name, and the word the button stands for.
    var primaryLabel: String
    var status: String
    /// Second line: the session name, or why Record cannot start.
    var detail: String?
    var showsTimer: Bool
    var recordAppEnabled: Bool
    var watchOn: Bool
    var watchEnabled: Bool

    var isStop: Bool {
        switch primary {
        case .stopManual, .stopWatching: true
        default: false
        }
    }

    static func resolve(_ input: Input) -> RecordingConsole {
        if input.canStopManual { return manualRecording(input) }
        if input.manualPendingOrActive { return starting }
        if input.isWatching, input.isRecording { return meetingRecording(input) }
        if input.isWatching { return watching(input) }
        return idle(input)
    }

    /// `0:00`, then `1:05`, then `1:01:01`. Hours appear only once an hour has passed.
    static func elapsedText(since start: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remain = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remain)
        }
        return String(format: "%d:%02d", minutes, remain)
    }

    // MARK: - Phases

    private static func manualRecording(_ input: Input) -> RecordingConsole {
        RecordingConsole(
            primary: .stopManual,
            primaryEnabled: true,
            primaryLabel: "Stop Recording",
            status: "Recording",
            detail: input.sessionTitle ?? "Microphone",
            showsTimer: input.isRecording,
            recordAppEnabled: false,
            watchOn: false,
            watchEnabled: false,
        )
    }

    private static var starting: RecordingConsole {
        RecordingConsole(
            primary: nil,
            primaryEnabled: false,
            primaryLabel: "Record",
            status: "Starting…",
            detail: nil,
            showsTimer: false,
            recordAppEnabled: false,
            watchOn: false,
            watchEnabled: false,
        )
    }

    private static func meetingRecording(_ input: Input) -> RecordingConsole {
        RecordingConsole(
            primary: .stopWatching,
            primaryEnabled: true,
            primaryLabel: "Stop Recording",
            status: "Recording",
            detail: input.sessionTitle ?? "Meeting",
            showsTimer: true,
            recordAppEnabled: false,
            watchOn: true,
            watchEnabled: false,
        )
    }

    private static func watching(_ input: Input) -> RecordingConsole {
        let microphone = microphoneAvailability(input)
        return RecordingConsole(
            primary: microphone.allowsStart ? .recordMicrophone : nil,
            primaryEnabled: microphone.allowsStart,
            primaryLabel: "Record",
            status: "Watching for meetings",
            detail: microphone.disabledReason,
            showsTimer: false,
            recordAppEnabled: true,
            watchOn: true,
            watchEnabled: true,
        )
    }

    private static func idle(_ input: Input) -> RecordingConsole {
        let microphone = microphoneAvailability(input)
        return RecordingConsole(
            primary: microphone.allowsStart ? .recordMicrophone : nil,
            primaryEnabled: microphone.allowsStart,
            primaryLabel: "Record",
            status: "Ready",
            detail: microphone.disabledReason ?? "Record the microphone, or pick an app.",
            showsTimer: false,
            recordAppEnabled: true,
            watchOn: false,
            watchEnabled: true,
        )
    }

    private static func microphoneAvailability(_ input: Input) -> MicrophoneRecordingAvailability {
        .resolve(
            isRecording: input.manualPendingOrActive || input.isRecording,
            noMic: input.noMic,
        )
    }
}
