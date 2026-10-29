import AppKit
import SwiftUI
import XCTest
@testable import PokeTokenBar

@MainActor final class BattleItemLoadoutTests:XCTestCase {
    private func entry(_ id:String,_ species:Int=6,released:Bool=false)->DexEntry {
        DexEntry(id:id,baseID:species,finalID:species,chainOrder:[species],rarity:.common,caughtAt:Date(),releasedAt:released ? Date():nil)
    }
    private func storage() throws->UserDefaults {
        let name="BattleItemLoadoutTests.\(UUID().uuidString)"
        let defaults=try XCTUnwrap(UserDefaults(suiteName:name))
        addTeardownBlock{defaults.removePersistentDomain(forName:name)}
        return defaults
    }
    func testSixMemberAssignmentsRejectDuplicatesAndFreeItemsOnRemoval() {
        var draft=BattleItemLoadout();let roster=(0..<6).map{String($0)}
        XCTAssertTrue(draft.apply("charizarditex",to:entry("0"),roster:roster))
        XCTAssertFalse(draft.apply("charizarditex",to:entry("5"),roster:roster),"Reserve six must also obey the clause")
        XCTAssertEqual(draft.owner(of:"charizarditex"),"0")
        XCTAssertNil(draft.owner(of:"charizarditex",excluding:"0"));XCTAssertNil(draft.owner(of:""))
        XCTAssertFalse(draft.apply("blastoisinite",to:entry("1"),roster:roster))
        XCTAssertFalse(draft.apply("fairyfeather",to:entry("1"),roster:roster))
        XCTAssertFalse(draft.apply("lifeorb",to:entry("missing"),roster:roster))
        XCTAssertFalse(draft.apply("lifeorb",to:entry("1",released:true),roster:roster))
        XCTAssertTrue(draft.apply("charizarditey",to:entry("1"),roster:roster))
        XCTAssertTrue(draft.apply("",to:entry("0"),roster:roster));XCTAssertNil(draft.items["0"])
        XCTAssertTrue(draft.apply("charizarditex",to:entry("5"),roster:roster))
        draft.retain(Array(roster.prefix(5)));XCTAssertNil(draft.items["5"])
        XCTAssertTrue(draft.apply("charizarditex",to:entry("0"),roster:roster))
        XCTAssertTrue(draft.apply("leftovers",to:entry("0"),roster:roster))
        XCTAssertNil(draft.owner(of:"charizarditex"))
        XCTAssertTrue(BattleItemLoadout().items.isEmpty,"An uninitialized draft waits for roster defaults")
    }
    func testPerIndividualLastItemPersistsAndFirstAppearanceUsesNone() throws {
        let defaults=try storage(),memory=BattlePokemonItemStore(defaults:defaults)
        let first=entry("first"),second=entry("another-owned-charizard")
        var draft=BattleItemLoadout()
        draft.restore(roster:[first,second],remembered:memory.items)
        XCTAssertTrue(draft.items.isEmpty)
        memory.recordApplied("charizarditex",to:first)
        let restored=BattlePokemonItemStore(defaults:defaults)
        draft.restore(roster:[first,second],remembered:restored.items)
        XCTAssertEqual(draft.items,[first.id:"charizarditex"])
        XCTAssertNil(restored.items[second.id],"Remember the owned individual, not its species")
        restored.recordApplied("",to:first)
        draft.restore(roster:[first],remembered:BattlePokemonItemStore(defaults:defaults).items)
        XCTAssertTrue(draft.items.isEmpty,"Explicit None replaces the previous item")
    }
    func testCollectionDefaultsPrecedeMemoryAndManualSelectionOverridesThisMatch() {
        var a=entry("a"),b=entry("b",9),c=entry("c",3)
        a.battleDefaultItem="lifeorb";b.battleDefaultItem="lifeorb"
        c.battleDefaultItem="charizarditex" // An imported incompatible preference falls back safely.
        let memory=["a":"leftovers","b":"sitrusberry","c":"lumberry"]
        var draft=BattleItemLoadout()
        draft.restore(roster:[a,b,c],remembered:memory)
        XCTAssertEqual(draft.items,["a":"lifeorb","c":"lumberry"])
        draft.restore(roster:[b,a,c],remembered:memory)
        XCTAssertEqual(draft.items,["b":"lifeorb","c":"lumberry"])
        draft.restore(roster:[a,b,c],remembered:memory,overrides:["a":"leftovers","c":""])
        XCTAssertEqual(draft.items,["a":"leftovers","b":"lifeorb"],"Manual None must also override defaults")
        draft.restore(roster:[a,b,c],remembered:memory,useCollectionDefaults:false)
        XCTAssertEqual(draft.items,memory,"Registered teams remain frozen when collection preferences change")
        a.battleDefaultItem=nil
        draft.restore(roster:[a],remembered:memory)
        XCTAssertEqual(draft.items,["a":"leftovers"])
        draft.restore(roster:[entry("new")],remembered:memory)
        XCTAssertTrue(draft.items.isEmpty)
    }
    func testCollectionItemLegacyDecodingAndNumericStatGrades() throws {
        var pokemon=entry("a");pokemon.battleDefaultItem="charizarditex"
        let data=try JSONEncoder().encode(pokemon)
        XCTAssertEqual(try JSONDecoder().decode(DexEntry.self,from:data).battleDefaultItem,"charizarditex")
        var json=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        json.removeValue(forKey:"battleDefaultItem")
        XCTAssertNil(try JSONDecoder().decode(DexEntry.self,from:JSONSerialization.data(withJSONObject:json)).battleDefaultItem)
        json["battleDefaultItem"]=["invalid":true]
        XCTAssertEqual(try JSONDecoder().decode(DexEntry.self,from:JSONSerialization.data(withJSONObject:json)).id,"a")
        let grades=(0...31).map{PokemonStatGrade.rank(iv:$0)}
        XCTAssertEqual(Set(grades),Set(1...32))
        XCTAssertEqual(grades,grades.sorted())
        XCTAssertEqual(PokemonStatGrade.label(iv:0),"★(1)")
        XCTAssertEqual(PokemonStatGrade.label(iv:31),"★(32)")
        XCTAssertEqual(PokemonStatGrade.rank(iv:-1),1)
        XCTAssertEqual(PokemonStatGrade.rank(iv:99),32)
    }
    func testSixDefaultsResolveDuplicatesInRegistrationOrderAndNeverErasePreferences() throws {
        let defaults=try storage(),memory=BattlePokemonItemStore(defaults:defaults)
        let roster=zip(["z","a","y","b","x","c"],[6,9,3,94,143,181]).map{entry($0.0,$0.1)}
        for (pokemon,item) in zip(roster,["lifeorb","lifeorb","leftovers","leftovers","sitrusberry",""]) {
            memory.recordApplied(item,to:pokemon)
        }
        let original=memory.items
        var draft=BattleItemLoadout()
        draft.restore(roster:roster,remembered:memory.items)
        XCTAssertEqual(draft.items,["z":"lifeorb","y":"leftovers","x":"sitrusberry"])
        draft.restore(roster:roster.reversed(),remembered:memory.items)
        XCTAssertEqual(draft.items,["a":"lifeorb","b":"leftovers","x":"sitrusberry"])
        draft.restore(roster:Array(roster.dropFirst()),remembered:memory.items)
        XCTAssertEqual(draft.items["a"],"lifeorb","Removing the first holder frees the remembered item")
        XCTAssertEqual(BattlePokemonItemStore(defaults:defaults).items,original)
        memory.recordApplied("",to:roster[0])
        draft.restore(roster:roster,remembered:memory.items)
        XCTAssertNil(draft.items["z"]);XCTAssertEqual(draft.items["a"],"lifeorb")
    }
    func testRecentApplicationsPersistAndUnusedItemsSortByLocalizedName() throws {
        let defaults=try storage(),usage=BattleItemUsageStore(defaults:defaults)
        let items=BattleHeldItems.choices(speciesID:6,form:nil)
        for language in AppLanguage.allCases {
            let sorted=usage.sorted(items,language:language)
            for (a,b) in zip(sorted,sorted.dropFirst()) {
                XCTAssertNotEqual(a.name(language).compare(b.name(language),options:[.caseInsensitive,.diacriticInsensitive,.numeric],range:nil,locale:language.displayLocale),.orderedDescending)
            }
        }
        usage.recordApplied("");usage.recordApplied("invalid");XCTAssertNil(usage.usage(""))
        usage.recordApplied("lifeorb");usage.recordApplied("lifeorb");usage.recordApplied("leftovers")
        XCTAssertEqual(usage.sorted(items,language:.ko).prefix(2).map(\.id),["leftovers","lifeorb"],"Recency takes priority over frequency")
        let restored=BattleItemUsageStore(defaults:defaults)
        XCTAssertEqual(restored.usage("lifeorb")?.count,2)
        XCTAssertEqual(restored.sorted(items,language:.en).prefix(2).map(\.id),["leftovers","lifeorb"])
        restored.recordApplied("lifeorb");XCTAssertEqual(restored.usage("lifeorb")?.count,3)
        XCTAssertEqual(restored.sorted(items,language:.en).first?.id,"lifeorb")
        defaults.set(Data("invalid".utf8),forKey:"battleHeldItemUsage.v1")
        XCTAssertNil(BattleItemUsageStore(defaults:defaults).usage("lifeorb"))
    }
    func testNativeRowPreviewDoesNotAssignOrRecordUntilApplied() async throws {
        _ = NSApplication.shared
        let usage=BattleItemUsageStore(defaults:try storage()),pokemon=entry("0")
        var draft=BattleItemLoadout(),preview=""
        let choices=BattleHeldItems.choices(speciesID:6,form:nil).map{PokemonLoadoutChoice(id:$0.id,title:$0.name(.ko),tooltip:$0.tooltip(.ko))}
        let host=NSHostingController(rootView:BattleItemList(choices:choices,selectedID:"",onSelect:{preview=$0}).frame(width:252,height:286))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:252,height:286),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{window.orderOut(nil);window.contentViewController=nil}
        func table(_ view:NSView)->NSTableView? {if let t=view as? NSTableView{return t};return view.subviews.compactMap{table($0)}.first}
        var native:NSTableView?
        let deadline=Date().addingTimeInterval(3)
        while native==nil,Date()<deadline {native=table(host.view);try await Task.sleep(for:.milliseconds(20))}
        let list=try XCTUnwrap(native),row=try XCTUnwrap(choices.firstIndex{$0.id=="charizarditex"})
        list.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)
        XCTAssertEqual(preview,"charizarditex");XCTAssertTrue(draft.items.isEmpty);XCTAssertNil(usage.usage(preview))
        XCTAssertTrue(draft.apply(preview,to:pokemon,roster:["0","1"]))
        usage.recordApplied(preview)
        XCTAssertEqual(draft.items["0"],preview);XCTAssertEqual(usage.usage(preview)?.count,1)
        let another=try XCTUnwrap(choices.firstIndex{$0.id=="leftovers"})
        list.selectRowIndexes(IndexSet(integer:another),byExtendingSelection:false)
        XCTAssertEqual(preview,"leftovers");XCTAssertEqual(draft.items["0"],"charizarditex")
        XCTAssertNil(usage.usage(preview),"Preview/cancel must not record usage")
        XCTAssertFalse(draft.apply("charizarditex",to:entry("1"),roster:["0","1"]))
        XCTAssertEqual(usage.usage("charizarditex")?.count,1)
    }
    func testNativeItemNamesAreVerticallyCenteredWithinRows() throws {
        _ = NSApplication.shared
        let coordinator=BattleItemList.Coordinator{_ in}
        coordinator.choices=[.init(id:"toxicorb",title:"맹독구슬",tooltip:"설명")]
        let table=NSTableView()
        for height in [CGFloat(29),CGFloat(35)] {
            let cell=try XCTUnwrap(coordinator.tableView(table,viewFor:nil,row:0) as? NSTableCellView)
            cell.frame=NSRect(x:0,y:0,width:252,height:height);cell.layoutSubtreeIfNeeded()
            let text=try XCTUnwrap(cell.textField)
            XCTAssertEqual(text.stringValue,"맹독구슬")
            XCTAssertEqual(text.frame.midY,cell.bounds.midY,accuracy:0.5)
            XCTAssertGreaterThan(text.frame.minY,0)
            XCTAssertLessThan(text.frame.maxY,cell.bounds.maxY)
        }
    }
    func testCategoriesPartitionCatalogAndKeepSpeciesBindingAndRecentOrder() throws {
        XCTAssertEqual(BattleItemCategory.allCases.map{$0.title(.ko)},["전체","메가스톤","회복","공격강화","타입강화","생존","행동순서","열매"])
        let counts:[BattleItemCategory:Int]=[.all:100,.mega:64,.recovery:3,.power:6,.type:17,.defense:5,.order:3,.berries:2]
        for group in BattleItemCategory.allCases {
            XCTAssertEqual(BattleHeldItems.all.filter{group.includes($0)}.count,counts[group])
            for language in AppLanguage.allCases {XCTAssertFalse(group.title(language).isEmpty)}
        }
        for item in BattleHeldItems.all {
            XCTAssertEqual(BattleItemCategory.allCases.filter{$0 != .all && $0.includes(item)}.count,1,item.id)
        }
        let compatible=BattleHeldItems.choices(speciesID:6,form:nil)
        XCTAssertEqual(Set(compatible.filter{BattleItemCategory.mega.includes($0)}.map(\.id)),["charizarditex","charizarditey"])
        XCTAssertTrue(BattleHeldItems.choices(speciesID:25,form:nil).filter{BattleItemCategory.mega.includes($0)}.isEmpty)
        let usage=BattleItemUsageStore(defaults:try storage())
        usage.recordApplied("lifeorb");usage.recordApplied("wiseglasses")
        let filtered=usage.sorted(compatible.filter{BattleItemCategory.power.includes($0)},language:.ko)
        XCTAssertEqual(filtered.prefix(2).map(\.id),["wiseglasses","lifeorb"])
        XCTAssertEqual(filtered.count,6)
    }
    func testPickerFitsOffscreenAndAllDescriptionsAreLocalized() async throws {
        let usage=BattleItemUsageStore(defaults:try storage())
        for language in AppLanguage.allCases {
            for item in BattleHeldItems.all {XCTAssertFalse(item.descriptions[language.rawValue]?.isEmpty ?? true)}
        }
        let host=NSHostingController(rootView:BattleItemPicker(pokemon:entry("0"),current:"charizarditex",assignments:["0":"charizarditex"],language:.ko,usage:usage,onApply:{_ in XCTFail("Rendering must not apply");return false},onCancel:{}))
        let window=NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:640,height:414),styleMask:[.borderless],backing:.buffered,defer:false)
        window.contentViewController=host;window.orderFront(nil)
        defer{window.orderOut(nil);window.contentViewController=nil}
        try await Task.sleep(for:.milliseconds(500));host.view.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.view.fittingSize.width,640,accuracy:1)
        XCTAssertEqual(host.view.fittingSize.height,414,accuracy:1)
        if let bitmap=host.view.bitmapImageRepForCachingDisplay(in:host.view.bounds) {
            host.view.cacheDisplay(in:host.view.bounds,to:bitmap)
            try bitmap.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:"/tmp/ptb-registration-item-picker.png"))
        } else {XCTFail("Missing offscreen image")}
    }
}
