import XCTest
@testable import PokeTokenBar

final class SafariCaptureOddsTests: XCTestCase {
    // Evaluated independently from PokéRogue attempt-capture-phase.ts at revision
    // 967ac11fad5b31ead174077c6934b5bcded097a2 (normal ball, 50% HP, no status).
    func testOriginalReferenceVectors() {
        let vectors: [(Int,Bool,Int,Int,Int,Int,Double)] = [
            (3,false,649,2,26406,0,0.06541360211335245),
            (45,false,0,30,43875,0,0.30006241241720133),
            (45,false,649,30,43875,10,0.314492762327357),
            (45,true,649,60,49964,20,0.4680728136604593),
            (255,true,649,340,65536,85,1),
            (190,false,200,127,57506,10,0.6835006414456071)]
        for (rate,shiny,dex,a,b,c,p) in vectors {
            let odds = SafariCaptureOdds(captureRate:rate,shiny:shiny,registeredSpecies:dex)
            XCTAssertEqual(odds.modifiedRate,a); XCTAssertEqual(odds.shakeThreshold,b)
            XCTAssertEqual(odds.criticalThreshold,c); XCTAssertEqual(odds.successProbability,p,accuracy:1e-12)
        }
    }
    func testReachableDexTierBoundaries() {
        for (count,threshold) in [(100,0),(101,2),(200,2),(201,5),(400,5),(401,7),(600,7),(601,10),(649,10)] {
            XCTAssertEqual(SafariCaptureOdds(captureRate:45,registeredSpecies:count).criticalThreshold,threshold)
        }
    }
    func testActualFailedCheckDeterminesZeroOneOrTwoShakes() {
        let odds = SafariCaptureOdds(captureRate:45)
        for shakes in 0...2 {
            var rolls = [UInt64(255)] + Array(repeating:UInt64(0),count:shakes) + [65535]
            let result = odds.resolve { rolls.removeFirst() }
            XCTAssertTrue(result.isValid); XCTAssertFalse(result.caught); XCTAssertFalse(result.critical)
            XCTAssertEqual(result.shakes,shakes); XCTAssertTrue(rolls.isEmpty)
        }
        var rolls: [UInt64] = [255,0,0,0]
        let result = odds.resolve { rolls.removeFirst() }
        XCTAssertTrue(result.isValid); XCTAssertTrue(result.caught); XCTAssertEqual(result.shakes,3); XCTAssertTrue(rolls.isEmpty)
    }
    func testCriticalNeedsOnlyOneCheckAndCanFail() {
        let odds = SafariCaptureOdds(captureRate:45,registeredSpecies:649)
        for roll: UInt64 in [0,65535] {
            var rolls: [UInt64] = [0,roll]
            let result = odds.resolve { rolls.removeFirst() }
            XCTAssertTrue(result.isValid); XCTAssertTrue(result.critical); XCTAssertEqual(result.shakes,1)
            XCTAssertEqual(result.caught,roll == 0); XCTAssertTrue(rolls.isEmpty)
        }
        // The critical threshold is exclusive, matching randInt(256) < threshold.
        var rolls: [UInt64] = [UInt64(odds.criticalThreshold),65535]
        XCTAssertFalse(odds.resolve { rolls.removeFirst() }.critical)
    }
    func testGuaranteedCatchSkipsOrdinaryChecksButKeepsCriticalCheck() {
        let odds = SafariCaptureOdds(captureRate:255,shiny:true,registeredSpecies:649)
        var ordinary: [UInt64] = [255]
        XCTAssertTrue(odds.resolve { ordinary.removeFirst() }.caught); XCTAssertTrue(ordinary.isEmpty)
        var critical: [UInt64] = [0,65535]
        XCTAssertTrue(odds.resolve { critical.removeFirst() }.caught); XCTAssertTrue(critical.isEmpty)
    }
    func testPercentagePointModifiersPreserveFinalProbabilityIncludingCritical() {
        let base = SafariCaptureOdds(captureRate:45,registeredSpecies:649)
        for modifier in [-100.0,-6,-3,5,10,100] {
            let odds = SafariCaptureOdds(captureRate:45,registeredSpecies:649,modifier:modifier)
            let expected = min(1,max(0,base.successProbability+modifier/100))
            XCTAssertEqual(odds.successProbability,expected,accuracy:1e-12)
            let q = Double(odds.shakeThreshold)/65536, c = odds.criticalProbability
            XCTAssertEqual((1-c)*pow(q,3)+c*q,expected,accuracy:0.000025)
        }
    }
    func testOriginalCatalogExceptionsAndLegacySessionCompatibility() throws {
        let catalog = try SafariCatalog.load()
        XCTAssertEqual(catalog.species.first { $0.id == 550 }?.captureRate,190)
        XCTAssertEqual(catalog.species.first { $0.id == 376 }?.captureRate,10)
        var session = SafariSession(area:.plains,seed:7,shinyDenominator:4096)
        try session.continueJourney(catalog:catalog)
        session.registeredSpeciesCount = 649
        try session.act(.ball)
        let saved = try JSONEncoder().encode(session)
        let restored = try JSONDecoder().decode(SafariSession.self,from:saved)
        XCTAssertEqual(restored.lastCapture,session.lastCapture)
        XCTAssertNotNil(restored.lastCapture); XCTAssertEqual(restored.randomState,session.randomState)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with:saved) as? [String:Any])
        legacy.removeValue(forKey:"lastCapture"); legacy.removeValue(forKey:"registeredSpeciesCount")
        let old = try JSONDecoder().decode(SafariSession.self,from:JSONSerialization.data(withJSONObject:legacy))
        XCTAssertNil(old.lastCapture); XCTAssertNil(old.registeredSpeciesCount)
        try old.validate(catalog:catalog)
    }
}
