import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleStatusNoticeTests: XCTestCase {
    func testRealEngineFlinchSleepPoisonBurnAndWeatherScenesHaveLocalizedNotices() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = root.appendingPathComponent("BattleEngine/runtime/node")
        process.arguments = [root.appendingPathComponent("BattleEngine/tests/fixtures/status-notices.cjs").path]
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
        let matches = try JSONDecoder().decode([String: [BattleFrame]].self, from: data)
        for frames in matches.values {
            for (player, frame) in frames.enumerated() {
                for language in AppLanguage.allCases {
                    let presentation = BattlePresentationEvents(frame: frame, language: language, ownPlayer: player)
                    for scene in frame.scenes ?? [] {
                        let index = scene.id - (frame.logOffset ?? 0)
                        let line = frame.log[index]
                        guard line.hasPrefix("|cant|") || line.hasPrefix("|-damage|") || line.hasPrefix("|-status|") else { continue }
                        let text = try XCTUnwrap(presentation.messages[scene.id], line)
                        XCTAssertTrue(presentation.events.contains { $0.id == scene.id && $0.phase != "state" }, line)
                        if line.hasPrefix("|cant|") {
                            XCTAssertTrue(text.contains(L(language).battleCannotAct))
                            let reason = line.split(separator: "|", omittingEmptySubsequences: false)[3]
                            XCTAssertTrue(text.contains(L(language).battleStatus(String(reason))))
                        }
                        for cause in ["psn", "brn", "Sandstorm"] where line.contains("[from] " + cause) {
                            XCTAssertTrue(text.contains(L(language).battleDamageCause(cause)), line)
                        }
                    }
                }
            }
        }
        for language in AppLanguage.allCases {
            for reason in ["par", "frz", "confusion", "attract", "Truant", "Taunt"] {
                let text = try XCTUnwrap(BattleLogText.describe("|cant|p2a: Raichu|\(reason)", language: language))
                XCTAssertTrue(text.contains(L(language).battleCannotAct))
                if ["par", "frz", "confusion", "attract"].contains(reason) { XCTAssertTrue(text.contains(L(language).battleStatus(reason))) }
            }
            XCTAssertTrue(try XCTUnwrap(BattleLogText.describe("|-activate|p2a: Raichu|confusion", language: language)).contains(L(language).battleStatus("confusion")))
            for cause in ["tox", "confusion", "hail", "recoil", "move: Leech Seed"] {
                XCTAssertFalse(L(language).battleDamageCause(cause).isEmpty)
            }
        }
    }

    func testNewMessagesAppendBelowExistingOnesAndExpireIndependently() {
        let start = Date(timeIntervalSince1970: 1000)
        var queue = BattleNoticeQueue()
        queue.append(id: 1, text: "Move", at: start)
        XCTAssertNil(queue.nextExpiry, "A running move remains visible even for a long original animation")
        queue.expire(at: start.addingTimeInterval(20))
        XCTAssertEqual(queue.entries.count, 1)
        queue.finish(id: 1, at: start.addingTimeInterval(20))
        queue.append(id: 2, text: "Flinch", at: start.addingTimeInterval(20.1))
        queue.finish(id: 2, at: start.addingTimeInterval(20.2))
        XCTAssertEqual(queue.entries.map(\.text), ["Move", "Flinch"])
        queue.expire(at: start.addingTimeInterval(21))
        XCTAssertEqual(queue.entries.map(\.id), [2])
        queue.expire(at: start.addingTimeInterval(24))
        XCTAssertTrue(queue.entries.isEmpty)
        XCTAssertNil(queue.nextExpiry)
        for id in 3...7 { queue.append(id: id, text: "\(id)", at: start) }
        XCTAssertEqual(queue.entries.map(\.id), [5,6,7], "A burst retains the latest messages within the battlefield")
        queue.finish(id: 3, at: start) // An older message may already have been evicted.
        queue.append(id: 6, text: "Updated", at: start)
        XCTAssertEqual(queue.entries.map(\.id), [5,7,6])
    }

    func testStackFitsSmallAndNormalBattlefieldsInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            var queue = BattleNoticeQueue()
            for id in 0..<3 {
                let text = try XCTUnwrap(BattleLogText.describe("|cant|p2a: Raichu|flinch", language: language))
                queue.append(id: id, text: String(repeating: text + " · ", count: 4))
            }
            for size in [CGSize(width: 320, height: 80), CGSize(width: 640, height: 300)] {
                let renderer = ImageRenderer(content: BattleNoticeStack(notices: queue.entries).frame(width: size.width, height: size.height))
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                XCTAssertEqual(bitmap.pixelsWide, Int(size.width))
                XCTAssertEqual(bitmap.pixelsHigh, Int(size.height))
                for x in 0..<bitmap.pixelsWide {
                    XCTAssertEqual(bitmap.colorAt(x: x, y: 0)?.alphaComponent, 0)
                    XCTAssertEqual(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1)?.alphaComponent, 0)
                }
                var visible = 0
                for y in 0..<bitmap.pixelsHigh {
                    XCTAssertEqual(bitmap.colorAt(x: 0, y: y)?.alphaComponent, 0)
                    XCTAssertEqual(bitmap.colorAt(x: bitmap.pixelsWide - 1, y: y)?.alphaComponent, 0)
                    if (bitmap.colorAt(x: bitmap.pixelsWide / 2, y: y)?.alphaComponent ?? 0) > 0 { visible += 1 }
                }
                XCTAssertGreaterThan(visible, 10, "The bounded stack must actually render, not simply hide its notices")
            }
        }
    }
}
