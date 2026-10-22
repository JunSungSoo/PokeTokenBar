import XCTest
@testable import PokeTokenBar

@MainActor
final class BattleAudioSettingsTests: XCTestCase {
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
