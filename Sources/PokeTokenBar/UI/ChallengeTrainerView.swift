import AppKit
import ImageIO
import Observation
import SwiftUI

@MainActor enum ChallengeTrainerCatalog {
    static func key(_ encounter:String)->String {
        if encounter=="ltsurge" {return "lt_surge"}
        return encounter.replacingOccurrences(of:"[12]$",with:"",options:.regularExpression)
    }
    static func resource(_ name:String,_ ext:String)->URL? {
        let bundled=Bundle.main.resourceURL?.appendingPathComponent("BattleText/ChallengeTrainers/\(name).\(ext)")
        return bundled.flatMap{FileManager.default.fileExists(atPath:$0.path) ? $0:nil}
            ?? Bundle.module.url(forResource:name,withExtension:ext,subdirectory:"BattleText/ChallengeTrainers")
    }
    static let names:[String:[String:String]] = {
        guard let url=resource("names","json"),let data=try? Data(contentsOf:url),let names=try? JSONDecoder().decode([String:[String:String]].self,from:data) else{return [:]}
        return names
    }()
    static func name(_ encounter:String,language:AppLanguage)->String {
        names[key(encounter)]?[language.rawValue] ?? L(language).challengeTitle
    }
    private struct Atlas:Decodable {
        struct Texture:Decodable {
            struct Frame:Decodable {struct Rect:Decodable {let x:Int;let y:Int;let w:Int;let h:Int};let frame:Rect;let rotated:Bool}
            let frames:[Frame]
        }
        let textures:[Texture]
    }
    private static var images:[String:NSImage]=[:]
    static func image(_ key:String)->NSImage? {
        if let cached=images[key] {return cached}
        guard let png=resource(key,"png"),let json=resource(key,"json"),let data=try? Data(contentsOf:json),
              let atlas=try? JSONDecoder().decode(Atlas.self,from:data),let frames=atlas.textures.first?.frames,
              let source=CGImageSourceCreateWithURL(png as CFURL,nil),let image=CGImageSourceCreateImageAtIndex(source,0,nil) else{return nil}
        let index=["clair":8,"red":15,"lance":8,"bugsy":8][key] ?? 0
        guard frames.indices.contains(index),!frames[index].rotated else{return nil}
        let r=frames[index].frame
        guard let cropped=image.cropping(to:CGRect(x:r.x,y:r.y,width:r.w,height:r.h)) else{return nil}
        let result=NSImage(cgImage:cropped,size:NSSize(width:cropped.width,height:cropped.height));images[key]=result;return result
    }
}
@MainActor struct ChallengeTrainerSprite:View {
    let key:String
    var body:some View {
        Group {
            if let image=ChallengeTrainerCatalog.image(key) {Image(nsImage:image).resizable().interpolation(.none).scaledToFit()}
            else {Image(systemName:"person.fill").resizable().scaledToFit().foregroundStyle(.secondary)}
        }.accessibilityHidden(true)
    }
}
@MainActor @Observable final class ChallengeTrainerIntro {
    private(set) var key="brock"
    private(set) var active=false
    private(set) var exiting=false
    private(set) var ownEntryStarted=false
    var duration:Duration = .milliseconds(450)
    func openingMessages(events:[BattleVisualEvent],messages:[Int:String],language:AppLanguage,enabled:Bool)->[Int:String] {
        guard enabled,let first=events.first(where:{$0.phase=="entry"}) else{return messages}
        var result=messages
        result[first.id]=L(language).challengeTrainerAppeared(ChallengeTrainerCatalog.name(key,language:language))
        return result
    }
    func reset(encounter:String){key=ChallengeTrainerCatalog.key(encounter);exiting=false;ownEntryStarted=false;active=true}
    func finish(){active=false;exiting=false}
    func before(_ event:BattleVisualEvent)async {
        guard active,event.phase=="entry" else{return}
        if event.source.own {ownEntryStarted=true;return}
        // The shared effects queue calls this only after the prior own-entry completes.
        withAnimation(.easeInOut(duration:0.45)){exiting=true}
        do {try await Task.sleep(for:duration)} catch {return}
        guard !Task.isCancelled else{return}
        active=false
    }
}
