import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleFieldTests: XCTestCase {
    func testFieldStateCodingLabelsAndRenderingInEveryLanguage() throws {
        var field = BattleFieldState(weather: "raindance", weatherSuppressed: true,
            conditions: ["trickroom", "gravity"], ownSide: [.init(id: "reflect", layers: 1)],
            foeSide: [.init(id: "spikes", layers: 3)])
        field.weatherTiming = .init(remaining: 4, maximum: 5)
        field.conditionTimings = ["trickroom": .init(remaining: 3, maximum: 5)]
        XCTAssertFalse(field.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(BattleFieldState.self, from: JSONEncoder().encode(field)), field)
        XCTAssertTrue(BattleFieldState(weather: "", weatherSuppressed: false, conditions: [], ownSide: [], foeSide: []).isEmpty)
        XCTAssertFalse(BattleFieldState(weather: "", weatherSuppressed: false, conditions: ["gravity"], ownSide: [], foeSide: []).isEmpty)
        XCTAssertFalse(BattleFieldState(weather: "", weatherSuppressed: false, conditions: [], ownSide: [.init(id:"reflect",layers:1)], foeSide: []).isEmpty)
        XCTAssertFalse(BattleFieldState(weather: "", weatherSuppressed: false, conditions: [], ownSide: [], foeSide: [.init(id:"spikes",layers:1)]).isEmpty)
        let ids = ["trickroom","magicroom","wonderroom","gravity","mudsport","watersport","reflect","lightscreen","safeguard","mist","tailwind","stealthrock","spikes","toxicspikes","luckychant","rainbow","swamp","seaoffire"]
        for language in AppLanguage.allCases {
            let l = L(language)
            for id in ids {
                let text = l.battleFieldEffect(id)
                XCTAssertFalse(text.isEmpty)
                XCTAssertNotEqual(text, l.battleUnknownMove, id)
                XCTAssertNotEqual(text, l.battleStatus("unknown"), id)
            }
            XCTAssertFalse(l.battleFieldTitle.isEmpty); XCTAssertFalse(l.battleWeatherSuppressed.isEmpty)
            let renderer = ImageRenderer(content: BattleFieldStatus(field: field, language: language).frame(width: 480))
            XCTAssertNotNil(renderer.nsImage)
            let unsuppressed = BattleFieldState(weather:"hail",weatherSuppressed:false,conditions:[],ownSide:[],foeSide:[])
            XCTAssertNotNil(ImageRenderer(content:BattleFieldStatus(field:unsuppressed,language:language).frame(width:480)).nsImage)
            let clear = BattleFieldState(weather: "", weatherSuppressed: false, conditions: [], ownSide: [], foeSide: [])
            XCTAssertNotNil(ImageRenderer(content: BattleFieldStatus(field: clear, language: language).frame(width:480)).nsImage)
            for event in ["|-fieldstart|move: Trick Room", "|-fieldend|move: Gravity", "|-sidestart|p1: Me|Reflect", "|-sideend|p2: Opponent|Spikes"] {
                let description = try XCTUnwrap(BattleLogText.describe(event, language: language))
                XCTAssertFalse(description.isEmpty)
                XCTAssertFalse(description.contains("move:"))
            }
        }
        XCTAssertTrue(try XCTUnwrap(BattleLogText.describe("|-sidestart|p1: Me|Reflect", language:.ko)).contains("아군"))
        XCTAssertTrue(try XCTUnwrap(BattleLogText.describe("|-sideend|p2: Opponent|Spikes", language:.ko)).contains("상대"))
    }
    func testTimerRatiosPersistAndRenderWithoutAssumingFiveTurns() throws {
        for (remaining, maximum) in [(5,5),(4,5),(3,5),(4,4),(1,4)] {
            let timer = BattleFieldTiming(remaining: remaining, maximum: maximum)
            XCTAssertEqual(timer.label, "\(remaining)/\(maximum)")
            for language in AppLanguage.allCases {
                let field = BattleFieldState(weather: "raindance", weatherSuppressed: false,
                    conditions: ["trickroom"], ownSide: [.init(id: "tailwind", layers: 1, timing: timer)], foeSide: [],
                    weatherTiming: timer, conditionTimings: ["trickroom": timer])
                XCTAssertEqual(try JSONDecoder().decode(BattleFieldState.self, from: JSONEncoder().encode(field)), field)
                XCTAssertNotNil(ImageRenderer(content: BattleFieldStatus(field: field, language: language).frame(width: 240)).nsImage)
                XCTAssertFalse(L(language).battleFieldUntilRemoved.isEmpty)
            }
        }
        // Exercise each production label, not just the formatter/model.
        for location in 0..<3 {
            func image(_ remaining: Int) throws -> Data {
                let timer = BattleFieldTiming(remaining: remaining, maximum: 5)
                let field = BattleFieldState(weather: "raindance", weatherSuppressed: false,
                    conditions: ["trickroom"], ownSide: [.init(id: "reflect", layers: 1, timing: location == 2 ? timer : nil)], foeSide: [],
                    weatherTiming: location == 0 ? timer : nil,
                    conditionTimings: location == 1 ? ["trickroom": timer] : [:])
                return try XCTUnwrap(ImageRenderer(content: BattleFieldStatus(field: field, language: .ko).frame(width: 240)).nsImage?.tiffRepresentation)
            }
            XCTAssertNotEqual(try image(4), try image(3), "Timer must change the actual weather/field/side label: \(location)")
        }
    }
}
