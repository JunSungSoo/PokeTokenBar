import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class ReleaseHistoryTests: XCTestCase {
    private var documentURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/releases/zip/00-Release History.txt")
    }

    func testBundledHistoryIsTheReleaseHistoryDocument() throws {
        // The app ships a copy; this fails whenever docs/releases/zip changes without re-copying it.
        XCTAssertEqual(try XCTUnwrap(ReleaseHistory.bundledText()), try String(contentsOf: documentURL, encoding: .utf8))
    }

    func testEntriesKeepDocumentOrderTitlesAndChanges() {
        let text = "2026-11-20 (1차 배포)\n\n- 첫 변경\n- 둘째 변경\n\n2026-11-17 (2차 배포)\n\n- 셋째 변경\n"
        let entries = ReleaseHistory.entries(from: text)
        XCTAssertEqual(entries.map(\.title), ["2026-11-20 (1차 배포)", "2026-11-17 (2차 배포)"])
        XCTAssertEqual(entries.map(\.changes), [["첫 변경", "둘째 변경"], ["셋째 변경"]])
        let windows = "2026-11-20 (1차 배포)\r\n\r\n- 줄바꿈된\r\n  변경\r\n"
        XCTAssertEqual(ReleaseHistory.entries(from: windows), [.init(title: "2026-11-20 (1차 배포)", changes: ["줄바꿈된 변경"])],
                       "CRLF files and wrapped change lines keep one entry")
    }

    func testEveryDocumentedDeploymentAppearsWithItsChanges() throws {
        struct History: Decodable {
            struct Deployment: Decodable {
                let date: String
                let releaseNumber: Int
                let changes: [String]
            }
            let entries: [Deployment]
        }

        let document = try String(contentsOf: documentURL, encoding: .utf8)
        let titles = document.split(separator: "\n").map(String.init).filter { $0.range(of: #"^\d{4}-\d{2}-\d{2} \(\d+차 배포\)$"#, options: .regularExpression) != nil }
        let entries = ReleaseHistory.entries(from: document)
        XCTAssertEqual(entries.map(\.title), titles)
        XCTAssertTrue(entries.allSatisfy { !$0.changes.isEmpty })

        let metadata = documentURL.deletingLastPathComponent().appendingPathComponent("history.json")
        let history = try JSONDecoder().decode(History.self, from: Data(contentsOf: metadata))
        let latest = try XCTUnwrap(history.entries.max {
            ($0.date, $0.releaseNumber) < ($1.date, $1.releaseNumber)
        })
        XCTAssertEqual(entries.first, .init(title: "\(latest.date) (\(latest.releaseNumber)차 배포)",
                                            changes: latest.changes))
    }

    func testReleaseNoteWindowShowsTheBundledHistory() throws {
        let controller = ReleaseNotesWindowController.shared
        defer { controller.close() }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertEqual(window.title, "Release Note")
        let hosting = try XCTUnwrap(window.contentViewController as? NSHostingController<ReleaseNotesView>)
        XCTAssertEqual(hosting.rootView.entries, ReleaseHistory.bundled)
        XCTAssertFalse(hosting.rootView.entries.isEmpty)
        controller.show()
        XCTAssertTrue(controller.window === window, "A second press brings the same window forward")
    }

    func testReleaseNotesWindowDrawsTheHistoryText() async throws {
        let controller = ReleaseNotesWindowController.shared
        defer { controller.close() }
        controller.show()
        let window = try XCTUnwrap(controller.window)
        window.appearance = NSAppearance(named: .aqua)
        let content = try XCTUnwrap(window.contentView)
        try await Task.sleep(for: .milliseconds(300))
        content.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
        content.cacheDisplay(in: content.bounds, to: bitmap)
        // ImageRenderer leaves ScrollView content blank, so count dark text pixels in the real window instead.
        var textPixels = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) where (bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 1) < 0.4 {
                textPixels += 1
            }
        }
        XCTAssertGreaterThan(textPixels, 500, "The notes window must show the history text")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/tmp/ptb-release-notes.png"))
    }
}
