import AppKit
import SwiftUI

/// One side's original PokéRogue platform as full 320×132 field frames; `end` ships a 12 fps atlas.
@MainActor
struct BattleArenaLayer {
    static let frameDuration: TimeInterval = 1.0 / 12
    let frames: [CGImage]
    /// Atlas frame names in playback order; empty for a single-image platform.
    let frameNames: [String]

    private struct Atlas: Decodable {
        struct Texture: Decodable { let frames: [Frame] }
        struct Frame: Decodable { let filename: String; let frame: Box; let spriteSourceSize: Box; let rotated: Bool }
        struct Box: Decodable {
            let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
            enum CodingKeys: String, CodingKey { case x, y, width = "w", height = "h" }
            var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        }
        let textures: [Texture]
    }

    private static var cache: [String: BattleArenaLayer] = [:]

    static func load(arena: BattleArena, own: Bool) -> Self? {
        let path = arena.platformPath(own: own)
        if let cached = cache[path] { return cached }
        let url = PokeRogueOriginalCatalog.directory.appendingPathComponent(path)
        guard let sheet = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let frames: [CGImage]
        var frameNames: [String] = []
        if let data = try? Data(contentsOf: url.deletingPathExtension().appendingPathExtension("json")) {
            guard let atlas = try? JSONDecoder().decode(Atlas.self, from: data) else { return nil }
            // arena-base.ts plays zero-padded filenames from 0001, not the atlas packing order.
            let ordered = (atlas.textures.first?.frames ?? []).sorted { $0.filename < $1.filename }
            frames = ordered.compactMap { fieldFrame(sheet: sheet, frame: $0) }
            frameNames = ordered.map(\.filename)
            guard frames.count == ordered.count else { return nil }
        } else {
            frames = sheet.width == Int(BattleFieldScene.fieldWidth) && sheet.height == Int(BattleFieldScene.fieldHeight) ? [sheet] : []
        }
        guard !frames.isEmpty else { return nil }
        let layer = Self(frames: frames, frameNames: frameNames)
        cache[path] = layer
        return layer
    }

    /// Draws a trimmed atlas frame back at its offset inside the 320×132 field.
    private static func fieldFrame(sheet: CGImage, frame: Atlas.Frame) -> CGImage? {
        // sRGB keeps the PNG's colours; a device space would shift them on screen.
        guard !frame.rotated, let piece = sheet.cropping(to: frame.frame.rect), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(BattleFieldScene.fieldWidth), height: Int(BattleFieldScene.fieldHeight),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let target = frame.spriteSourceSize
        context.interpolationQuality = .none
        // Core Graphics counts y from the bottom; atlas offsets count from the top.
        context.draw(piece, in: CGRect(x: target.x, y: BattleFieldScene.fieldHeight - target.y - target.height,
                                       width: target.width, height: target.height))
        return context.makeImage()
    }
}

/// The enemy platform cropped to its opaque base, so a Safari encounter can stand on it.
@MainActor
struct BattleArenaPlatform {
    /// Points per original pixel: the arena background's scale at the default battle width.
    static let pointsPerPixel: CGFloat = 660.0 / 320
    // Centre of the enemy base ellipse inside the original field layer.
    private static let enemyCenter = CGPoint(x: 216, y: 74)

    let image: NSImage
    let size: CGSize
    /// Shift from "bottom-centre on the stage" to "platform under the feet".
    let offset: CGSize

    private static var cache: [BattleArena: BattleArenaPlatform] = [:]

    static func load(arena: BattleArena) -> Self? {
        if let cached = cache[arena] { return cached }
        guard let field = BattleArenaLayer.load(arena: arena, own: false)?.frames.first,
              let bounds = BattleSpriteGeometry.contentBounds(NSBitmapImageRep(cgImage: field)),
              let cropped = field.cropping(to: bounds) else { return nil }
        let scale = pointsPerPixel
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let belowFeet = (bounds.maxY - enemyCenter.y) * scale
        let platform = Self(image: NSImage(cgImage: cropped, size: size), size: size,
                            offset: CGSize(width: size.width / 2 - (enemyCenter.x - bounds.minX) * scale,
                                           height: belowFeet - BattleSpriteGeometry.footInset))
        cache[arena] = platform
        return platform
    }
}

@MainActor
struct BattleArenaPlatformSurface: View {
    let platform: BattleArenaPlatform
    var body: some View {
        Image(nsImage: platform.image).resizable().interpolation(.none)
            .frame(width: platform.size.width, height: platform.size.height)
            .offset(platform.offset)
    }
}
