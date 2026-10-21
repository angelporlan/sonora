import SwiftUI

/// The record control for the main window. A red record button, the session
/// name, and a running time — the same arrangement Voice Memos uses — with
/// the two other ways to capture beside it.
struct RecordingConsoleView: View {
    let recording: RecordingConsole
    let startedAt: Date?
    let onPrimary: () -> Void
    let onRecordApp: () -> Void
    let onToggleWatch: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            recordButton
            statusColumn
            Spacer(minLength: 12)
            secondaryActions
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var recordButton: some View {
        Button(action: onPrimary) {
            Image(systemName: recording.isStop ? "stop.circle.fill" : "record.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(recording.primaryEnabled ? Color.red : Color.red.opacity(0.35))
        }
        .buttonStyle(.plain)
        .disabled(!recording.primaryEnabled)
        .accessibilityIdentifier(A11yID.homeRecordButton)
        .accessibilityLabel(recording.primaryLabel)
        .help(recording.detail ?? recording.primaryLabel)
    }

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if recording.showsTimer {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                Text(recording.status)
                    .font(.headline)
            }
            if recording.showsTimer {
                timer
            } else if let detail = recording.detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    @ViewBuilder private var timer: some View {
        if let startedAt {
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                Text(RecordingConsole.elapsedText(since: startedAt, now: context.date))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundStyle(.red)
            }
        } else {
            Text("0:00")
                .font(.system(.title2, design: .rounded).monospacedDigit())
                .foregroundStyle(.red)
        }
    }

    private var secondaryActions: some View {
        HStack(spacing: 16) {
            Button("Record App…", action: onRecordApp)
                .buttonStyle(.bordered)
                .disabled(!recording.recordAppEnabled)
                .accessibilityIdentifier(A11yID.homeRecordAppButton)
            Toggle("Watch for meetings", isOn: watchBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!recording.watchEnabled)
                .accessibilityIdentifier(A11yID.homeWatchToggle)
        }
    }

    private var watchBinding: Binding<Bool> {
        Binding(
            get: { recording.watchOn },
            set: { _ in onToggleWatch() },
        )
    }
}
