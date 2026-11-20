import CoreGraphics

/// PokéRogue's visible 320×132 field scaled to the battlefield height, centred, with both sides cropped.
struct BattleFieldScene: Equatable {
    static let fieldWidth: CGFloat = 320
    static let fieldHeight: CGFloat = 132
    /// Arena backgrounds are 320×180; the original message box covers the bottom 48 rows.
    static let backgroundHeight: CGFloat = 180
    // Battler feet after the encounter slide: PlayerPokemon (106,148), EnemyPokemon (236,84).
    private static let ownFeet = CGPoint(x: 106, y: 148)
    private static let foeFeet = CGPoint(x: 236, y: 84)
    // Double-battle field offsets for the LEFT and RIGHT slots.
    private static let doubleOffsets = [CGVector(dx: -32, dy: -8), CGVector(dx: 32, dy: 0)]
    /// ArenaBase x after the slide: the player base stays at 0, the enemy base rests at 20.
    private static let foeBaseX: CGFloat = 20

    let size: CGSize
    var unit: CGFloat { size.height / Self.fieldHeight }
    var origin: CGPoint { CGPoint(x: (size.width - Self.fieldWidth * unit) / 2, y: 0) }

    func point(_ field: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + field.x * unit, y: origin.y + field.y * unit)
    }

    func feet(own: Bool, slot: Int, count: Int) -> CGPoint {
        let base = own ? Self.ownFeet : Self.foeFeet
        let offset = count > 1 && Self.doubleOffsets.indices.contains(slot) ? Self.doubleOffsets[slot] : .zero
        return point(CGPoint(x: base.x + offset.dx, y: base.y + offset.dy))
    }

    /// Bottom-centred battler box whose centre is the original move focus, 32 units above the feet.
    @MainActor func stageFrame(own: Bool, slot: Int, count: Int, sizing: BattleSpriteSizing) -> CGRect {
        let feet = feet(own: own, slot: slot, count: count)
        return CGRect(x: feet.x - sizing.stageWidth / 2, y: feet.y + BattleSpriteGeometry.footInset - sizing.stageHeight,
                      width: sizing.stageWidth, height: sizing.stageHeight)
    }

    /// Full 320×132 platform layer, placed at the original field origin.
    func baseRect(own: Bool) -> CGRect {
        let topLeft = point(CGPoint(x: own ? 0 : Self.foeBaseX, y: 0))
        return CGRect(x: topLeft.x, y: topLeft.y, width: Self.fieldWidth * unit, height: Self.fieldHeight * unit)
    }

    /// The background follows the field; a field wider than the scene widens it around the same centre.
    var backgroundRect: CGRect {
        let scale = max(unit, size.width / Self.fieldWidth)
        let width = Self.fieldWidth * scale
        return CGRect(x: (size.width - width) / 2, y: origin.y, width: width, height: Self.backgroundHeight * scale)
    }
}
