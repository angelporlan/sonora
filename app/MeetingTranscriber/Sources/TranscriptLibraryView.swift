import AppKit
import SwiftUI

/// List and reader for the output folder. The controller is owned by the
/// window so switching to Settings and back keeps the selection and the
/// security scope.
struct TranscriptLibraryView: View {
    var library: TranscriptLibraryController
    let directory: URL
    @Binding var selectedID: String?
    let onRevealFolder: () -> Void

    @State private var query = ""

    var body: some View {
        Group {
            if !library.hasLoaded {
                ProgressView("Loading transcripts")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if library.folderMissing {
                unavailable(
                    title: "Output Folder Not Found",
                    systemImage: "folder.badge.questionmark",
                    description: "Transcripts are saved to the output folder. Showing it in Finder creates the folder.",
                )
            } else if library.documents.isEmpty {
                unavailable(
                    title: "No Transcripts Yet",
                    systemImage: "doc.text",
                    description: "Protocols and transcripts from finished meetings show up here.",
                )
            } else {
                browser
            }
        }
        .onChange(of: library.documents) { _, _ in
            keepSelection()
        }
    }

    private var browser: some View {
        NavigationSplitView {
            documentList
        } detail: {
            if let document = selectedDocument {
                TranscriptDocumentPage(document: document)
                    .id(document.id)
            } else {
                ContentUnavailableView(
                    "No Transcript Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a meeting from the list."),
                )
            }
        }
        .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 400)
        .onAppear(perform: keepSelection)
    }

    private var documentList: some View {
        List(selection: $selectedID) {
            if groups.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(groups) { group in
                    Section(group.title) {
                        ForEach(group.documents) { document in
                            documentRow(document)
                                .tag(document.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Transcripts")
        .searchable(text: $query, prompt: "Search transcripts")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            folderBar
        }
    }

    private func documentRow(_ document: TranscriptDocument) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(document.title)
                .font(.body)
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(TranscriptLibrary.listDate(document.meetingStart ?? document.modified, now: Date()))
                Text("·")
                Text(document.kindSummary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 2)
    }

    private var folderBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
            Text(folderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(directory.path)
            Spacer(minLength: 0)
            Button(action: onRevealFolder) {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")
            .accessibilityLabel("Show in Finder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func unavailable(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
            Text(folderPath)
                .font(.caption)
                .foregroundStyle(.secondary)
        } actions: {
            Button("Show in Finder", action: onRevealFolder)
        }
    }

    private var groups: [TranscriptLibrary.Group] {
        TranscriptLibrary.groups(visibleDocuments, now: Date())
    }

    private var visibleDocuments: [TranscriptDocument] {
        TranscriptLibrary.filter(library.documents, query: query)
    }

    private var selectedDocument: TranscriptDocument? {
        guard let selectedID else { return nil }
        return library.documents.first { $0.id == selectedID }
    }

    private var folderPath: String {
        OutputSettingsLogic.displayPath(
            for: directory,
            home: FileManager.default.homeDirectoryForCurrentUser,
        )
    }

    private func keepSelection() {
        let ids = library.documents.map(\.id)
        if let selectedID, ids.contains(selectedID) { return }
        selectedID = library.documents.first?.id
    }
}

private struct TranscriptDocumentPage: View {
    let document: TranscriptDocument

    @State private var kind: TranscriptDocumentKind
    @State private var text = ""
    @State private var loadedToken: String?
    @State private var failed = false

    init(document: TranscriptDocument) {
        self.document = document
        _kind = State(initialValue: document.preferredKind)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            reader
        }
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(document.title)
        .task(id: loadToken) { await load() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text(TranscriptLibrary.headerDate(document.meetingStart ?? document.modified))
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            kindControl
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var kindControl: some View {
        if document.hasProtocol, document.hasTranscript {
            Picker("Document", selection: $kind) {
                Text("Protocol").tag(TranscriptDocumentKind.meetingProtocol)
                Text("Transcript").tag(TranscriptDocumentKind.transcript)
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .labelsHidden()
        } else {
            Text(document.kindSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var reader: some View {
        if failed {
            ContentUnavailableView(
                "File Could Not Be Read",
                systemImage: "doc.badge.exclamationmark",
                description: Text("It may have been moved out of the output folder."),
            )
        } else if loadedToken != loadToken {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if displayedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ContentUnavailableView("This File Is Empty", systemImage: "doc")
        } else {
            ScrollView {
                pageBody
                    .frame(maxWidth: 720, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
            }
        }
    }

    @ViewBuilder private var pageBody: some View {
        if kind == .meetingProtocol, let attributed = TranscriptLibrary.attributedMarkdown(displayedText) {
            Text(attributed)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(displayedText)
                .font(.body)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var displayedText: String {
        switch kind {
        case .meetingProtocol: TranscriptLibrary.readerText(from: text)
        case .transcript: text
        }
    }

    private var loadToken: String {
        let modified = document.modified.timeIntervalSince1970
        return "\(document.id)|\(kind.rawValue)|\(modified)"
    }

    private func load() async {
        let token = loadToken
        failed = false
        guard let url = document.url(for: kind) else {
            failed = true
            return
        }
        let loaded = await Task.detached {
            try? String(contentsOf: url, encoding: .utf8)
        }.value
        guard !Task.isCancelled, token == loadToken else { return }
        if let loaded {
            text = loaded
            loadedToken = token
            failed = false
        } else {
            failed = true
        }
    }
}
