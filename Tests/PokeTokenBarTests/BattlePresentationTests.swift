import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor
final class BattlePresentationTests: XCTestCase {
    private var move: BattleMove {
        BattleMove(index:1,name:"Thunderbolt",apiName:"thunderbolt",pp:14,maxPP:15,disabled:false,type:"Electric",
            power:95,category:"Special",description:nil,matchups:[],targetRequired:false,targets:[])
    }
    func testBaseAccuracyRoundTripsAndChangesBattleDetailsInEveryLanguage() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        XCTAssertEqual(try decoder.decode(BattleMoveAccuracy.self, from: Data("85".utf8)), .percent(85))
        XCTAssertEqual(try decoder.decode(BattleMoveAccuracy.self, from: Data("true".utf8)), .always)
        for language in AppLanguage.allCases {
            let l = L(language)
            var images = [Data]()
            for accuracy in [BattleMoveAccuracy.percent(100), .percent(70), .always] {
                var sample = move
                sample.accuracy = accuracy
                XCTAssertEqual(try decoder.decode(BattleMove.self, from: encoder.encode(sample)).accuracy, accuracy)
                let image = try XCTUnwrap(ImageRenderer(content: BattleMoveDetails(move: sample, language: language, compact: true).frame(width: 340)).nsImage)
                XCTAssertLessThanOrEqual(image.size.height, 290)
                images.append(try XCTUnwrap(image.tiffRepresentation))
            }
            XCTAssertNotEqual(images[0], images[1], "Numeric accuracy must appear in production details: \(language)")
            XCTAssertNotEqual(images[0], images[2], "Always-hit moves must not display 100%: \(language)")
            XCTAssertEqual(l.battleAccuracy(.percent(70)), "70%")
            XCTAssertNotEqual(l.battleAccuracy(.always), "100%")
            XCTAssertEqual(l.battleAccuracy(nil), "—")
        }
    }
    func testCompactMoveDetailsFitWithLongDescriptionsInEveryLanguage() throws {
        for language in AppLanguage.allCases {
            for name in ["substitute", "fire-pledge", "thunderbolt"] {
                let move = BattleMove(index: 1, name: name, apiName: name, pp: 10, maxPP: 10, disabled: false, type: "Normal", power: 0, category: "Status", description: nil, matchups: [], targetRequired: false, targets: [])
                let renderer = ImageRenderer(content: BattleMoveDetails(move: move, language: language, compact: true).frame(width: 340))
                let image = try XCTUnwrap(renderer.cgImage)
                XCTAssertLessThanOrEqual(image.height, 290, "Long descriptions must not push controls out of the window: \(language) \(name)")
                XCTAssertFalse(L(language).battleFullDescription.isEmpty)
                XCTAssertFalse(L(language).battleFieldWindow.isEmpty)
                XCTAssertFalse(L(language).battleStatsWindow.isEmpty)
                XCTAssertFalse(L(language).battleNoFieldEffects.isEmpty)
            }
        }
    }
    private func event(_ id: Int,type: String = "Electric",category: String = "Special",hit: Bool = true) -> BattleVisualEvent {
        BattleVisualEvent(id:id,move:type == "Water" ? "Water Gun" : "Thunderbolt",type:type,category:category,source:BattleEffectPosition(own:true,slot:0),
            targets:[BattleEffectTarget(position:BattleEffectPosition(own:false,slot:0),hit:hit)])
    }
    func testMoveAndAbilityNoticesUseEngineOrderAndLocalizedTextWithoutChangingLayout() throws {
        let log = ["|-ability|p1a: Gyarados|Intimidate|boost", "|-unboost|p2a: Raichu|atk|1", "|move|p1a: Gyarados|Thunderbolt|p2a: Raichu", "|-status|p1a: Gyarados|par|[from] ability: Static", "|move|p2a: Raichu|Tackle|p1a: Gyarados"]
        let frame = BattleFrame(revision: "test", turn: 2, decisionID: "2", preview: false, waiting: false, own: [], foe: [], slots: [], log: log,
            effects: [event(1002), event(1004)], logOffset: 1000, ended: false, winner: nil)
        for language in AppLanguage.allCases {
            let presentation = BattlePresentationEvents(frame: frame, language: language, ownPlayer: 0)
            XCTAssertEqual(presentation.events.map(\.id), [1000,1001,1002,1003,1004])
            XCTAssertEqual(presentation.events.map { $0.phase == "ability" }, [true,true,false,true,false])
            XCTAssertTrue(try XCTUnwrap(presentation.messages[1001]).contains(L(language).battleStat("atk")))
            XCTAssertTrue(try XCTUnwrap(presentation.messages[1002]).contains(BattleTextCatalog.shared.moveName("thunderbolt",language:language)))
            XCTAssertTrue(try XCTUnwrap(presentation.messages[1003]).contains(BattleTextCatalog.shared.abilityName("static",language:language)))
            for text in presentation.messages.values {
                let image = try XCTUnwrap(ImageRenderer(content: BattleEventNotice(text: text).frame(width: 640)).cgImage)
                XCTAssertLessThan(image.height, 110)
            }
        }
        let reflected = BattleFrame(revision:"test",turn:2,decisionID:"2",preview:false,waiting:false,own:[],foe:[],slots:[],
            log:["|-activate|p2a: Espeon|ability: Magic Bounce", "|move|p1a: Pikachu|Thunder Wave|p2a: Espeon|[from] ability: Magic Bounce"],
            effects:[event(1)],logOffset:0,ended:false,winner:nil)
        let reflection = BattlePresentationEvents(frame:reflected,language:.en,ownPlayer:0)
        XCTAssertEqual(reflection.events.map(\.id),[0,1],"A reflected move's ability annotation must not duplicate its move event")
        for reduced in [false,true] { XCTAssertGreaterThanOrEqual(BattleEffectsLayer.presentationDuration(event(1),reducedMotion:reduced), 1.4) }
    }
    func testMountedAbilityNoticeAppearsTemporarilyThenClears() async throws {
        let notice = BattleVisualEvent(id:1,move:"Static",type:"",category:"Status",source:BattleEffectPosition(own:true,slot:0),targets:[],phase:"ability")
        let probe = PlaybackProbe()
        let host = NSHostingController(rootView:EffectPlaybackFixture(events:[notice],probe:probe))
        let window = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        func whitePixels() throws -> Int {
            host.view.layoutSubtreeIfNeeded()
            let bitmap=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
            var count=0
            for y in Int(Double(bitmap.pixelsHigh)*0.35)..<Int(Double(bitmap.pixelsHigh)*0.65) {
                for x in Int(Double(bitmap.pixelsWide)*0.2)..<Int(Double(bitmap.pixelsWide)*0.8) {
                    if let color=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), min(color.redComponent,color.greenComponent,color.blueComponent)>0.6 { count += 1 }
                }
            }
            return count
        }
        let until=Date().addingTimeInterval(1)
        while probe.started == nil && Date()<until { try await Task.sleep(for:.milliseconds(20)) }
        try await Task.sleep(for:.milliseconds(200))
        XCTAssertGreaterThan(try whitePixels(),10,"The actual mounted ability-only event must draw its announcement")
        let end=Date().addingTimeInterval(3)
        while probe.finished == nil && Date()<end { try await Task.sleep(for:.milliseconds(30)) }
        XCTAssertNotNil(probe.finished)
        XCTAssertEqual(try whitePixels(),0,"Announcements must disappear rather than accumulate")
    }
    func testMoveSelectionKeepsIdenticalSizeInEveryLanguageAndBothGridWidths() throws {
        for language in AppLanguage.allCases {
            for width: CGFloat in [140,220] {
                var images=[CGImage]()
                for selected in [false,true] {
                    let renderer=ImageRenderer(content:BattleMoveButtonLabel(move:move,language:language,selected:selected)
                        .frame(width:width).background(Color(red:0.12,green:0.12,blue:0.12)).environment(\.colorScheme,.dark))
                    renderer.scale=2
                    images.append(try XCTUnwrap(renderer.cgImage))
                }
                XCTAssertEqual(images[0].width,images[1].width)
                XCTAssertEqual(images[0].height,images[1].height)
                XCTAssertEqual(images[0].height,128,"Selection must not add a text row or increase the 64-point button")
                let before=try XCTUnwrap(NSBitmapImageRep(cgImage:images[0]).representation(using:.png,properties:[:]))
                let after=try XCTUnwrap(NSBitmapImageRep(cgImage:images[1]).representation(using:.png,properties:[:]))
                XCTAssertNotEqual(before,after,"Selection must still change the background/check pixels")
                if language == .ko && width == 220 {
                    try before.write(to:URL(fileURLWithPath:"/private/tmp/ptb-move-unselected.png"))
                    try after.write(to:URL(fileURLWithPath:"/private/tmp/ptb-move-selected.png"))
                }
            }
        }
    }
    func testEffectCursorQueuesBothMovesOnceAndDoesNotReplayOnReconnect() {
        let first=event(10),second=event(18),third=event(27)
        var cursor=BattleEffectCursor(events:[])
        XCTAssertEqual(cursor.takeNew([first,second]),[first,second])
        XCTAssertEqual(cursor.takeNew([first,second]),[])
        XCTAssertEqual(cursor.takeNew([first,second,third]),[third])
        var reopened=BattleEffectCursor(events:[first,second,third])
        XCTAssertEqual(reopened.takeNew([first,second,third]),[])
        XCTAssertEqual(reopened.takeNew([first,second,third,event(35)]),[event(35)])
    }
    func testMountedEffectLayerStartsFromEmptyAndPlaysBothNewMoves() async throws {
        let probe=PlaybackProbe()
        let ability = BattleVisualEvent(id:14,move:"Static",type:"",category:"Status",source:BattleEffectPosition(own:true,slot:0),targets:[],phase:"ability")
        let events=[event(10),ability,event(18)]
        let host=NSHostingController(rootView:EffectPlaybackFixture(events:events,probe:probe))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.setContentSize(NSSize(width:640,height:300));window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        var sawPixels=false
        let expectedDuration=events.reduce(0.0) { $0 + BattleEffectsLayer.presentationDuration($1) }
        let end=Date().addingTimeInterval(expectedDuration+1)
        while Date() < end && probe.finished == nil {
            try await Task.sleep(for:.milliseconds(60))
            guard probe.started != nil && !sawPixels else { continue }
            host.view.layoutSubtreeIfNeeded()
            let bitmap=try XCTUnwrap(host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds))
            host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
            for y in stride(from:0,to:bitmap.pixelsHigh,by:12) { for x in stride(from:0,to:bitmap.pixelsWide,by:12) {
                if let c=bitmap.colorAt(x:x,y:y)?.usingColorSpace(.deviceRGB), max(c.redComponent,c.greenComponent,c.blueComponent)>0.25 {
                    sawPixels=true
                }
            } }
        }
        XCTAssertNotNil(probe.started,"An initially empty layer must still mount its playback task")
        XCTAssertNotNil(probe.finished)
        XCTAssertTrue(sawPixels,"The live TimelineView must actually render particles")
        if let start=probe.started, let finish=probe.finished {
            XCTAssertGreaterThan(finish.timeIntervalSince(start),expectedDuration-0.25,"Both complete move timelines must play, not just the last move")
        }
    }
    func testNewFramesAppendWithoutInterruptingCurrentMoveAndKeepFullPacedOrder() async throws {
        let probe=PlaybackProbe(),events=[event(10),event(18,type:"Water"),event(27)]
        let host=NSHostingController(rootView:EffectPlaybackFixture(events:events,probe:probe,appendDuringPlayback:true))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        let end=Date().addingTimeInterval(events.reduce(0.0) { $0 + BattleEffectsLayer.presentationDuration($1) } + 2)
        while probe.finished == nil && Date()<end { try await Task.sleep(for:.milliseconds(40)) }
        XCTAssertNotNil(probe.finished)
        XCTAssertEqual(probe.played.map(\.id),events.map(\.id),"A later frame must append, not cancel and lose already queued moves")
        XCTAssertEqual(probe.busyTransitions,[true,false],"Input stays gated for the entire sequence, including pauses")
        if probe.played.count == events.count {
            for i in 1..<events.count {
                let previous=events[i-1]
                let minimum=BattleEffectPlayback.animationDuration(previous)+BattleEffectPlayback.interEventPause+BattleEffectPlayback.announcementLeadIn
                XCTAssertGreaterThanOrEqual(probe.played[i].date.timeIntervalSince(probe.played[i-1].date),minimum-0.15)
            }
        }
        if let start=probe.started, let first=probe.played.first {
            XCTAssertGreaterThanOrEqual(first.date.timeIntervalSince(start),BattleEffectPlayback.announcementLeadIn-0.1)
        }
    }
    func testForegroundAndBackgroundShareSlowerTimelineWhileSourceDurationsStayUnchanged() {
        for name in ["thunderbolt","quickattack","psychic","surf","rest"] {
            var sample=event(1);sample.moveID=name
            let source=BattleEffectPlayback.duration(sample),duration=BattleEffectPlayback.animationDuration(sample)
            XCTAssertGreaterThanOrEqual(duration,2.2)
            XCTAssertGreaterThanOrEqual(duration,source/0.65)
            let start=Date(),playback=BattleEffectPlayback(event:sample,began:start)
            XCTAssertEqual(playback.progress(at:start.addingTimeInterval(duration/2)),0.5,accuracy:0.001)
            XCTAssertEqual(playback.progress(at:start.addingTimeInterval(duration)),1,accuracy:0.001)
        }
    }
    func testReducedMotionStillAnnouncesAndHoldsEachMoveBeforeFinishing() async throws {
        let probe=PlaybackProbe(),sample=event(10)
        let host=NSHostingController(rootView:EffectPlaybackFixture(events:[sample],probe:probe,reducedMotion:true))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:300),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer { window.orderOut(nil);window.contentViewController=nil }
        let end=Date().addingTimeInterval(4)
        while probe.finished == nil && Date()<end { try await Task.sleep(for:.milliseconds(40)) }
        XCTAssertEqual(probe.played.map(\.id),[sample.id])
        XCTAssertEqual(probe.busyTransitions,[true,false])
        let start=try XCTUnwrap(probe.started),finish=try XCTUnwrap(probe.finished)
        XCTAssertGreaterThanOrEqual(finish.timeIntervalSince(start),BattleEffectsLayer.presentationDuration(sample,reducedMotion:true)-0.15)
    }
    func testEffectFramesFollowTargetsDifferentiateTypesAndSuppressMissImpact() throws {
        let rects=["own-0":CGRect(x:30,y:175,width:100,height:100),"foe-0":CGRect(x:490,y:10,width:100,height:100)]
        func bitmap(_ e: BattleVisualEvent,_ p: Double) throws -> NSBitmapImageRep {
            let cg=try XCTUnwrap(ImageRenderer(content:BattleEffectCanvas(event:e,rects:rects,progress:p)
                .frame(width:640,height:300)).cgImage)
            return NSBitmapImageRep(cgImage:cg)
        }
        let electric=try bitmap(event(1),0.42),water=try bitmap(event(1,type:"Water"),0.42)
        XCTAssertNotEqual(electric.tiffRepresentation,water.tiffRepresentation)
        let impact=try bitmap(event(1),0.8),miss=try bitmap(event(1,hit:false),0.8)
        func alpha(_ rep: NSBitmapImageRep,rect: CGRect) -> Double {
            var sum=0.0
            for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) {
                sum += Double(rep.colorAt(x:x,y:y)?.alphaComponent ?? 0)
            } }
            return sum
        }
        // Canvas pixels use a top-left origin; target center is (540,60).
        let target=CGRect(x:485,y:5,width:110,height:110)
        XCTAssertGreaterThan(alpha(impact,rect:target),100)
        XCTAssertEqual(alpha(miss,rect:target),0,accuracy:0.01)
        XCTAssertEqual(alpha(try bitmap(event(1),1),rect:CGRect(x:0,y:0,width:640,height:300)),0,accuracy:0.01)
        for (name,rep) in [("electric",electric),("water",water),("impact",impact)] {
            try XCTUnwrap(rep.representation(using:.png,properties:[:])).write(to:URL(fileURLWithPath:"/private/tmp/ptb-effect-\(name).png"))
        }
    }
}

@MainActor
private final class PlaybackProbe {
    var started: Date?
    var finished: Date?
    var played: [(id: Int,date: Date)] = []
    var busyTransitions: [Bool] = []
}
@MainActor
private struct EffectPlaybackFixture: View {
    let events: [BattleVisualEvent]
    let probe: PlaybackProbe
    var appendDuringPlayback = false
    var reducedMotion = false
    @State private var shown: [BattleVisualEvent] = []
    @State private var busy = false
    @State private var playback: BattleEffectPlayback?
    var body: some View {
        ZStack {
            Color.black
            BattleEffectsLayer(events:shown,rects:["own-0":CGRect(x:30,y:175,width:100,height:100),
                "foe-0":CGRect(x:490,y:10,width:100,height:100)],busy:$busy,playback:$playback,messages:Dictionary(uniqueKeysWithValues:shown.map { ($0.id,$0.move) }),reducedMotionOverride:reducedMotion)
        }.frame(width:640,height:300)
            .onChange(of:busy) { _,value in
                probe.busyTransitions.append(value)
                if value { probe.started=Date() } else { probe.finished=Date() }
            }
            .onChange(of:playback?.event.id) { _,id in if let id { probe.played.append((id,Date())) } }
            .task {
                try? await Task.sleep(for:.milliseconds(120))
                shown=appendDuringPlayback ? Array(events.prefix(2)) : events
                if appendDuringPlayback {
                    try? await Task.sleep(for:.milliseconds(650));shown=events
                }
            }
    }
}
