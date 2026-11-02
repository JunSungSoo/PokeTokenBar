import AppKit
import SwiftUI
import AVFoundation
import CryptoKit
import Vision
import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeChampionTests:XCTestCase {
    func testSixMembersAppearInOrderThenFadeOutBeforeChampionTitle()async {
        let p=ChallengeChampionPresentation();p.hold = .milliseconds(1);p.fade = .milliseconds(1)
        var shown:[Int]=[]
        await p.play(count:6,onReveal:{shown.append($0)})
        XCTAssertEqual(shown,[0,1,2,3,4,5]);XCTAssertTrue(p.completed);XCTAssertNil(p.index);XCTAssertEqual(p.opacity,0)
    }
    func testClosingCancelsSequenceWithoutShowingAFalseCompletion()async throws {
        let p=ChallengeChampionPresentation();p.hold = .seconds(1)
        var shown:[Int]=[];let task=Task{await p.play(count:6,onReveal:{shown.append($0)})}
        try await Task.sleep(for:.milliseconds(10));task.cancel();await task.value
        XCTAssertEqual(shown,[0]);XCTAssertFalse(p.completed)
    }
    func testChampionTrackMatchesProvidedAudioFramesAndRepeatsWithoutTrimming()throws {
        let directory=BattleEngineProcess.resourceDirectory,track=try BattleMusicTrack(directory:directory,cue:.championVictory)
        XCTAssertEqual(track.intro.frameLength,2178255);XCTAssertEqual(track.intro.format.sampleRate,44100)
        XCTAssertEqual(track.intro.format.channelCount,2);XCTAssertTrue(track.loop === track.intro)
        let root=BattleEngineProcess.sourceRoot
        let meta=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("music/champion-victory-source.json"))) as? [String:Any])
        let data=try Data(contentsOf:directory.appendingPathComponent("RubySapphireChampionVictory.wav"))
        XCTAssertEqual(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),meta["wavSHA256"] as? String)
    }
    func testRedBattleTrackMatchesSeparateProvidedAudioAndLoopsAtOriginalRate()throws {
        let directory=BattleEngineProcess.resourceDirectory,track=try BattleMusicTrack(directory:directory,cue:.championBattle)
        XCTAssertEqual(track.intro.frameLength,4119954);XCTAssertEqual(track.intro.format.sampleRate,44100)
        XCTAssertEqual(track.intro.format.channelCount,2);XCTAssertTrue(track.loop === track.intro)
        let root=BattleEngineProcess.sourceRoot
        let meta=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("music/champion-battle-source.json"))) as? [String:Any])
        let wav=try Data(contentsOf:directory.appendingPathComponent("RubySapphireChampionBattle.wav"))
        let source=try Data(contentsOf:root.appendingPathComponent("music/RubySapphireChampionBattle.ogg"))
        XCTAssertEqual(SHA256.hash(data:wav).map{String(format:"%02x",$0)}.joined(),meta["wavSHA256"] as? String)
        XCTAssertEqual(SHA256.hash(data:source).map{String(format:"%02x",$0)}.joined(),meta["sourceSHA256"] as? String)
        XCTAssertNotEqual(wav,try Data(contentsOf:directory.appendingPathComponent("RubySapphireChampionVictory.wav")))
    }
    func testProductionChampionFinaleRendersTitleAndBottomCloseOffscreen()async throws {
        let sequence=ChallengeChampionPresentation();sequence.hold = .milliseconds(200);sequence.fade = .milliseconds(40)
        let view=ChallengeChampionView(runID:"render",team:ChallengeRunTests().team(),language:.ko,onClose:{},presentation:sequence).frame(width:660,height:650).background(Color(nsColor:.windowBackgroundColor)).environment(\.colorScheme,.dark)
        let host=NSHostingController(rootView:view);host.sizingOptions=[]
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:660,height:650),styleMask:[.borderless],backing:.buffered,defer:false)
        window.appearance=NSAppearance(named:.darkAqua);host.view.appearance=window.appearance
        window.contentViewController=host;host.view.frame=NSRect(x:0,y:0,width:660,height:650);host.view.autoresizingMask=[.width,.height];window.orderFront(nil)
        defer{window.orderOut(nil);window.contentViewController=nil}
        func renderedText(_ bitmap:NSBitmapImageRep)throws->String {
            let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate
            request.recognitionLanguages=["ko-KR","en-US"]
            try VNImageRequestHandler(cgImage:try XCTUnwrap(bitmap.cgImage),options:[:]).perform([request])
            return (request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined(separator:" ")
        }
        try await Task.sleep(for:.milliseconds(100));host.view.layoutSubtreeIfNeeded()
        XCTAssertFalse(sequence.completed)
        let before=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:before)
        XCTAssertFalse(try renderedText(before).contains("닫기"),"Close must not appear during the six-member introduction")
        try XCTUnwrap(before.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-champion-before-trophy.png"))
        let end=Date().addingTimeInterval(5)
        while !sequence.completed,Date()<end{try await Task.sleep(for:.milliseconds(20))}
        XCTAssertTrue(sequence.completed);try await Task.sleep(for:.milliseconds(150));host.view.layoutSubtreeIfNeeded()
        let bitmap=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds));host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
        let text=try renderedText(bitmap)
        XCTAssertTrue(text.contains("닫기"),"The trophy and Close must appear together: \(text)")
        XCTAssertTrue(text.contains("Champion"))
        try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-champion-complete.png"))
        XCTAssertEqual(host.view.bounds.size,CGSize(width:660,height:650))
    }
    func testLegacyCollectionEntriesDecodeWithoutATrophy()throws {
        let entry=DexEntry(id:"legacy",baseID:6,finalID:6,chainOrder:[6],rarity:.common,caughtAt:nil)
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(entry)) as? [String:Any]);json.removeValue(forKey:"championAchievedAt")
        let restored=try JSONDecoder().decode(DexEntry.self,from:JSONSerialization.data(withJSONObject:json))
        XCTAssertNil(restored.championAchievedAt);XCTAssertEqual(restored.id,"legacy")
    }
}
