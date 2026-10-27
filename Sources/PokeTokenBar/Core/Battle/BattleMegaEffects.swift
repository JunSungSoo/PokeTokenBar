import Foundation

enum BattleMegaEffects {
    /// Showdown captures the new form at detailschange immediately before -mega.
    /// Hold that intermediate scene so the old sprite survives until the transformation reveal.
    static func deferredSceneIDs(frame:BattleFrame)->Set<Int> {
        var result=Set<Int>()
        for index in frame.log.indices.dropLast() {
            let line=frame.log[index].split(separator:"|",omittingEmptySubsequences:false)
            let next=frame.log[index+1].split(separator:"|",omittingEmptySubsequences:false)
            if line.count>2,next.count>2,line[1]=="detailschange",next[1]=="-mega",line[2]==next[2] {
                result.insert((frame.logOffset ?? 0)+index)
            }
        }
        return result
    }
    static func event(scene:BattleScene,line:String,ownPlayer:Int)->BattleVisualEvent? {
        let parts=line.split(separator:"|",omittingEmptySubsequences:false)
        guard parts.count>2,parts[1]=="-mega" else{return nil}
        let token=parts[2].split(separator:":").first ?? ""
        guard token.count==3,token.first=="p",let side=token.dropFirst().first,["1","2"].contains(side),
              let slot=token.last,["a","b"].contains(slot) else{return nil}
        return BattleVisualEvent(id:scene.id,move:"",type:"",category:"Status",
            source:.init(own:Int(String(side))==ownPlayer+1,slot:slot=="b" ? 1:0),targets:[],phase:"mega")
    }
}
