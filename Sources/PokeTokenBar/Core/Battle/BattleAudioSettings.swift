import Foundation
import Observation

@MainActor
@Observable
final class BattleAudioSettings {
    static let volumeKey = "battleMusicVolume"
    private(set) var volume: Double
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var onVolumeChange: ((Double) -> Void)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        volume = defaults.object(forKey:Self.volumeKey) == nil ? 0.35 : Self.clamp(defaults.double(forKey:Self.volumeKey))
    }
    private static func clamp(_ value: Double) -> Double { value.isFinite ? min(1,max(0,value)) : 0.35 }
    func setVolume(_ value: Double) {
        volume = Self.clamp(value)
        defaults.set(volume,forKey:Self.volumeKey)
        onVolumeChange?(volume)
    }
}
