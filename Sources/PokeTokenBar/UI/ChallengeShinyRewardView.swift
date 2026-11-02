import SwiftUI

@MainActor struct ChallengeShinyRewardView:View {
    let model:ChallengeUIModel
    let onClose:()->Void
    private var l:L {model.store.l}
    private var applied:Bool {model.run.flatMap{model.store.state.challengeShinyClaims?[$0.id]} != nil}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            Label(l.challengeShinyReward,systemImage:"sparkles").font(.title2.bold())
            Text(l.challengeShinyHint).font(.callout).foregroundStyle(.secondary)
            Divider()
            if applied {
                Label(l.challengeRewardDone,systemImage:"checkmark.seal.fill").foregroundStyle(.green)
                Spacer()
            } else if model.store.championShinyTargets.isEmpty {
                Text(l.challengeShinyEmpty).foregroundStyle(.secondary)
                Spacer()
            } else {
                HStack(alignment:.top,spacing:16) {
                    ScrollView {
                        LazyVStack(spacing:8) {
                            ForEach(model.store.championShinyTargets){entry in
                                Button{model.shinyRewardSelection=entry.id}label:{
                                    HStack(spacing:9) {
                                        Image(systemName:model.shinyRewardSelection==entry.id ? "checkmark.circle.fill":"circle")
                                        SpriteView(speciesID:entry.finalID,size:42,form:entry.form).frame(width:46,height:48)
                                        VStack(alignment:.leading,spacing:4) {
                                            Text(BattleTextCatalog.shared.speciesName(entry.finalID,language:model.store.language))
                                            if let profile=entry.profile{Text("\(l.level) \(profile.level)").font(.caption).foregroundStyle(.secondary)}
                                        }
                                        Spacer(minLength:0)
                                        if entry.championAchievedAt != nil{ChallengeChampionBadge(label:l.challengeChampion)}
                                    }.padding(8).contentShape(Rectangle())
                                        .background(model.shinyRewardSelection==entry.id ? Color.accentColor.opacity(0.16):Color.secondary.opacity(0.06),in:RoundedRectangle(cornerRadius:8))
                                }.buttonStyle(.plain).accessibilityIdentifier("challenge-shiny-target-\(entry.id)")
                            }
                        }
                    }
                    if let entry=model.store.state.dex.first(where:{$0.id==model.shinyRewardSelection}) {
                        VStack(spacing:12) {
                            Text("✨").font(.title)
                            SpriteView(speciesID:entry.finalID,size:120,shiny:true,form:entry.form).frame(height:140)
                            Text(BattleTextCatalog.shared.speciesName(entry.finalID,language:model.store.language)).font(.headline)
                        }.frame(width:180).padding(.top,20).accessibilityIdentifier("challenge-shiny-preview")
                    }
                }
            }
            Divider()
            HStack {
                Button(l.challengeShinyLater,action:onClose).accessibilityIdentifier("challenge-shiny-later")
                Spacer()
                Button(applied ? l.challengeClose:l.challengeShinyApply){if model.claimChampionShiny(){onClose()}}
                    .buttonStyle(.borderedProminent).disabled(!model.canClaimChampionShiny)
                    .accessibilityIdentifier("challenge-shiny-claim")
            }
        }.padding(20).onAppear{model.configureChampionReward()}
    }
}
