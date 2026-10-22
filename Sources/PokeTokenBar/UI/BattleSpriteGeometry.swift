import AppKit

@MainActor
enum BattleSpriteGeometry {
    static let shadowHeight: CGFloat = 22
    static let feetAboveShadowCenter: CGFloat = 5
    static var footInset: CGFloat { shadowHeight / 2 + feetAboveShadowCenter }
    static func imageBox(stageSize: CGFloat) -> CGFloat { stageSize + 5 - footInset }

    // Center the stance (the lower quarter of visible pixels), not a tail/wing's bounds.
    // One duration-weighted center for the entire animation preserves native pose movement.
    static func horizontalCenter(_ frames: [(image: NSImage, delay: TimeInterval)]) -> CGFloat {
        var moment: CGFloat = 0, mass: CGFloat = 0
        for frame in frames {
            guard let data = frame.image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:data) else { continue }
            for y in Int(CGFloat(bitmap.pixelsHigh)*0.75)..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                let weight = (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) * frame.delay
                moment += (CGFloat(x) + 0.5) / CGFloat(bitmap.pixelsWide) * weight
                mass += weight
            } }
        }
        return mass > 0 ? moment / mass : 0.5
    }

    static func contentBounds(_ bitmap: NSBitmapImageRep) -> CGRect? {
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.01 {
                minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x); maxY = max(maxY,y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)
    }
    // A shared crop preserves the GIF's native movement instead of re-centering each pose.
    static func croppedFrames(_ frames: [(image: NSImage, delay: TimeInterval)]) -> [(image: NSImage, delay: TimeInterval)] {
        let bitmaps = frames.map { $0.image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) }
        guard let first = bitmaps.first ?? nil,
              bitmaps.allSatisfy({ $0?.pixelsWide == first.pixelsWide && $0?.pixelsHigh == first.pixelsHigh }) else { return frames }
        let bounds = bitmaps.compactMap { $0.flatMap(contentBounds) }.reduce(CGRect.null) { $0.union($1) }
        guard !bounds.isNull else { return frames }
        return zip(frames,bitmaps).map { frame, bitmap in
            guard let cg = bitmap?.cgImage?.cropping(to:bounds) else { return frame }
            return (NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height)),frame.delay)
        }
    }
    static func cropped(_ image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data:tiff),
              let bounds = contentBounds(bitmap), let cg = bitmap.cgImage?.cropping(to:bounds) else { return image }
        return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
    }
}
