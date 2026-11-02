import Foundation
import SwiftUI

/// Snapshot the real collection once. A running older production app must not overwrite QA awards.
@MainActor enum ChallengeTestData {
    static func snapshot(source:URL=CompanionStore.defaultURL(),destination:URL?=nil)throws->URL {
        let target=destination ?? source.deletingLastPathComponent().appendingPathComponent("challenge-test-companion-v1.json")
        guard !FileManager.default.fileExists(atPath:target.path) else{return target}
        let data=FileManager.default.fileExists(atPath:source.path) ? try Data(contentsOf:source):try JSONEncoder().encode(CompanionState())
        try data.write(to:target,options:.atomic);return target
    }
}

@MainActor struct ChallengeTestRootView:View {
    let store:CompanionStore
    let battle:BattleCoordinator
    @State private var collection=false
    @State private var navigation=PopoverNavigation()
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            Text(store.l.challengeTestData).font(.caption).foregroundStyle(.secondary)
            Picker("",selection:$collection){
                Text(store.l.battle).tag(false)
                Text(store.l.collection).tag(true)
            }.pickerStyle(.segmented)
            if collection {CollectionView(store:store,navigation:navigation)}
            else{BattleTabView(store:store,battle:battle,tradeActive:false)}
            Spacer(minLength:0)
        }.padding(16).background(Color(nsColor:.windowBackgroundColor))
    }
}
