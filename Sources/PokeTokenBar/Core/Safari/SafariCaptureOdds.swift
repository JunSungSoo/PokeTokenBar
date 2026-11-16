import Foundation

/// PokéRogue normal-ball rules with an explicit 50% HP ratio; no status or event bonus.
/// Rock/bait changes the final probability in percentage points, not the species catch rate.
struct SafariCaptureOdds: Sendable {
    let modifiedRate: Int
    let criticalThreshold: Int
    let shakeThreshold: Int
    let successProbability: Double
    let guaranteed: Bool
    var criticalProbability: Double { Double(criticalThreshold) / 256 }
    init(captureRate: Int, shiny: Bool = false, registeredSpecies: Int = 0, modifier: Double = 0) {
        modifiedRate = Int((Double(max(0,min(255,captureRate))) * (2.0/3.0) * (shiny ? 2:1)).rounded())
        let count = max(0,registeredSpecies)
        let dex = count > 800 ? 2.5 : count > 600 ? 2 : count > 400 ? 1.5 : count > 200 ? 1 : count > 100 ? 0.5 : 0
        criticalThreshold = min(256,max(0,Int(floor(dex * Double(min(255,modifiedRate))/6))))
        let critical = Double(criticalThreshold)/256
        let baseThreshold = modifiedRate <= 0 ? 0 : min(65536,Int((65536*pow(Double(modifiedRate)/255,3.0/16.0)).rounded()))
        let q = Double(baseThreshold)/65536
        let base = modifiedRate >= 255 ? 1 : (1-critical)*pow(q,3)+critical*q
        successProbability = min(1,max(0,base+(modifier.isFinite ? modifier:0)/100))
        guaranteed = successProbability >= 1
        if modifier == 0 { shakeThreshold = baseThreshold }
        else {
            var low = 0.0, high = 1.0
            for _ in 0..<60 {
                let mid = (low+high)/2
                if (1-critical)*pow(mid,3)+critical*mid < successProbability { low = mid } else { high = mid }
            }
            shakeThreshold = min(65536,max(0,Int(((low+high)/2*65536).rounded())))
        }
    }
    /// The caller supplies the persisted session stream. Presentation never rolls catch RNG.
    func resolve(next: () -> UInt64) -> SafariCaptureResult {
        let critical = Int(next() % 256) < criticalThreshold
        if critical {
            let caught = Int(next() % 65536) < shakeThreshold
            return SafariCaptureResult(caught:caught,critical:true,shakes:1)
        }
        for check in 0..<3 {
            if !guaranteed && Int(next() % 65536) >= shakeThreshold {
                return SafariCaptureResult(caught:false,critical:false,shakes:check)
            }
        }
        return SafariCaptureResult(caught:true,critical:false,shakes:3)
    }
}

struct SafariCaptureResult: Codable, Sendable, Equatable {
    let caught: Bool
    let critical: Bool
    let shakes: Int
    var visualSeed: UInt64 = 1
    var isValid: Bool { critical ? shakes == 1 : caught ? shakes == 3 : (0...2).contains(shakes) }
}
