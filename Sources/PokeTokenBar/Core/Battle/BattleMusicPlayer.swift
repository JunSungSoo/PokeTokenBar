import AVFoundation

@MainActor
enum BattleMusicCue {
    case battle, trainerVictory, playerLost
    static func resolve(phase: BattleCoordinator.Phase, outcome: String?, pending: Bool) -> Self? {
        if phase == .playing || (phase == .ended && pending) { return .battle }
        if phase == .ended && outcome == "win" { return .trainerVictory }
        if phase == .ended && outcome == "loss" { return .playerLost }
        return nil
    }
    var prefix: String { self == .battle ? "GoldSilverWildBattle" : "GoldSilverTrainerVictory" }
    var repeats: Bool { self != .playerLost }
}

/// Queue the intro once, then repeat only the loop buffer at the archived PCM boundary.
@MainActor
struct BattleMusicTrack {
    let intro: AVAudioPCMBuffer
    let loop: AVAudioPCMBuffer?
    init(directory: URL, cue: BattleMusicCue = .battle) throws {
        func load(_ name: String) throws -> AVAudioPCMBuffer {
            let file = try AVAudioFile(forReading:directory.appendingPathComponent(name))
            guard file.length > 0, file.length <= Int64(UInt32.max),
                  let buffer = AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:AVAudioFrameCount(file.length)) else {
                throw BattleFailure.invalidMessage
            }
            try file.read(into:buffer)
            return buffer
        }
        intro = try load(cue == .playerLost ? "BattleRevolutionPlayerLost.wav" : cue.prefix + "Intro.wav")
        loop = cue.repeats ? try load(cue.prefix + "Loop.wav") : nil
        if let loop, intro.format != loop.format { throw BattleFailure.invalidMessage }
    }
    func schedule(on node: AVAudioPlayerNode, completion: @escaping @Sendable () -> Void = {}) {
        if let loop {
            node.scheduleBuffer(intro,at:nil,options:[])
            node.scheduleBuffer(loop,at:nil,options:.loops)
        } else {
            node.scheduleBuffer(intro,completionCallbackType:.dataPlayedBack) { _ in completion() }
        }
    }
}

@MainActor
final class BattleMusicPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let track: BattleMusicTrack
    let cue: BattleMusicCue
    private var finished = false
    var isPlaying: Bool { engine.isRunning && node.isPlaying }
    var volume: Double {
        get { Double(engine.mainMixerNode.outputVolume) }
        set { engine.mainMixerNode.outputVolume = Float(min(1,max(0,newValue))) }
    }
    init(directory: URL, volume: Double = 0.35, cue: BattleMusicCue = .battle) throws {
        self.cue = cue
        track = try BattleMusicTrack(directory:directory,cue:cue)
        engine.attach(node)
        engine.connect(node,to:engine.mainMixerNode,format:track.intro.format)
        self.volume = volume
    }
    func play() throws {
        guard !isPlaying, !finished else { return }
        node.stop()
        track.schedule(on:node) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.finished = true
                self.stop()
            }
        }
        try engine.start()
        node.play()
    }
    func stop() { node.stop(); engine.stop() }
}
