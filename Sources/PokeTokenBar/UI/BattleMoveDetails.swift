import SwiftUI

@MainActor
struct BattleMoveDetails: View {
    let move: BattleMove
    let language: AppLanguage
    var compact = false
    @State private var fullDescription = false
    private var l: L { L(language) }
    var body: some View {
        VStack(alignment:.leading,spacing:compact ? 6 : 10) {
            Label(l.battleSelected,systemImage:"checkmark.circle.fill").font(.caption.bold()).foregroundStyle(Color.accentColor)
            let description = l.battleMoveDescription(move)
            HStack(alignment: .top) {
                Text(description).font(compact ? .caption : .callout)
                    .lineLimit(compact ? 4 : nil).fixedSize(horizontal:false,vertical:true)
                if compact {
                    Button { fullDescription = true } label: { Image(systemName: "info.circle") }
                        .buttonStyle(.plain).accessibilityLabel(l.battleFullDescription)
                        .popover(isPresented: $fullDescription) {
                            ScrollView { Text(description).font(.callout).textSelection(.enabled).padding(16).reservesScrollerLane() }
                                .frame(width: 420, height: min(480, CGFloat(description.count) * 0.35 + 60))
                        }
                }
            }
            HStack {
                Text(l.battlePower + ": " + ((move.power ?? 0) > 0 ? String(move.power!) : "—"))
                Spacer()
                Text(l.battleBaseAccuracy + ": " + l.battleAccuracy(move.accuracy))
                    .accessibilityIdentifier("battle-move-accuracy")
                Spacer()
                Text("\(l.battlePP) \(move.pp) / \(move.maxPP)")
            }.font(.callout.monospacedDigit())
            HStack {
                Text(l.battleCategory(move.category ?? "Status"))
                Text("·")
                Text(l.battleMoveType(move))
            }.font(.callout.bold())
            Text(l.battleTarget + ": " + l.battleMoveTarget(move)).font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("battle-move-scope")
            Divider()
            ForEach(Array((move.matchups ?? []).enumerated()),id:\.offset) { _, matchup in
                HStack {
                    Text((move.matchups?.count ?? 0) > 1 ? "\(matchup.location) · " + BattleTextCatalog.shared.pokemonName(matchup.name,language:language) : BattleTextCatalog.shared.pokemonName(matchup.name,language:language)).lineLimit(1)
                    Spacer()
                    Text(l.battleEffectiveness(matchup.multiplier)).fontWeight(.semibold)
                        .foregroundStyle(matchup.multiplier == 0 ? Color.red : (matchup.multiplier ?? 1) > 1 ? Color.green : Color.secondary)
                }.font(.caption)
            }
            Text(move.ignoresTypeMatchup == true ? l.battleTypelessMove : l.battleTypeOnly).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        }.padding(12).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))

    }
}

@MainActor
struct BattlePokemonSprite: View {
    let pokemon: BattleCombatant
    let back: Bool
    let size: CGFloat
    var pixelScale:CGFloat? = nil
    var spriteStore: SpriteStore = .shared
    var animated = true
    var bobsWhenStatic = false
    @State private var bobUp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0
    @State private var horizontalCenter: CGFloat = 0.5
    init(pokemon:BattleCombatant,back:Bool,size:CGFloat,pixelScale:CGFloat? = nil,
         spriteStore:SpriteStore = .shared,animated:Bool = true,bobsWhenStatic:Bool = false) {
        self.pokemon = pokemon; self.back = back; self.size = size
        self.pixelScale = pixelScale; self.spriteStore = spriteStore; self.animated = animated; self.bobsWhenStatic = bobsWhenStatic
        // Seed the same cropped assets used by the task so encounter switches and
        // offscreen rendering do not briefly show a placeholder before onAppear.
        let raw = Self.cachedImage(pokemon:pokemon,back:back,spriteStore:spriteStore)
        let decoded = animated && !pokemon.fainted ? SpriteLoader.cachedFrames(
            speciesID:pokemon.speciesID,shiny:pokemon.shiny,directory:spriteStore.directory,form:pokemon.form,back:back) : []
        let key = spriteStore.directory.path + "/" + SpriteStore.cacheKey(speciesID:pokemon.speciesID,
            animated:animated && !pokemon.fainted,shiny:pokemon.shiny,form:pokemon.form,back:back)
        let seed = Self.prepared(key:key,image:raw,frames:decoded)
        _image = State(initialValue:seed.image)
        _frames = State(initialValue:seed.frames)
        _horizontalCenter = State(initialValue:seed.center)
    }
    /// Keep pixel scans out of TimelineView redraws. Source image identity detects
    /// real cache replacements; missing assets are not retained as negative entries.
    @MainActor private final class Prepared {
        let source:NSImage?; let originals:[(image:NSImage,delay:TimeInterval)]
        let image:NSImage?; let frames:[(image:NSImage,delay:TimeInterval)]; let center:CGFloat
        init(image:NSImage?,frames:[(image:NSImage,delay:TimeInterval)]) {
            source=image; originals=frames
            self.image=image.map(BattleSpriteGeometry.cropped)
            self.frames=BattleSpriteGeometry.croppedFrames(frames)
            center=BattleSpriteGeometry.horizontalCenter(self.frames.isEmpty ? self.image.map { [($0,1)] } ?? []:self.frames)
        }
    }
    private static let preparedCache:NSCache<NSString,Prepared> = {
        let cache=NSCache<NSString,Prepared>(); cache.countLimit=16; return cache
    }()
    private static func prepared(key:String,image:NSImage?,frames:[(image:NSImage,delay:TimeInterval)]) -> Prepared {
        if let old=preparedCache.object(forKey:key as NSString), old.source === image,
           old.originals.count == frames.count,
           zip(old.originals,frames).allSatisfy({ $0.image === $1.image && $0.delay == $1.delay }) { return old }
        let result=Prepared(image:image,frames:frames)
        if image != nil || !frames.isEmpty { preparedCache.setObject(result,forKey:key as NSString) }
        return result
    }
    private var moving: Bool { animated && !reduceMotion && !pokemon.fainted }
    private var key: String { SpriteStore.cacheKey(speciesID:pokemon.speciesID,animated:moving,shiny:pokemon.shiny,form:pokemon.form,back:back) }
    private static func cachedImage(pokemon:BattleCombatant,back:Bool,spriteStore:SpriteStore) -> NSImage? {
        for (facing,color) in [(back,pokemon.shiny),(back,false),(false,pokemon.shiny),(false,false)] {
            if let source = SpriteLoader.cachedImage(speciesID:pokemon.speciesID,shiny:color,
                directory:spriteStore.directory,form:pokemon.form,back:facing) {
                return source
            }
        }
        return nil
    }
    private func loadStatic() async {
        for (facing,color) in [(back,pokemon.shiny),(back,false),(false,pokemon.shiny),(false,false)] {
            let data = await spriteStore.data(speciesID:pokemon.speciesID,animated:false,shiny:color,form:pokemon.form,back:facing)
            guard !Task.isCancelled else { return }
            if let source = data.flatMap(NSImage.init(data:)) {
                let cropped = BattleSpriteGeometry.cropped(source)
                image = cropped
                horizontalCenter = BattleSpriteGeometry.horizontalCenter([(cropped,1)])
                return
            }
        }
    }
    var body: some View {
        Group {
            if let current = frames.isEmpty ? image : frames[frameIndex % frames.count].image {
                let target=PokeRogueSpriteSizes.shared.battleSize(speciesID:pokemon.speciesID,form:pokemon.form,back:back)
                let native=SpriteFit.size(for:current.size,width:target.width,height:target.height)
                let fitted=pixelScale.map{CGSize(width:native.width*$0,height:native.height*$0)} ?? SpriteFit.size(for:current.size,box:size)
                Image(nsImage:current).interpolation(.none).resizable().frame(width:fitted.width,height:fitted.height)
                    .offset(x:(0.5-horizontalCenter)*fitted.width)
            } else {
                Image(systemName:"pawprint.fill").font(.system(size:22)).foregroundStyle(.secondary)
            }
        }
        .offset(y:bobsWhenStatic && !reduceMotion && frames.isEmpty && bobUp ? -3:0)
        .animation(bobsWhenStatic && !reduceMotion ? .easeInOut(duration:0.9).repeatForever(autoreverses:true):nil,value:bobUp)
        .frame(width:size,height:pixelScale == nil ? size:nil,alignment:.bottom)
        .onAppear { if bobsWhenStatic && !reduceMotion { bobUp = true } }
        .task(id:key) {
            // Clear old species/form/facing pixels before any await; SwiftUI cancels on replacement/removal.
            image = Self.cachedImage(pokemon:pokemon,back:back,spriteStore:spriteStore).map(BattleSpriteGeometry.cropped); frameIndex = 0
            horizontalCenter = image.map { BattleSpriteGeometry.horizontalCenter([($0,1)]) } ?? 0.5
            frames = moving ? BattleSpriteGeometry.croppedFrames(SpriteLoader.cachedFrames(
                speciesID:pokemon.speciesID,shiny:pokemon.shiny,directory:spriteStore.directory,form:pokemon.form,back:back)) : []
            if moving && frames.count < 2 {
                let decoded = await SpriteLoader.recoveringAnimationFrames(
                    speciesID:pokemon.speciesID,shiny:pokemon.shiny,store:spriteStore,form:pokemon.form,back:back,
                    onUnavailable: { await loadStatic() })
                guard !Task.isCancelled else { return }
                frames = BattleSpriteGeometry.croppedFrames(decoded)
            } else if !moving && image == nil { await loadStatic() }
            if !frames.isEmpty { horizontalCenter = BattleSpriteGeometry.horizontalCenter(frames) }
            guard frames.count > 1 else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for:.seconds(frames[frameIndex % frames.count].delay)) }
                catch { return }
                guard !Task.isCancelled else { return }
                frameIndex = (frameIndex + 1) % frames.count
            }
        }
    }
}

@MainActor
struct BattlePokemonStage: View {
    var spriteOpacity:Double=1
    let pokemon: BattleCombatant
    let back: Bool
    let stageSize: CGFloat
    var sizing:BattleSpriteSizing? = nil
    var spriteStore: SpriteStore = .shared
    var animated = true
    var showsGround = true
    var body: some View {
        let width=sizing?.stageWidth ?? (stageSize+20)
        let footprint = BattleSpriteGeometry.groundSize(stageWidth: width)
        ZStack(alignment:.bottom) {
            if showsGround { BattleGroundSurface(size: footprint) }
            BattlePokemonSprite(pokemon:pokemon,back:back,size:BattleSpriteGeometry.imageBox(stageSize:stageSize),pixelScale:sizing?.pixelScale,spriteStore:spriteStore,animated:animated)
                .padding(.bottom,BattleSpriteGeometry.footInset).opacity(spriteOpacity)
        }.frame(width:width,height:sizing?.stageHeight ?? (stageSize+5),alignment:.bottom)
    }
}

/// One surface can support a single battler or an entire doubles pair.
@MainActor
struct BattleGroundSurface: View {
    let size: CGSize
    var body: some View {
        Ellipse().fill(LinearGradient(colors:[Color(red:0.39,green:0.26,blue:0.17),Color(red:0.18,green:0.12,blue:0.08)],startPoint:.top,endPoint:.bottom))
            .overlay(Ellipse().fill(.black.opacity(0.24)).scaleEffect(x:0.72,y:0.48))
            .overlay(Ellipse().stroke(.black.opacity(0.65),lineWidth:1))
            .frame(width:size.width,height:size.height)
            .padding(.bottom,BattleSpriteGeometry.footInset-size.height/2)
    }
}
