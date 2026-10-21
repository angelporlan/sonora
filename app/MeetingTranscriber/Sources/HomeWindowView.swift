import AppKit
import SwiftUI

/// The menu-bar app is an `LSUIElement`, so it has no Dock icon. While this
/// window is open the process behaves as a regular app (Dock, Cmd-Tab). Closing
/// it returns to the menu bar. Other windows stay as they are today.
@MainActor
enum MainWindowActivation {
    static func show() {
        NSApp.setActivationPolicy(.regular)
    }

    static func hide() {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Native window: one source list for the library and the settings tabs.
/// The menu-bar Settings window stays a separate scene so the automation
/// harness still addresses it by its own window id.
struct HomeWindowView<Pane: View>: View {
    @Bindable var settings: AppSettings
    let recording: RecordingConsole
    let recordingStartedAt: Date?
    let onRecord: () -> Void
    let onStopManualRecording: () -> Void
    let onRecordApp: () -> Void
    let onToggleWatch: () -> Void
    let onRevealOutputFolder: () -> Void
    @ViewBuilder let settingsPane: (SettingsTab) -> Pane

    @State private var section: HomeSection = .transcripts
    @State private var library = TranscriptLibraryController()
    @State private var selectedDocumentID: String?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .frame(minWidth: 960, minHeight: 580)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RecordingConsoleView(
                recording: recording,
                startedAt: recordingStartedAt,
                onPrimary: performRecordingPrimary,
                onRecordApp: onRecordApp,
                onToggleWatch: onToggleWatch,
            )
        }
        .onAppear {
            MainWindowActivation.show()
            library.start(directory: settings.effectiveOutputDir)
        }
        .onDisappear {
            library.stop()
            MainWindowActivation.hide()
        }
        .onChange(of: settings.effectiveOutputDir.path) { _, _ in
            library.start(directory: settings.effectiveOutputDir)
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section("Library") {
                Label("Transcripts", systemImage: "doc.text")
                    .tag(HomeSection.transcripts)
            }
            Section("Settings") {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.systemImage)
                        .tag(HomeSection.settings(tab))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Meeting Transcriber")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .toolbar {
            if section == .transcripts {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onRevealOutputFolder) {
                        Label("Show in Finder", systemImage: "folder")
                    }
                    .help("Open the output folder in Finder")
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch section {
        case .transcripts:
            TranscriptLibraryView(
                library: library,
                directory: settings.effectiveOutputDir,
                selectedID: $selectedDocumentID,
                onRevealFolder: onRevealOutputFolder,
            )
        case .settings(let tab):
            settingsPane(tab)
                .navigationTitle(tab.label)
        }
    }
}

private enum HomeSection: Hashable {
    case transcripts
    case settings(SettingsTab)
}

extension HomeWindowView {
    fileprivate func performRecordingPrimary() {
        switch recording.primary {
        case .recordMicrophone: onRecord()
        case .stopManual: onStopManualRecording()
        case .stopWatching: onToggleWatch()
        case nil: break
        }
    }
}
