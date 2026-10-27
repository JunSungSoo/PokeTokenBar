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
            let description = BattleTextCatalog.shared.description(move.apiName ?? move.name,language:language)
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
                Text(BattleTextCatalog.shared.typeName(move.type,language:language))
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
            Text(l.battleTypeOnly).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var image: NSImage?
    @State private var frames: [(image: NSImage, delay: TimeInterval)] = []
    @State private var frameIndex = 0
    @State private var horizontalCenter: CGFloat = 0.5
    private var moving: Bool { animated && !reduceMotion && !pokemon.fainted }
    private var key: String { SpriteStore.cacheKey(speciesID:pokemon.speciesID,animated:moving,shiny:pokemon.shiny,form:pokemon.form,back:back) }
    private func cachedImage() -> NSImage? {
        for (facing,color) in [(back,pokemon.shiny),(back,false),(false,pokemon.shiny),(false,false)] {
            if let source = SpriteLoader.cachedImage(speciesID:pokemon.speciesID,shiny:color,
                directory:spriteStore.directory,form:pokemon.form,back:facing) {
                return BattleSpriteGeometry.cropped(source)
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
        }.frame(width:size,height:pixelScale == nil ? size:nil,alignment:.bottom)
        .task(id:key) {
            // Clear old species/form/facing pixels before any await; SwiftUI cancels on replacement/removal.
            image = cachedImage(); frameIndex = 0
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
    var body: some View {
        ZStack(alignment:.bottom) {
            Ellipse().fill(Color(red:0.57,green:0.62,blue:0.40))
                .frame(width:sizing?.stageWidth ?? (stageSize+20),height:BattleSpriteGeometry.shadowHeight)
                .overlay(Ellipse().stroke(.white.opacity(0.35),lineWidth:3))
            BattlePokemonSprite(pokemon:pokemon,back:back,size:BattleSpriteGeometry.imageBox(stageSize:stageSize),pixelScale:sizing?.pixelScale,spriteStore:spriteStore,animated:animated)
                .padding(.bottom,BattleSpriteGeometry.footInset).opacity(spriteOpacity)
        }.frame(width:sizing?.stageWidth ?? (stageSize+20),height:sizing?.stageHeight ?? (stageSize+5),alignment:.bottom)
    }
}
