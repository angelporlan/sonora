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

/// Native window: a source list with the meeting library and the existing
/// settings. The settings window opened from the menu bar stays separate so
/// the automation harness still addresses it by its own window id.
struct HomeWindowView<Settings: View>: View {
    @Bindable var settings: AppSettings
    let onRevealOutputFolder: () -> Void
    @ViewBuilder let settingsContent: () -> Settings

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
            Section {
                Label("Settings", systemImage: "gearshape")
                    .tag(HomeSection.settings)
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
        case .settings:
            settingsContent()
        }
    }
}

private enum HomeSection: Hashable {
    case transcripts
    case settings
}
