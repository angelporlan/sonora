import Foundation
import Observation

/// Holds the output-folder index for the main window and refreshes it while
/// that window is open.
///
/// The folder may be a security-scoped bookmark (a user-picked output
/// directory). The scope is taken for the whole time the window is open,
/// because listing and reading are not one call. A scope opened only around
/// the scan would already be closed by the time the page reads the file.
@MainActor
@Observable
final class TranscriptLibraryController {
    private(set) var documents: [TranscriptDocument] = []
    private(set) var folderMissing = false
    private(set) var hasLoaded = false

    private var scopedURL: URL?
    private var accessing = false
    private var poll: Task<Void, Never>?
    private var reloadGeneration = 0

    func start(directory: URL) {
        if scopedURL?.path != directory.path {
            releaseScope()
            scopedURL = directory
            accessing = directory.startAccessingSecurityScopedResource()
            hasLoaded = false
        }
        reload()
        ensurePolling()
    }

    func stop() {
        poll?.cancel()
        poll = nil
        reloadGeneration += 1
        releaseScope()
        scopedURL = nil
    }

    func reload() {
        guard let directory = scopedURL else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        Task { [weak self] in
            let scan = await Task.detached {
                TranscriptLibrary.scan(directory: directory)
            }.value
            self?.apply(scan, generation: generation)
        }
    }

    private func apply(_ scan: TranscriptLibrary.Scan, generation: Int) {
        guard generation == reloadGeneration else { return }
        if documents != scan.documents { documents = scan.documents }
        if folderMissing != scan.folderMissing { folderMissing = scan.folderMissing }
        hasLoaded = true
    }

    private func ensurePolling() {
        guard poll == nil else { return }
        poll = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                self?.reload()
            }
        }
    }

    private func releaseScope() {
        if accessing, let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        accessing = false
    }
}
