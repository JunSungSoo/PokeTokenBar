import Foundation

/// PokéRogue capture/bounce timing at authored 1x speed, with a Safari parabolic throw.
/// Coordinates are the original field units; Safari's fixed viewport applies one scale/translation.
struct SafariCaptureSequence: Sendable, Equatable {
    enum Phase: String, Sendable { case flight, absorb, critical, drop, bounce, shake, caught, escaped }
    static let launch = 0.0, impact = 0.5, absorbed = 1.0, dropStart = 1.25, landed = 1.6
    static var shakeStart: Double { dropStart + bounceDuration }
    static let bounceDuration = 1.04453125
    let result: SafariCaptureResult
    init(result: SafariCaptureResult) { self.result = result }
    init(caught: Bool, failedShakes: Int = 0) {
        result = SafariCaptureResult(caught:caught,critical:false,shakes:caught ? 3:min(2,max(0,failedShakes)))
    }
    var caught: Bool { result.caught }
    var critical: Bool { result.critical }
    var shakeCount: Int { result.shakes }
    var bounceStart: Double { Self.dropStart + (critical ? 2.06:0) }
    var shakeStartTime: Double { bounceStart + Self.bounceDuration }
    var resultTime: Double { shakeStartTime + (critical ? 2 : caught ? 4:Double(shakeCount+1)) }
    var duration: Double { resultTime + (caught ? 1:0.5) }
    struct Particle: Sendable { let id:Int; let texture:String; let x:Double; let y:Double; let alpha:Double }
    struct Sound: Sendable { let time:Double; let name:String; var volume:Double = 1 }
    struct Frame: Sendable {
        let phase: Phase
        var x = 236.0, y = 16.0, angle = 0.0, ballOpacity = 1.0, open = 0.0
        var pokemonScale = 1.0, pokemonOpacity = 1.0, pokemonLift = 0.0, pokemonLight = 0.0
        var ballShade = 0.0
        var trainerFrame = 0
        var ballBehindPokemon = false
        var particles: [Particle] = []
    }
    private struct Bounce {
        let start:Double, duration:Double, from:Double, to:Double, power:Double
        let falling:Bool
    }
    private var bounces: [Bounce] {
        var segments:[Bounce] = [], time = bounceStart, power = 1.0, from = 16.0
        while true {
            let duration = power*0.35
            segments.append(Bounce(start:time,duration:duration,from:from,to:72,power:power,falling:true)); time += duration
            power = power > 0.01 ? power*0.5:0
            if power == 0 { break }
            from = 72-56*power
            segments.append(Bounce(start:time,duration:power*0.35,from:72,to:from,power:power,falling:false)); time += power*0.35
        }
        return segments
    }
    var sounds: [Sound] {
        var events = [Sound(time:0,name:critical ? "crit_throw":"pb_throw"),
                      Sound(time:Self.impact,name:"pb_rel"),Sound(time:Self.absorbed,name:"pb_catch")]
        events += bounces.filter(\.falling).map { Sound(time:$0.start+$0.duration,name:"pb_bounce_1",volume:$0.power) }
        for i in 0..<shakeCount { events.append(Sound(time:shakeStartTime+Double(i+1),name:"pb_move")) }
        events.append(Sound(time:resultTime,name:caught ? "pb_lock":"pb_rel"))
        if !caught { events.append(Sound(time:resultTime,name:"cry")) }
        return events.sorted { $0.time < $1.time }
    }
    private func clamp(_ p:Double) -> Double { min(1,max(0,p)) }
    private func sineIn(_ p:Double) -> Double { 1-cos(clamp(p)*Double.pi/2) }
    private func sineOut(_ p:Double) -> Double { sin(clamp(p)*Double.pi/2) }
    private func cubicOut(_ p:Double) -> Double { 1-pow(1-clamp(p),3) }
    func frame(at elapsed: Double) -> Frame {
        let t = max(0,elapsed)
        var f = baseFrame(t)
        f.ballBehindPokemon = t >= 0.3
        if t >= Self.absorbed && t < Self.absorbed+0.017 { f.open = 0.5 }
        // Original default opening particles: 17 emissions, 20ms apart, 16fps, 575ms life.
        for index in 1...17 {
            let age = t-Self.impact-Double(index)*0.02
            guard age >= 0 && age < 0.575 else { continue }
            let angle = Double(index)*Double.pi/4, radius = 48*age/0.575
            let texture = (index+3+Int(floor(age*16))) % 4
            f.particles.append(Particle(id:index,texture:"\(texture).png",x:236+cos(angle)*radius,y:16+sin(angle)*radius,
                alpha:age < 0.5 ? 1:1-sineIn((age-0.5)/0.075)))
        }
        if caught && t >= resultTime && t < resultTime+0.5 {
            let age = t-resultTime
            var visualSeed = result.visualSeed
            func visualRandom() -> Double {
                visualSeed = visualSeed &* 6364136223846793005 &+ 1442695040888963407
                return Double(visualSeed >> 11)/9_007_199_254_740_992
            }
            for i in 0..<3 {
                let u = max(Double.leastNonzeroMagnitude,1-visualRandom())
                let v = visualRandom()
                let distance = sqrt(-2*log(u))*cos(2*Double.pi*v)*25
                let y = age < 0.25 ? 72-10*sineOut(age/0.25):62+10*sineIn((age-0.25)/0.25)
                f.particles.append(Particle(id:100+i,texture:"4.png",x:236+distance*age/0.5,y:y,
                    alpha:age < 0.25 ? 0.5:0.5*(1-sineIn((age-0.25)/0.25))))
            }
        }
        return f
    }
    private func baseFrame(_ t:Double) -> Frame {
        if t < Self.impact {
            let p = clamp(t/0.5)
            var f = Frame(phase:.flight)
            let point = SafariThrowPath.ball.point(at:p)
            f.x = point.x; f.y = point.y
            f.trainerFrame = p < 0.5 ? 3:4
            return f
        }
        if t < Self.absorbed {
            let p = sineIn((t-Self.impact)/0.5)
            var f = Frame(phase:.absorb)
            f.open = t < Self.impact+0.017 ? 0.5:1
            f.pokemonScale = 1-0.75*p; f.pokemonLift = -20*p; f.pokemonLight = 1
            return f
        }
        if t < bounceStart {
            var f = Frame(phase:critical ? .critical:.absorb); f.pokemonOpacity = 0
            if critical {
                let age = t-Self.dropStart-0.5
                if age >= 0 && age < 1 {
                    let cycle = Int(age/0.25), local = age-Double(cycle)*0.25
                    if local < 0.125 { f.x = (cycle == 0 ? 236:239)+(233-(cycle == 0 ? 236:239))*local/0.125 }
                    else { f.x = 233+6*(local-0.125)/0.125 }
                } else if age >= 1 && age < 1.06 { f.x = 239-3*(age-1)/0.06 }
            }
            return f
        }
        if t < shakeStartTime {
            var f = Frame(phase:t < bounceStart+0.35 ? .drop:.bounce); f.pokemonOpacity = 0
            if let segment = bounces.first(where: { t < $0.start+$0.duration }) {
                let p = clamp((t-segment.start)/segment.duration)
                let easing = segment.falling ? pow(p,3):cubicOut(p)
                f.y = segment.from+(segment.to-segment.from)*easing
            } else { f.y = 72 }
            return f
        }
        if t < resultTime {
            var f = Frame(phase:.shake); f.y = 72; f.pokemonOpacity = 0
            let age = t-shakeStartTime
            let cycle = Int(age)
            if cycle >= 1 && cycle <= shakeCount {
                let local = age-Double(cycle)
                let p = local < 0.25 ? local/0.25:local < 0.5 ? 1-(local-0.25)/0.25:0
                let value = cubicOut(p)*(cycle.isMultiple(of:2) ? -1:1)
                f.x += value*4; f.angle = value*27.5
            }
            return f
        }
        var f = Frame(phase:caught ? .caught:.escaped); f.y = 72
        let age = t-resultTime
        if caught {
            f.pokemonOpacity = 0
            f.ballShade = age < 0.2 ? 0.375*sineOut(age/0.2):age < 0.4 ? 0.375*(1-sineIn((age-0.2)/0.2)):0
            if age >= 0.75 { f.ballOpacity = 1-sineIn((age-0.75)/0.25) }
        } else {
            f.open = age < 0.017 ? 0.5:1
            let p = sineOut(age/0.25)
            f.pokemonScale = 0.25+0.75*p; f.pokemonOpacity = 1; f.pokemonLight = 1-p
            if age >= 0.25 { f.ballOpacity = 1-sineIn((age-0.25)/0.25) }
        }
        return f
    }
}

struct SafariCapturePlayback: Sendable {
    let startedAt: Date
    let sequence: SafariCaptureSequence
}
