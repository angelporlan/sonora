@testable import MeetingTranscriber
import XCTest

final class TranscriptLibraryTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    // MARK: - Titles

    func testDisplayTitleStripsStampAndShortID() throws {
        let parsed = TranscriptLibrary.displayTitle(
            stem: "20260102_1530_team_meeting_a1b2c3d4",
            markdownTitle: nil,
        )
        XCTAssertEqual(parsed.title, "Team Meeting")
        let expected = try XCTUnwrap(DateFormatter.filenameStamp("yyyyMMdd HHmm").date(from: "20260102 1530"))
        XCTAssertEqual(parsed.meetingStart, expected)
    }

    func testDisplayTitleStripsCompoundedShortIDs() {
        let parsed = TranscriptLibrary.displayTitle(
            stem: "20260801_0900_daily_standup_a1b2c3d4_e5f6a7b8",
            markdownTitle: nil,
        )
        XCTAssertEqual(parsed.title, "Daily Standup")
    }

    func testDisplayTitleKeepsSecondsInTheStamp() throws {
        let parsed = TranscriptLibrary.displayTitle(
            stem: "20260102_153045_standup_abcdef12",
            markdownTitle: nil,
        )
        XCTAssertEqual(parsed.title, "Standup")
        let expected = try XCTUnwrap(
            DateFormatter.filenameStamp("yyyyMMdd HHmmss").date(from: "20260102 153045"),
        )
        XCTAssertEqual(parsed.meetingStart, expected)
    }

    func testDisplayTitleWithoutStampHumanizesTheStem() {
        let parsed = TranscriptLibrary.displayTitle(stem: "voice_memo", markdownTitle: nil)
        XCTAssertEqual(parsed.title, "Voice Memo")
        XCTAssertNil(parsed.meetingStart)
    }

    func testMarkdownTitleOverridesTheSlug() throws {
        let parsed = TranscriptLibrary.displayTitle(
            stem: "20260102_1530_team_meeting_a1b2c3d4",
            markdownTitle: "Meeting Protocol - Quarterly Review",
        )
        XCTAssertEqual(parsed.title, "Meeting Protocol - Quarterly Review")
        XCTAssertNotNil(parsed.meetingStart)
    }

    func testMarkdownTitleUsesTheFirstH1Only() {
        let text = """
        **Date:** 2026-01-02

        # Meeting Protocol - Quarterly Review

        ## Summary
        Hello
        """
        XCTAssertEqual(
            TranscriptLibrary.markdownTitle(in: text),
            "Meeting Protocol - Quarterly Review",
        )
    }

    func testReaderTextDropsTheLeadingH1() {
        let input = "# Meeting Protocol - Review\n\n**Date:** 2026-01-02\n"
        XCTAssertEqual(
            TranscriptLibrary.readerText(from: input),
            "**Date:** 2026-01-02\n",
        )
    }

    func testReaderTextLeavesATranscriptAlone() {
        let input = "[00:00] Hello\n[00:05] World\n"
        XCTAssertEqual(TranscriptLibrary.readerText(from: input), input)
    }

    // MARK: - Scan

    func testScanPairsProtocolAndTranscriptAndSortsByMeetingStart() throws {
        let dir = try makeTempDirectory(prefix: "transcript-library")
        try write("# Older\n", name: "20260101_0900_older_meeting_aaaaaaa1.md", in: dir)
        try write("older words", name: "20260101_0900_older_meeting_aaaaaaa1.txt", in: dir)
        try write("# Newer\n", name: "20260103_1000_newer_meeting_bbbbbbb2.md", in: dir)
        try "not a transcript".write(
            to: dir.appendingPathComponent("notes.json"),
            atomically: true,
            encoding: .utf8,
        )
        let recordings = dir.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        try "hidden".write(
            to: recordings.appendingPathComponent("20260104_1100_hidden_cccccccc.txt"),
            atomically: true,
            encoding: .utf8,
        )

        let scan = TranscriptLibrary.scan(directory: dir)
        XCTAssertFalse(scan.folderMissing)
        XCTAssertEqual(scan.documents.map(\.title), ["Newer", "Older"])
        let newer = try XCTUnwrap(scan.documents.first)
        XCTAssertNotNil(newer.protocolURL)
        XCTAssertNil(newer.transcriptURL)
        XCTAssertEqual(newer.kindSummary, "Protocol")
        let older = try XCTUnwrap(scan.documents.last)
        XCTAssertNotNil(older.protocolURL)
        XCTAssertNotNil(older.transcriptURL)
        XCTAssertEqual(older.kindSummary, "Protocol and transcript")
        XCTAssertEqual(older.preferredKind, .meetingProtocol)
    }

    func testScanUsesTheProtocolHeadingAsTheTitle() throws {
        let dir = try makeTempDirectory(prefix: "transcript-library-heading")
        try write(
            "# Meeting Protocol - Quarterly Review\n\n## Summary\nTalked.\n",
            name: "20260102_1530_team_meeting_a1b2c3d4.md",
            in: dir,
        )
        let scan = TranscriptLibrary.scan(directory: dir)
        XCTAssertEqual(scan.documents.map(\.title), ["Meeting Protocol - Quarterly Review"])
    }

    func testScanMissingFolder() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-library-missing-\(UUID().uuidString)")
        let scan = TranscriptLibrary.scan(directory: missing)
        XCTAssertTrue(scan.folderMissing)
        XCTAssertTrue(scan.documents.isEmpty)
    }

    func testTranscriptOnlyDocument() throws {
        let dir = try makeTempDirectory(prefix: "transcript-library-txt")
        try write("[00:00] Hello", name: "20260102_1530_call_abcdef12.txt", in: dir)
        let document = try XCTUnwrap(TranscriptLibrary.scan(directory: dir).documents.first)
        XCTAssertEqual(document.title, "Call")
        XCTAssertEqual(document.kindSummary, "Transcript")
        XCTAssertEqual(document.preferredKind, .transcript)
        XCTAssertNil(document.protocolURL)
    }

    // MARK: - Groups, dates, search

    func testGroupsTodayYesterdayAndMonth() throws {
        let calendar = utc
        let now = try date(2026, 1, 2, 18, 0, calendar: calendar)
        let documents = [
            sample("today", at: try date(2026, 1, 2, 15, 30, calendar: calendar)),
            sample("yesterday", at: try date(2026, 1, 1, 9, 5, calendar: calendar)),
            sample("march", at: try date(2026, 3, 5, 9, 15, calendar: calendar)),
            sample("last-year", at: try date(2025, 12, 20, 9, 0, calendar: calendar)),
        ]
        let titles = TranscriptLibrary.groups(documents, now: now, calendar: calendar).map(\.title)
        XCTAssertEqual(titles, ["Today", "Yesterday", "March 2026", "December 2025"])
    }

    func testListDateOmitsTheDayInsideItsSection() throws {
        let calendar = utc
        let now = try date(2026, 1, 2, 18, 0, calendar: calendar)
        XCTAssertEqual(
            TranscriptLibrary.listDate(try date(2026, 1, 2, 15, 30, calendar: calendar), now: now, calendar: calendar),
            "15:30",
        )
        XCTAssertEqual(
            TranscriptLibrary.listDate(try date(2026, 1, 1, 9, 5, calendar: calendar), now: now, calendar: calendar),
            "09:05",
        )
        XCTAssertEqual(
            TranscriptLibrary.listDate(try date(2026, 3, 5, 9, 15, calendar: calendar), now: now, calendar: calendar),
            "5 Mar, 09:15",
        )
        XCTAssertEqual(
            TranscriptLibrary.listDate(try date(2025, 12, 20, 9, 0, calendar: calendar), now: now, calendar: calendar),
            "20 Dec 2025",
        )
    }

    func testHeaderDate() throws {
        let calendar = utc
        let when = try date(2026, 1, 2, 15, 30, calendar: calendar)
        XCTAssertEqual(
            TranscriptLibrary.headerDate(when, calendar: calendar),
            "Friday, 2 January 2026 at 15:30",
        )
    }

    func testFilterMatchesTheTitleAndIgnoresBlankQueries() {
        let documents = [
            sample("Quarterly Review", at: .distantPast),
            sample("Standup", at: .distantPast),
        ]
        XCTAssertEqual(TranscriptLibrary.filter(documents, query: "review").map(\.title), ["Quarterly Review"])
        XCTAssertEqual(TranscriptLibrary.filter(documents, query: "  "), documents)
        XCTAssertTrue(TranscriptLibrary.filter(documents, query: "absent").isEmpty)
    }

    // MARK: - Helpers

    private func write(_ contents: String, name: String, in directory: URL) throws {
        try contents.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
        calendar: Calendar,
    ) throws -> Date {
        let components = DateComponents(
            calendar: calendar, year: year, month: month, day: day, hour: hour, minute: minute,
        )
        return try XCTUnwrap(calendar.date(from: components))
    }

    private func sample(_ title: String, at when: Date) -> TranscriptDocument {
        TranscriptDocument(
            id: title,
            title: title,
            meetingStart: when,
            modified: when,
            protocolURL: nil,
            transcriptURL: URL(fileURLWithPath: "/tmp/\(title).txt"),
        )
    }
}
