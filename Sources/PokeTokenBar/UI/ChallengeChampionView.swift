import Observation
import SwiftUI

@MainActor @Observable final class ChallengeChampionPresentation {
    private(set) var index:Int?
    private(set) var opacity=0.0
    private(set) var completed=false
    var hold:Duration = .milliseconds(1500)
    var fade:Duration = .milliseconds(550)
    func play(count:Int,reducedMotion:Bool=false,onReveal:(Int)->Void={_ in})async {
        completed=false;index=nil;opacity=0
        do {
            for i in 0..<count {
                guard !Task.isCancelled else{return}
                index=i;onReveal(i)
                withAnimation(reducedMotion ? nil:.easeIn(duration:0.25)){opacity=1}
                try await Task.sleep(for:hold)
                withAnimation(reducedMotion ? nil:.easeOut(duration:0.5)){opacity=0}
                try await Task.sleep(for:fade)
            }
            guard !Task.isCancelled else{return}
            index=nil;completed=true
        }catch{}
    }
}

struct ChallengeChampionBadge:View {
    let label:String
    var body:some View {
        Image(systemName:"trophy.fill").foregroundStyle(Color(red:0.95,green:0.70,blue:0.12))
            .accessibilityLabel(label).help(label).accessibilityIdentifier("challenge-champion-trophy")
    }
}

@MainActor struct ChallengeChampionView:View {
    let runID:String
    let team:[BattlePokemon]
    let language:AppLanguage
    let onClose:()->Void
    @State private var sequence:ChallengeChampionPresentation
    init(runID:String,team:[BattlePokemon],language:AppLanguage,onClose:@escaping()->Void,presentation:ChallengeChampionPresentation?=nil) {
        self.runID=runID;self.team=team;self.language=language;self.onClose=onClose
        _sequence=State(initialValue:presentation ?? ChallengeChampionPresentation())
    }
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    var body:some View {
        VStack(spacing:12) {
            Spacer(minLength:12)
            ZStack {
                if sequence.completed {
                    VStack(spacing:18) {
                        ChallengeChampionBadge(label:L(language).challengeChampion).font(.system(size:64))
                        Text("Champion!").font(.system(size:44,weight:.bold,design:.rounded))
                            .foregroundStyle(Color(red:0.95,green:0.70,blue:0.12))
                    }.accessibilityIdentifier("challenge-champion-complete")
                } else if let index=sequence.index,team.indices.contains(index) {
                    let p=team[index]
                    VStack(spacing:16) {
                        SpriteView(speciesID:p.speciesID,size:190,shiny:p.shiny,form:p.form).frame(height:210)
                        Text(BattleTextCatalog.shared.speciesName(p.speciesID,language:language)).font(.title2.bold())
                        Text("\(index+1) / \(team.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }.opacity(sequence.opacity).id(p.id).accessibilityIdentifier("challenge-champion-member-\(p.id)")
                }
            }.frame(maxWidth:.infinity,minHeight:280)
            Spacer(minLength:12)
            Divider()
            HStack{Spacer();Button(L(language).challengeClose,action:onClose).buttonStyle(.borderedProminent).tint(.blue).accessibilityIdentifier("challenge-champion-close")}.padding(14)
        }.task(id:runID){await sequence.play(count:team.count,reducedMotion:reducedMotion)}
    }
}
