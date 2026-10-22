import AppKit
import XCTest
@testable import PokeTokenBar

final class BattleWindowLayoutTests: XCTestCase {
    func testInitialWindowsFitVisibleScreenBeforeContentMeasurement() {
        for screen in [NSRect(x: 0, y: 40, width: 1280, height: 760), NSRect(x: -1512, y: 0, width: 1512, height: 930), NSRect(x: 0, y: 0, width: 1920, height: 1040)] {
            let layout = BattleWindowLayout(screen: screen)
            for rect in [layout.main, layout.field, layout.stats] { XCTAssertTrue(screen.contains(rect)) }
            XCTAssertFalse(layout.main.intersects(layout.field))
            XCTAssertFalse(layout.main.intersects(layout.stats))
            XCTAssertEqual(layout.main.height, min(700, screen.height))
            XCTAssertEqual(layout.main.width, 800, "Both modes use the selected 20% reduction from 1000 points")
        }
    }
    func testSmallScreenKeepsAllWindowControlsInsideVisibleArea() {
        let screen = NSRect(x: 0, y: 50, width: 1024, height: 700)
        let layout = BattleWindowLayout(screen: screen)
        for rect in [layout.main, layout.field, layout.stats] { XCTAssertTrue(screen.contains(rect)) }
    }
}
