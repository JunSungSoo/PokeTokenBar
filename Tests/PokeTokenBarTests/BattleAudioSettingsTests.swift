import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleAudioSettingsTests: XCTestCase {
    func testVolumePopoverOpensBelowToolbarButton() async throws {
        let name = "ptb-volume-popover-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName:name))
        defer { defaults.removePersistentDomain(forName:name) }
        let host = NSHostingController(rootView:BattleVolumeControl(settings:BattleAudioSettings(defaults:defaults),
            label:"BGM volume",effectsLabel:"Effects volume").frame(width:300,height:60))
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let window = NSWindow(contentRect:NSRect(x:screen.midX-150,y:screen.midY,width:300,height:60),
            styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host
        window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        try await Task.sleep(for:.milliseconds(150))
        let existing = Set(NSApp.windows.map(\.windowNumber))
        for type in [NSEvent.EventType.leftMouseDown,.leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with:type,location:NSPoint(x:150,y:30),modifierFlags:[],
                timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:window.windowNumber,context:nil,
                eventNumber:1,clickCount:1,pressure:1))
            window.sendEvent(event)
        }
        try await Task.sleep(for:.milliseconds(400))
        let popup = try XCTUnwrap(NSApp.windows.first { !existing.contains($0.windowNumber) && $0.isVisible })
        defer { popup.orderOut(nil) }
        XCTAssertGreaterThan(popup.frame.height,120,"Both volume controls must fit in the popover")
        XCTAssertLessThan(popup.frame.maxY,window.frame.midY+5,"The toolbar popup must open below its button")
    }

    func testEffectsVolumePersistsIndependentlyFromMusicIncludingMuteAndInvalidValues() throws {
        let name = "ptb-effects-volume-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = BattleAudioSettings(defaults: defaults)
        XCTAssertEqual(settings.effectsVolume, 0.35)
        settings.setVolume(0.72)
        var musicChanges = 0
        settings.onVolumeChange = { _ in musicChanges += 1 }
        for (input, expected) in [(0.6, 0.6), (0, 0), (1, 1), (-1, 0), (2, 1), (.nan, 0.35)] {
            settings.setEffectsVolume(input)
            XCTAssertEqual(settings.effectsVolume, expected)
            let nextBattle = BattleAudioSettings(defaults: defaults)
            XCTAssertEqual(nextBattle.effectsVolume, expected)
            XCTAssertEqual(nextBattle.volume, 0.72)
        }
        XCTAssertEqual(musicChanges, 0)
        defaults.set(-0.5, forKey: BattleAudioSettings.effectsVolumeKey)
        XCTAssertEqual(BattleAudioSettings(defaults: defaults).effectsVolume, 0)
    }
}
