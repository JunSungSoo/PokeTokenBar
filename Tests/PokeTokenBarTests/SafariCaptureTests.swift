import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

final class SafariCaptureSequenceTests: XCTestCase {
    func testParabolicFlightAndOriginalAbsorptionEasing() {
        let sequence = SafariCaptureSequence(caught:true)
        let start = sequence.frame(at:0)
        XCTAssertEqual(start.phase,.flight); XCTAssertEqual(start.x,16); XCTAssertEqual(start.y,80)
        let halfway = sequence.frame(at:0.25)
        XCTAssertEqual(halfway.x,126); XCTAssertEqual(halfway.y,0)
        XCTAssertEqual(halfway.angle,0) // original throw does not spin the ball
        XCTAssertTrue(halfway.ballBehindPokemon == false)
        XCTAssertTrue(sequence.frame(at:0.31).ballBehindPokemon)
        let opening = sequence.frame(at:0.5)
        XCTAssertEqual(opening.open,0.5)
        let absorbing = sequence.frame(at:0.75)
        XCTAssertEqual(absorbing.open,1)
        XCTAssertEqual(absorbing.pokemonScale,1-0.75*(1-cos(Double.pi/4)),accuracy:0.000001)
        XCTAssertEqual(absorbing.pokemonOpacity,1)
        XCTAssertEqual(sequence.frame(at:1).pokemonOpacity,0)
    }
    func testOriginalRecursiveBounceTimesAndVolumes() {
        let sequence = SafariCaptureSequence(caught:true)
        let bounces = sequence.sounds.filter { $0.name == "pb_bounce_1" }
        XCTAssertEqual(bounces.count,8)
        XCTAssertEqual(bounces.first?.time,1.6)
        XCTAssertEqual(bounces.last?.time ?? 0,2.29453125,accuracy:0.000001)
        for (i,sound) in bounces.enumerated() { XCTAssertEqual(sound.volume,pow(0.5,Double(i)),accuracy:0.000001) }
        XCTAssertEqual(sequence.frame(at:1.425).y,23,accuracy:0.000001) // Cubic.easeIn
        XCTAssertLessThan(sequence.frame(at:1.7).y,72)
    }
    func testNormalFailuresHaveZeroOneOrTwoCompletedShakes() {
        for shakes in 0...2 {
            let sequence = SafariCaptureSequence(caught:false,failedShakes:shakes)
            XCTAssertEqual(sequence.shakeCount,shakes)
            XCTAssertEqual(sequence.resultTime,sequence.shakeStartTime+Double(shakes+1))
            XCTAssertEqual(sequence.sounds.filter { $0.name == "pb_move" }.count,shakes)
            let escape = sequence.frame(at:sequence.resultTime+0.125)
            XCTAssertEqual(escape.phase,.escaped); XCTAssertEqual(escape.pokemonOpacity,1)
            XCTAssertEqual(escape.pokemonScale,0.25+0.75*sin(Double.pi/4),accuracy:0.000001)
            let done = sequence.frame(at:sequence.duration)
            XCTAssertEqual(done.pokemonScale,1); XCTAssertEqual(done.ballOpacity,0,accuracy:0.000001)
        }
    }
    func testSuccessLocksAfterThreeShakesAndUsesOriginalStarTextures() {
        let sequence = SafariCaptureSequence(caught:true)
        XCTAssertEqual(sequence.shakeCount,3)
        XCTAssertEqual(sequence.resultTime,6.29453125,accuracy:0.000001)
        XCTAssertEqual(sequence.duration,7.29453125,accuracy:0.000001)
        XCTAssertEqual(sequence.sounds.filter { $0.name == "pb_move" }.count,3)
        let shake = sequence.frame(at:sequence.shakeStartTime+1.25)
        XCTAssertEqual(shake.angle,27.5,accuracy:0.000001)
        let result = sequence.frame(at:sequence.resultTime+0.2)
        XCTAssertEqual(result.phase,.caught); XCTAssertEqual(result.pokemonOpacity,0)
        XCTAssertEqual(result.particles.filter { $0.texture == "4.png" }.count,3)
        XCTAssertGreaterThan(result.ballShade,0)
    }
    func testCriticalHasPreLandingQuiverAndOnePostLandingCheckEvenWhenItFails() {
        for success in [true,false] {
            let sequence = SafariCaptureSequence(result:SafariCaptureResult(caught:success,critical:true,shakes:1))
            XCTAssertEqual(sequence.bounceStart,3.31,accuracy:0.000001)
            XCTAssertEqual(sequence.shakeCount,1)
            XCTAssertEqual(sequence.sounds.first?.name,"crit_throw")
            XCTAssertNotEqual(sequence.frame(at:1.85).x,236)
            XCTAssertEqual(sequence.resultTime,sequence.shakeStartTime+2)
            XCTAssertEqual(sequence.frame(at:sequence.duration).pokemonOpacity,success ? 0:1)
        }
    }
    func testOpeningParticlesMatchOriginalCountFramesAndLifespan() {
        let sequence = SafariCaptureSequence(caught:true)
        XCTAssertTrue(sequence.frame(at:0.519).particles.isEmpty)
        let first = sequence.frame(at:0.521).particles
        XCTAssertEqual(first.count,1); XCTAssertEqual(first.first?.texture,"0.png")
        XCTAssertEqual(sequence.frame(at:0.85).particles.count,17)
        XCTAssertTrue(sequence.frame(at:1.416).particles.isEmpty)
    }
    func testFrameValuesAreFiniteAndUseOriginalFieldUnits() {
        for result in [SafariCaptureResult(caught:true,critical:false,shakes:3),SafariCaptureResult(caught:false,critical:false,shakes:0),SafariCaptureResult(caught:false,critical:true,shakes:1)] {
            let sequence = SafariCaptureSequence(result:result)
            for t in stride(from:0.0,through:sequence.duration+0.1,by:0.013) {
                let frame = sequence.frame(at:t)
                XCTAssertTrue((16...240).contains(frame.x)); XCTAssertTrue((-8...80).contains(frame.y))
                for value in [frame.pokemonOpacity,frame.pokemonScale,frame.ballOpacity,frame.open,frame.ballShade] {
                    XCTAssertTrue(value.isFinite && (0...1).contains(value))
                }
                XCTAssertTrue(frame.particles.allSatisfy { $0.alpha >= 0 && $0.alpha <= 1 })
            }
        }
    }
}

@MainActor
final class SafariCaptureRenderingTests: XCTestCase {
    func testAllTrainerThrowPosesRetainCrispPixels() throws {
        var poses = Set<Data>()
        for index in 0..<5 {
            let frame = try XCTUnwrap(SafariArtwork.redDisplayFrame(index))
            XCTAssertEqual(frame.width,192); XCTAssertEqual(frame.height,192)
            let bitmap = NSBitmapImageRep(cgImage:frame)
            poses.insert(try XCTUnwrap(bitmap.representation(using:.png,properties:[:])))
            XCTAssertEqual(bitmap.colorAt(x:0,y:0)?.alphaComponent,0)
        }
        XCTAssertEqual(poses.count,5)
    }
    func testCaptureStagesRenderOnProductionBattlefieldWithoutOpeningWindow() throws {
        let folder = ProcessInfo.processInfo.environment["PTB_SAFARI_CAPTURE_EVIDENCE"]
            .map { URL(fileURLWithPath:$0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("ptb-safari-capture-evidence")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let catalog = try SafariCatalog.load()
        let species = try XCTUnwrap(catalog.species.first { $0.id == 25 })
        var session = SafariSession(area:.metropolis,seed:1,shinyDenominator:4096)
        session.phase = .encounter
        session.wild = SafariPokemon(species:species,profile:.generate(seed:1),nature:.hardy,shiny:false)
        let success = SafariCaptureSequence(caught:true), failure = SafariCaptureSequence(caught:false)
        let stages: [(String,SafariCaptureSequence,Double)] = [
            ("throw",success,0.25),("absorb",success,0.75),("bounce",success,1.77),
            ("shake",success,success.shakeStartTime+1.25),("caught",success,success.resultTime+0.3),
            ("breakout",failure,failure.resultTime+0.2),("escaped",failure,failure.duration)]
        for (name,sequence,time) in stages {
            let renderer = ImageRenderer(content:SafariBattlefield(session:session,language:.ko,captureFrame:sequence.frame(at:time))
                .frame(width:632,height:280).background(Color.white).environment(\.colorScheme,.light))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage:try XCTUnwrap(renderer.cgImage))
            try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:folder.appendingPathComponent(name+".png"))
        }
        XCTAssertNil(SafariWindowController.shared.window)
    }
}

@MainActor
final class SafariCaptureAssetTests: XCTestCase {
    func testOriginalAtlasesAndEveryCaptureSoundDecode() throws {
        try SafariRogueAssets.validate()
        XCTAssertEqual(SafariRogueAssets.balls["pb"]?.width,12)
        XCTAssertEqual(SafariRogueAssets.particles["1.png"]?.width,8)
        let audio = SafariCaptureAudio()
        audio.setVolume(0); XCTAssertEqual(audio.volume,0)
        audio.setVolume(0.75); XCTAssertEqual(audio.volume,0.75)
        audio.setVolume(2); XCTAssertEqual(audio.volume,1)
        audio.stop()
    }
}
