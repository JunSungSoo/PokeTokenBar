import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class PikachuMoveEffectsTests: XCTestCase {
    private let rects=["own-0":CGRect(x:45,y:177,width:128,height:128),"foe-0":CGRect(x:405,y:25,width:128,height:128)]
    private func event(_ profile: PikachuMoveProfile,hit: Bool=true,reverse: Bool=false) -> BattleVisualEvent {
        BattleVisualEvent(id:1,move:profile.rawValue,type:"Electric",category:profile == .protect ? "Status" : "Special",
            source:BattleEffectPosition(own:!reverse,slot:0),targets:[BattleEffectTarget(position:BattleEffectPosition(own:profile == .protect ? !reverse : reverse,slot:0),hit:hit)],moveID:profile.rawValue)
    }
    private func render(_ event: BattleVisualEvent,seconds: Double) throws -> NSBitmapImageRep {
        let duration=try XCTUnwrap(PikachuMoveProfile.resolve(event)).duration
        return NSBitmapImageRep(cgImage:try XCTUnwrap(ImageRenderer(content:PikachuMoveEffects(event:event,rects:rects,progress:seconds/duration).frame(width:570,height:320)).cgImage))
    }
    private func alpha(_ image: NSBitmapImageRep,in rect: CGRect=CGRect(x:0,y:0,width:570,height:320)) -> Double {
        var sum=0.0
        for y in stride(from:Int(rect.minY),to:Int(rect.maxY),by:3) { for x in stride(from:Int(rect.minX),to:Int(rect.maxX),by:3) {
            sum += Double(image.colorAt(x:x,y:y)?.alphaComponent ?? 0)
        } }
        return sum
    }
    func testFourAuthoredSamplesHaveDistinctVisibleFramesAndFiniteLifetimes() throws {
        var frames=Set<Data>()
        for profile in PikachuMoveProfile.allCases {
            let seconds: Double = profile == .protect ? 0.8 : profile == .quickattack ? 0.48 : profile == .voltswitch ? 0.65 : 0.57
            let bitmap=try render(event(profile),seconds:seconds)
            XCTAssertGreaterThan(alpha(bitmap),10,profile.rawValue)
            let png=try XCTUnwrap(bitmap.representation(using:.png,properties:[:]))
            frames.insert(png)
            try png.write(to:URL(fileURLWithPath:"/private/tmp/ptb-pikachu-new-\(profile.rawValue).png"))
            XCTAssertEqual(alpha(try render(event(profile),seconds:profile.duration)),0)
        }
        XCTAssertEqual(frames.count,4)
        var charging=event(.thunderbolt);charging.phase="charge"
        XCTAssertNil(PikachuMoveProfile.resolve(charging))
        XCTAssertNil(PikachuMoveProfile.resolve(BattleVisualEvent(id:2,move:"Surf",type:"Water",category:"Special",source:.init(own:true,slot:0),targets:[])))
    }
    func testMissSuppressesImpactAndReverseMovesImpactToOppositeSide() throws {
        for profile in [PikachuMoveProfile.thunderbolt,.quickattack,.voltswitch] {
            let time: Double = profile == .thunderbolt ? 1.15 : profile == .quickattack ? 0.85 : 1.1
            let target=CGRect(x:415,y:35,width:110,height:110)
            XCTAssertGreaterThan(alpha(try render(event(profile),seconds:time),in:target),10,profile.rawValue)
            XCTAssertEqual(alpha(try render(event(profile,hit:false),seconds:time),in:target),0,accuracy:0.01,profile.rawValue)
            XCTAssertGreaterThan(alpha(try render(event(profile,reverse:true),seconds:time),in:CGRect(x:55,y:185,width:110,height:110)),10,profile.rawValue)
        }
        XCTAssertEqual(alpha(try render(event(.protect,hit:false),seconds:0.8)),0)
    }
    func testVoltSwitchReturnEnergyTravelsBackWithoutMissParticles() throws {
        let time=1.72
        let launchSide=CGRect(x:60,y:190,width:140,height:110)
        XCTAssertGreaterThan(alpha(try render(event(.voltswitch),seconds:time),in:launchSide),1)
        XCTAssertEqual(alpha(try render(event(.voltswitch,hit:false),seconds:time)),0)
    }
}
