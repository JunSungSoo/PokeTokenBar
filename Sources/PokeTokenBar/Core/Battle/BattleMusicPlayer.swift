import AVFoundation

/// Both pieces use identical PCM formats. Queueing them on one node retains the source's
/// sample boundary; only the loop buffer repeats, so the encounter intro plays once.
@MainActor
struct BattleMusicTrack {
    let intro: AVAudioPCMBuffer
    let loop: AVAudioPCMBuffer
    init(directory: URL) throws {
        func load(_ name: String) throws -> AVAudioPCMBuffer {
            let file = try AVAudioFile(forReading:directory.appendingPathComponent(name))
            guard file.length > 0, file.length <= Int64(UInt32.max),
                  let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else {
                throw BattleFailure.invalidMessage
            }
            try file.read(into:buffer)
            return buffer
        }
        intro = try load("GoldSilverWildBattleIntro.wav")
        loop = try load("GoldSilverWildBattleLoop.wav")
        guard intro.format == loop.format else { throw BattleFailure.invalidMessage }
    }
    func schedule(on node: AVAudioPlayerNode) {
        node.scheduleBuffer(intro,at:nil,options:[])
        node.scheduleBuffer(loop,at:nil,options:.loops)
    }
}

@MainActor
final class BattleMusicPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let track: BattleMusicTrack
    var isPlaying: Bool { engine.isRunning && node.isPlaying }
    var volume: Double {
        get { Double(engine.mainMixerNode.outputVolume) }
        set { engine.mainMixerNode.outputVolume = Float(min(1,max(0,newValue))) }
    }
    init(directory: URL, volume: Double = 0.35) throws {
        track = try BattleMusicTrack(directory:directory)
        engine.attach(node)
        engine.connect(node,to:engine.mainMixerNode,format:track.intro.format)
        self.volume = volume
    }
    func play() throws {
        guard !isPlaying else { return }
        node.stop()
        track.schedule(on:node)
        try engine.start()
        node.play()
    }
    func stop() { node.stop(); engine.stop() }
}
