import Foundation

/// One meeting's saved protocol (`.md`) and transcript (`.txt`), paired by the
/// stem the pipeline writes (`{yyyyMMdd_HHmm}_{slug}_{shortID}`).
struct TranscriptDocument: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// Meeting start parsed from the filename stamp. Nil when the name has none;
    /// the list then falls back to `modified`.
    let meetingStart: Date?
    let modified: Date
    let protocolURL: URL?
    let transcriptURL: URL?

    var hasProtocol: Bool { protocolURL != nil }
    var hasTranscript: Bool { transcriptURL != nil }

    var preferredKind: TranscriptDocumentKind {
        hasProtocol ? .meetingProtocol : .transcript
    }

    var kindSummary: String {
        if hasProtocol, hasTranscript { return "Protocol and transcript" }
        if hasProtocol { return "Protocol" }
        return "Transcript"
    }

    func url(for kind: TranscriptDocumentKind) -> URL? {
        switch kind {
        case .meetingProtocol: protocolURL
        case .transcript: transcriptURL
        }
    }
}

enum TranscriptDocumentKind: String, Hashable, Sendable {
    case meetingProtocol
    case transcript
}

/// Indexes the output folder. Only the top level is read: `recordings/` holds
/// audio, and a finished import leaves no protocol there. Subfolders are not
/// transcripts.
enum TranscriptLibrary {
    struct Scan: Equatable, Sendable {
        var documents: [TranscriptDocument]
        var folderMissing: Bool
    }

    struct Group: Identifiable, Equatable {
        let title: String
        let documents: [TranscriptDocument]
        var id: String { title }
    }

    struct DisplayTitle: Equatable {
        let title: String
        let meetingStart: Date?
    }

    static func scan(directory: URL, fileManager: FileManager = .default) -> Scan {
        var isDirectoryFlag: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectoryFlag),
              isDirectoryFlag.boolValue else {
            return Scan(documents: [], folderMissing: true)
        }
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles],
        ) else {
            return Scan(documents: [], folderMissing: false)
        }
        let files = urls.filter { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory != true
        }
        return Scan(documents: documents(from: files), folderMissing: false)
    }

    static func displayTitle(stem: String, markdownTitle: String?) -> DisplayTitle {
        let parsed = parsedStem(stem)
        if let markdownTitle {
            let trimmed = markdownTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return DisplayTitle(title: trimmed, meetingStart: parsed.meetingStart)
            }
        }
        let human = humanize(parsed.slug)
        let title = human.isEmpty ? stem : human
        return DisplayTitle(title: title, meetingStart: parsed.meetingStart)
    }

    /// First ATX H1 in the opening of a protocol. Section headings (`##`) are
    /// not the document title.
    static func markdownTitle(in text: String) -> String? {
        var seen = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            seen += 1
            if seen > 40 { return nil }
            guard trimmed.hasPrefix("# ") else { continue }
            let title = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return String(title) }
        }
        return nil
    }

    /// Drops a leading H1 so the page header is not repeated as the first line
    /// of the body. Leaves the rest of the document, including a following
    /// blank line, alone apart from that one blank line.
    static func readerText(from markdown: String) -> String {
        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let index = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else { return normalized }
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("# ") else { return normalized }
        lines.remove(at: index)
        if index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    static func attributedMarkdown(_ text: String) -> AttributedString? {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return try? AttributedString(markdown: text, options: options)
    }

    static func groups(
        _ documents: [TranscriptDocument],
        now: Date,
        calendar: Calendar = .current,
    ) -> [Group] {
        var order: [String] = []
        var buckets: [String: [TranscriptDocument]] = [:]
        for document in documents {
            let when = document.meetingStart ?? document.modified
            let label = bucketLabel(for: when, now: now, calendar: calendar)
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(document)
        }
        return order.map { Group(title: $0, documents: buckets[$0] ?? []) }
    }

    static func bucketLabel(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = englishFormatter("MMMM yyyy", calendar: calendar)
        return formatter.string(from: date)
    }

    /// Compact stamp for a list row. The section header already says which day
    /// "Today" and "Yesterday" are, so those rows only need the time.
    static func listDate(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        let recent = bucketLabel(for: date, now: now, calendar: calendar)
        let format = switch (recent, sameYear) {
        case ("Today", _), ("Yesterday", _): "HH:mm"
        case (_, true): "d MMM, HH:mm"
        default: "d MMM yyyy"
        }
        return englishFormatter(format, calendar: calendar).string(from: date)
    }

    static func headerDate(_ date: Date, calendar: Calendar = .current) -> String {
        englishFormatter("EEEE, d MMMM yyyy 'at' HH:mm", calendar: calendar).string(from: date)
    }

    static func filter(_ documents: [TranscriptDocument], query: String) -> [TranscriptDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return documents }
        return documents.filter { $0.title.localizedStandardContains(trimmed) }
    }

    // MARK: - Private

    private struct ParsedStem {
        var slug: String
        var meetingStart: Date?
    }

    private static func documents(from files: [URL]) -> [TranscriptDocument] {
        var protocols: [String: URL] = [:]
        var transcripts: [String: URL] = [:]
        for url in files {
            let stem = url.deletingPathExtension().lastPathComponent
            switch url.pathExtension.lowercased() {
            case "md": protocols[stem] = url
            case "txt": transcripts[stem] = url
            default: continue
            }
        }
        let stems = Set(protocols.keys).union(transcripts.keys)
        return stems.map { stem in
            makeDocument(stem: stem, protocolURL: protocols[stem], transcriptURL: transcripts[stem])
        }
        .sorted(by: isNewer)
    }

    private static func makeDocument(stem: String, protocolURL: URL?, transcriptURL: URL?) -> TranscriptDocument {
        let protocolModified = modificationDate(of: protocolURL)
        let transcriptModified = modificationDate(of: transcriptURL)
        let modified = [protocolModified, transcriptModified].compactMap(\.self).max() ?? .distantPast
        let heading = protocolURL.flatMap { markdownTitle(at: $0) }
        let display = displayTitle(stem: stem, markdownTitle: heading)
        return TranscriptDocument(
            id: stem,
            title: display.title,
            meetingStart: display.meetingStart,
            modified: modified,
            protocolURL: protocolURL,
            transcriptURL: transcriptURL,
        )
    }

    private static func markdownTitle(at url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), !data.isEmpty else { return nil }
        return markdownTitle(in: String(decoding: data, as: UTF8.self))
    }

    private static func modificationDate(of url: URL?) -> Date? {
        guard let url else { return nil }
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private static func isNewer(_ lhs: TranscriptDocument, _ rhs: TranscriptDocument) -> Bool {
        let left = lhs.meetingStart ?? lhs.modified
        let right = rhs.meetingStart ?? rhs.modified
        if left != right { return left > right }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private static func parsedStem(_ stem: String) -> ParsedStem {
        guard let match = stem.wholeMatch(of: /^(\d{8})_(\d{4}|\d{6})_(.+)$/) else {
            return ParsedStem(slug: stripShortIDs(stem), meetingStart: nil)
        }
        let dateStamp = String(match.output.1)
        let timeStamp = String(match.output.2)
        let format = timeStamp.count == 6 ? "yyyyMMdd HHmmss" : "yyyyMMdd HHmm"
        let meetingStart = DateFormatter.filenameStamp(format).date(from: "\(dateStamp) \(timeStamp)")
        return ParsedStem(slug: stripShortIDs(String(match.output.3)), meetingStart: meetingStart)
    }

    /// The pipeline appends an 8-hex job id, and a re-import can leave an older
    /// one in the slug as well. Both are noise in a title.
    private static func stripShortIDs(_ slug: String) -> String {
        var result = slug
        while let range = result.range(of: #"_[0-9a-f]{8}$"#, options: .regularExpression) {
            result.removeSubrange(range)
        }
        return result
    }

    private static func humanize(_ slug: String) -> String {
        slug.split(separator: "_").map { $0.capitalized }.joined(separator: " ")
    }

    /// English, like the rest of the UI, whatever the Mac's language is.
    /// The calendar's time zone is copied so a test calendar and the stamp
    /// describe the same instant.
    private static func englishFormatter(_ format: String, calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter
    }
}
