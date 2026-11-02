import SwiftUI

@MainActor struct ChallengeShopView:View {
    let model:ChallengeUIModel
    @State private var selected:ChallengeShopItem?
    private var l:L {model.store.l}
    var body:some View {
        VStack(alignment:.leading,spacing:10) {
            HStack {
                Label(l.challengeShop,systemImage:"bag.fill").font(.headline)
                Spacer()
                Text(l.challengePoints(model.shopBalance)).font(.headline.monospacedDigit()).foregroundStyle(.orange)
                    .accessibilityIdentifier("challenge-shop-points")
            }
            Text(l.challengeShopHint).font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) {
                ForEach(model.run?.shopOffers ?? []){item in
                    Button{selected=item}label:{
                        HStack(spacing:10) {
                            Image(systemName:(item == .ppRecovery || item == .ppMoveRecovery) ? "bolt.circle.fill":"heart.circle.fill").font(.title2).foregroundStyle((item == .ppRecovery || item == .ppMoveRecovery) ? Color.blue:Color.pink)
                            VStack(alignment:.leading,spacing:5) {
                                Text(l.challengeShopName(item)).font(.callout.bold())
                                Text(l.challengePoints(model.shopPrice(item))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            Spacer(minLength:0)
                        }.padding(12).frame(maxWidth:.infinity,minHeight:48,alignment:.leading)
                            .background(Color.secondary.opacity(0.08),in:RoundedRectangle(cornerRadius:10))
                            .contentShape(RoundedRectangle(cornerRadius:10))
                    }.buttonStyle(.plain).disabled(model.building || model.shopBalance<model.shopPrice(item))
                        .help(l.challengeShopDescription(item)).accessibilityIdentifier("challenge-shop-\(item.rawValue)")
                }
            }
        }.sheet(item:$selected){item in ChallengeShopPurchaseView(model:model,item:item,onClose:{selected=nil})}
    }
}

@MainActor struct ChallengeShopPurchaseView:View {
    let model:ChallengeUIModel
    let item:ChallengeShopItem
    let onClose:()->Void
    @State private var targetID=""
    @State private var moveIndex:Int?
    private var l:L {model.store.l}
    var body:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack{Text(l.challengeShopName(item)).font(.title2.bold());Spacer();Text(l.challengePoints(model.shopBalance)).monospacedDigit()}
            Text(l.challengeShopDescription(item)).font(.callout).foregroundStyle(.secondary)
            if model.problem{Text(l.challengeProblem).font(.caption).foregroundStyle(.red)}
            Text(item.teamWide ? l.challengeShopName(item):l.challengeShopTarget).font(.headline)
            ScrollView {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible()),count:3),spacing:8) {
                    ForEach(model.run?.team ?? []){pokemon in target(pokemon)}
                }
            }
            if item == .ppMoveRecovery,let resource=model.run?.resources.first(where:{$0.id==targetID}) {
                Picker(l.challengeShopName(item),selection:$moveIndex) {
                    ForEach(Array(resource.moves.enumerated()),id:\.offset){index,move in
                        Text("\(BattleTextCatalog.shared.moveName(move.id,language:model.store.language)) · PP \(move.pp)/\(move.maxPP)")
                            .tag(Optional(index)).disabled(move.pp==move.maxPP)
                    }
                }.pickerStyle(.radioGroup).accessibilityIdentifier("challenge-shop-move")
            }
            Divider()
            HStack {
                Button(l.cancel,action:onClose)
                Spacer()
                Button(l.challengeShopBuy(model.shopPrice(item))) {
                    if model.purchase(item,targetID:item.teamWide ? "":targetID,moveIndex:moveIndex){onClose()}
                }.buttonStyle(.borderedProminent).disabled((item == .ppMoveRecovery && moveIndex==nil) || !model.canPurchase(item,targetID:item.teamWide ? "":targetID,moveIndex:moveIndex))
                    .accessibilityIdentifier("challenge-shop-buy")
            }
        }.padding(20).frame(width:560,height:item == .ppMoveRecovery ? 580:490)
             .onAppear{targetID=model.run?.team.first{model.canPurchase(item,targetID:$0.id)}?.id ?? "";selectMove()}
            .onChange(of:targetID){_,_ in selectMove()}
    }
    private func selectMove() {
        moveIndex=model.run?.resources.first{$0.id==targetID}?.moves.firstIndex{$0.pp<$0.maxPP}
    }
    private func target(_ pokemon:BattlePokemon)->some View {
        let r=model.run?.resources.first{$0.id==pokemon.id}
        return Button{targetID=pokemon.id}label:{
            VStack(spacing:5) {
                HStack{Image(systemName:(item.teamWide || targetID==pokemon.id) ? "checkmark.circle.fill":"circle");Spacer()}
                SpriteView(speciesID:pokemon.speciesID,size:50,shiny:pokemon.shiny,form:pokemon.form).frame(height:54)
                Text(BattleTextCatalog.shared.speciesName(pokemon.speciesID,language:model.store.language)).font(.caption)
                Text("HP \(r?.hp ?? 0)/\(pokemon.stats["hp"] ?? 0)").font(.caption.monospacedDigit())
                if let r {
                    Text("PP \(r.moves.reduce(0){$0+$1.pp})/\(r.moves.reduce(0){$0+$1.maxPP})").font(.caption2.monospacedDigit())
                    if !r.status.isEmpty{Text(l.battleStatus(r.status)).font(.caption2).foregroundStyle(.secondary)}
                }
            }.padding(8).frame(maxWidth:.infinity,minHeight:150)
                .background((item.teamWide || targetID==pokemon.id) ? Color.accentColor.opacity(0.15):Color.secondary.opacity(0.07),in:RoundedRectangle(cornerRadius:9))
        }.buttonStyle(.plain).disabled(item.teamWide || !model.canPurchase(item,targetID:pokemon.id))
            .accessibilityIdentifier("challenge-shop-target-\(pokemon.id)")
    }
}
