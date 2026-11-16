import AppKit
import AVFoundation
import ImageIO

@MainActor
enum SafariRogueAssets {
    private struct Atlas: Decodable {
        struct Texture: Decodable {
            struct Frame: Decodable {
                struct Rect: Decodable { let x:Int,y:Int,w:Int,h:Int }
                struct Size: Decodable { let w:Int,h:Int }
                let filename:String; let frame:Rect; let sourceSize:Size; let spriteSourceSize:Rect
            }
            let frames:[Frame]
        }
        let textures:[Texture]
    }
    private static func atlas(_ path:String) -> [String:CGImage] {
        let base = PokeRogueOriginalCatalog.directory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf:base.appendingPathExtension("json")),
              let atlas = try? JSONDecoder().decode(Atlas.self,from:data),
              let source = CGImageSourceCreateWithURL(base.appendingPathExtension("png") as CFURL,nil),
              let image = CGImageSourceCreateImageAtIndex(source,0,nil) else { return [:] }
        var result:[String:CGImage] = [:]
        for frame in atlas.textures.flatMap(\.frames) {
            let r = frame.frame, s = frame.sourceSize, d = frame.spriteSourceSize
            guard let crop = image.cropping(to:CGRect(x:r.x,y:r.y,width:r.w,height:r.h)),
                  let context = CGContext(data:nil,width:s.w,height:s.h,bitsPerComponent:8,bytesPerRow:s.w*4,
                    space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.interpolationQuality = .none
            context.draw(crop,in:CGRect(x:d.x,y:s.h-d.y-d.h,width:d.w,height:d.h))
            result[frame.filename] = context.makeImage()
        }
        return result
    }
    static let balls = atlas("images/pb")
    static let particles = atlas("images/effects/pb_particles")
    static let soundNames = ["pb_throw","crit_throw","pb_rel","pb_catch","pb_bounce_1","pb_move","pb_lock"]
    static func soundURL(_ name:String) -> URL {
        PokeRogueOriginalCatalog.directory.appendingPathComponent("audio/se/\(name).wav")
    }
    static func validate() throws {
        guard ["pb","pb_opening","pb_open"].allSatisfy({balls[$0] != nil}),
              (0...4).allSatisfy({particles["\($0).png"] != nil}) else { throw SafariError.catalog }
        for name in soundNames {
            let file = try AVAudioFile(forReading:soundURL(name))
            guard file.length > 0 else { throw SafariError.catalog }
        }
    }
}

/// Original one-shot sounds share the battle SFX setting; scheduling uses the same capture clock.
@MainActor
final class SafariCaptureAudio {
    private struct Voice { let player:AVAudioPlayer; let gain:Double }
    private var voices:[Voice] = []
    private var scheduler:Task<Void,Never>?
    private(set) var volume = 0.35
    func setVolume(_ value:Double) {
        volume = min(1,max(0,value.isFinite ? value:0.35))
        for voice in voices { voice.player.volume = Float(volume*voice.gain) }
    }
    func start(_ playback:SafariCapturePlayback,speciesID:Int?,volume:Double) {
        scheduler?.cancel(); setVolume(volume)
        scheduler = Task { @MainActor [weak self] in
            for sound in playback.sequence.sounds {
                let delay = sound.time-Date().timeIntervalSince(playback.startedAt)
                if delay > 0 { do { try await Task.sleep(for:.seconds(delay)) } catch { return } }
                guard !Task.isCancelled, let self else { return }
                do {
                    let url:URL
                    if sound.name == "cry", let speciesID {
                        url = PokeRogueOriginalCatalog.directory.appendingPathComponent("audio/cry/\(speciesID).m4a")
                    } else { url = SafariRogueAssets.soundURL(sound.name) }
                    self.voices.removeAll { !$0.player.isPlaying }
                    let player = try AVAudioPlayer(contentsOf:url)
                    player.volume = Float(self.volume*sound.volume)
                    guard player.play() else { throw SafariError.catalog }
                    self.voices.append(Voice(player:player,gain:sound.volume))
                } catch { AppLog.write("Safari capture sound failed: \(sound.name): \(error)") }
            }
        }
    }
    func stop() { scheduler?.cancel(); scheduler = nil; for voice in voices { voice.player.stop() }; voices = [] }
}
