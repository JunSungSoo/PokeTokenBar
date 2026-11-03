import AppKit
import SwiftUI
import Vision
import XCTest
@testable import PokeTokenBar

@MainActor final class ChallengeLoadoutLabelTests:XCTestCase {
    func testSameSpeciesShowsDistinctLocalizedNatureAndFourMovesBesideName()throws {
        var profile=PokemonProfile.generate(seed:1,instanceID:"first")
        profile.moves=["flamethrower","solarbeam","roost","protect"].map{.init(name:$0,learnedAtLevel:1)}
        let first=DexEntry(id:"first",baseID:4,finalID:6,chainOrder:[4,5,6],rarity:.common,caughtAt:Date(),nature:.adamant,profile:profile)
        profile.moves=["airslash","dragonpulse","focusblast","fireblast"].map{.init(name:$0,learnedAtLevel:1)}
        let second=DexEntry(id:"second",baseID:4,finalID:6,chainOrder:[4,5,6],rarity:.common,caughtAt:Date(),nature:.timid,profile:profile)
        for language in AppLanguage.allCases {
            let content=VStack(spacing:20){
                ChallengePokemonLoadoutLabel(entry:first,language:language)
                ChallengePokemonLoadoutLabel(entry:second,language:language)
            }.padding(16).frame(width:600,height:160).background(Color(nsColor:.windowBackgroundColor))
            let renderer=ImageRenderer(content:content);renderer.scale=2
            let image=try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width,1200);XCTAssertEqual(image.height,320)
            if language == .ko {
                let bitmap=NSBitmapImageRep(cgImage:image)
                try XCTUnwrap(bitmap.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/tmp/ptb-challenge-loadout-labels.png"))
                let request=VNRecognizeTextRequest();request.recognitionLevel = .accurate;request.recognitionLanguages=["ko-KR","en-US"]
                try VNImageRequestHandler(cgImage:image,options:[:]).perform([request])
                let text=(request.results ?? []).compactMap{$0.topCandidates(1).first?.string}.joined().replacingOccurrences(of:" ",with:"")
                for expected in ["리자몽","고집","겁쟁이","화염방사","솔라빔","날개쉬기","방어","에어슬래시","용의파동","기합구슬","불대문자"] {
                    XCTAssertTrue(text.contains(expected),"Missing \(expected): \(text)")
                }
            }
        }
    }
}
