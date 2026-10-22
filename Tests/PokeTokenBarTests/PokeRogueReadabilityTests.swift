import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class PokeRogueReadabilityTests: XCTestCase {
    let rects=["own-0":CGRect(x:45,y:177,width:128,height:128),"foe-0":CGRect(x:405,y:25,width:128,height:128)]
    private func event(_ id: String,hit: Bool=true,own: Bool=true) -> BattleVisualEvent {
        .init(id:1,move:id,type:"Psychic",category:"Special",source:.init(own:own,slot:0),targets:[.init(position:.init(own:!own,slot:0),hit:hit)],moveID:id)
    }
    private func render(_ event: BattleVisualEvent,_ p: Double,reduced: Bool=false) throws -> NSBitmapImageRep {
        NSBitmapImageRep(cgImage:try XCTUnwrap(ImageRenderer(content:PokeRogueReadabilityEffects(event:event,rects:rects,progress:p,reducedMotion:reduced).frame(width:570,height:320)).cgImage))
    }
    private func alpha(_ rep: NSBitmapImageRep,in rect: CGRect=CGRect(x:0,y:0,width:570,height:320)) -> Double {
        var sum=0.0
        for y in stride(from:Int(rect.minY),to:Int(rect.maxY),by:3) { for x in stride(from:Int(rect.minX),to:Int(rect.maxX),by:3) {
            sum += Double(rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)
        } }
        return sum
    }
    func testPsychicOriginalIsTransparentButAuthoredBackgroundAndPressureAreVisible() throws {
        let catalog=try PokeRoguePreviewCatalog(directory:XCTUnwrap(Bundle.module.url(forResource:"PokeRoguePreview",withExtension:nil)))
        let raw=try XCTUnwrap(catalog.animation("psychic"))
        for frame in 0..<raw.frames.count { XCTAssertEqual(raw.background(at:Double(frame))?.opacity,0) }
        XCTAssertEqual(PokeRogueReadabilityProfile.psychic.backgroundOpacity(original:0,progress:0.5),0.24,accuracy:0.001)
        XCTAssertEqual(PokeRogueReadabilityProfile.psychic.backgroundOpacity(original:0.8,progress:0.5),0.8)
        XCTAssertEqual(PokeRogueReadabilityProfile.confusion.backgroundOpacity(original:0,progress:0.5),0.13,accuracy:0.001)
        XCTAssertEqual(PokeRogueReadabilityProfile.workup.backgroundOpacity(original:0.4,progress:0.5),0.4)
        XCTAssertEqual(PokeRogueReadabilityProfile.psychic.backgroundOpacity(original:0,progress:1),0)
        let target=CGRect(x:405,y:25,width:128,height:128)
        let pressure=try render(event("psychic"),0.68)
        XCTAssertGreaterThan(alpha(pressure,in:target),130,"Pressure must visibly surround the actual target, rather than only tinting the source")
        try XCTUnwrap(pressure.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/private/tmp/ptb-psychic-pressure.png"))
        XCTAssertNotEqual(pressure.tiffRepresentation,try render(event("confusion"),0.68).tiffRepresentation)
    }
    func testEveryDescriptionProfileVisibleAndNoImpactOnMissOrAtEnd() throws {
        for profile in PokeRogueReadabilityProfile.allCases {
            XCTAssertGreaterThan(alpha(try render(event(profile.rawValue),0.5)),20,profile.rawValue)
            XCTAssertEqual(alpha(try render(event(profile.rawValue,hit:false),0.5)),0,profile.rawValue)
            XCTAssertEqual(alpha(try render(event(profile.rawValue),1)),0,profile.rawValue)
            XCTAssertEqual(alpha(try render(event(profile.rawValue),0)),0,profile.rawValue)
        }
        XCTAssertEqual(alpha(try render(event("rest"),0.5)),0,"Empty-original previews must not silently acquire an invented imported effect")
        var charged=event("psychic");charged.phase="charge"
        XCTAssertNil(PokeRogueReadabilityProfile.resolve(charged))
    }
    func testDirectionCasterScopeAndReducedMotionStayBoundToCorrectPokemon() throws {
        let own=CGRect(x:45,y:177,width:128,height:128),foe=CGRect(x:405,y:25,width:128,height:128)
        XCTAssertGreaterThan(alpha(try render(event("psychic",own:false),0.68),in:own),100)
        let caster=try render(event("meditate"),0.5)
        XCTAssertGreaterThan(alpha(caster,in:own),50)
        XCTAssertEqual(alpha(caster,in:foe),0)
        XCTAssertEqual(try render(event("psychic"),0.25,reduced:true).tiffRepresentation,
                       try render(event("psychic"),0.75,reduced:true).tiffRepresentation)
        let split=try render(event("powersplit"),0.5)
        XCTAssertGreaterThan(alpha(split,in:own),5)
        XCTAssertGreaterThan(alpha(split,in:foe),5)
    }
}
