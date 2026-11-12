import AppKit

@MainActor
enum BattleSpriteGeometry {
    static let shadowHeight: CGFloat = 22
    static let feetAboveShadowCenter: CGFloat = 0
    static var footInset: CGFloat { shadowHeight / 2 + feetAboveShadowCenter }
    static func imageBox(stageSize: CGFloat) -> CGFloat { stageSize + 5 - footInset }
    /// The shared stage determines the ground footprint for the whole match.
    static func groundSize(stageWidth: CGFloat) -> CGSize {
        CGSize(width: stageWidth * 0.75, height: shadowHeight)
    }

    /// Read alpha from a single bitmap instead of creating an AppKit color for each pixel.
    private static func rgbaPixels(_ bitmap: NSBitmapImageRep) -> [UInt8]? {
        guard let image = bitmap.cgImage else { return nil }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return rendered ? pixels : nil
    }

    private static func bitmap(for image: NSImage) -> NSBitmapImageRep? {
        if let bitmap = image.representations.first as? NSBitmapImageRep { return bitmap }
        return image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))
    }

    // Use a single duration-weighted anchor so the GIF retains its native motion.
    static func horizontalCenter(_ frames: [(image: NSImage, delay: TimeInterval)]) -> CGFloat {
        var bodyMoment: CGFloat = 0
        var bodyMass: CGFloat = 0
        var stanceMoment: CGFloat = 0
        var stanceMass: CGFloat = 0
        for frame in frames {
            guard let bitmap = bitmap(for: frame.image) else { continue }
            let width = bitmap.pixelsWide
            let height = bitmap.pixelsHigh
            let stanceStart = height * 3 / 4
            let pixels = rgbaPixels(bitmap)
            for y in 0..<height {
                var rowMass = 0
                var rowMoment = 0
                if let pixels {
                    let rowOffset = y * width * 4
                    for x in 0..<width {
                        let alpha = Int(pixels[rowOffset + x * 4 + 3])
                        rowMass += alpha
                        rowMoment += x * alpha
                    }
                } else {
                    for x in 0..<width {
                        let alpha = Int(((bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded())
                        rowMass += alpha
                        rowMoment += x * alpha
                    }
                }
                let mass = CGFloat(rowMass) * frame.delay
                let moment = (CGFloat(rowMoment) + CGFloat(rowMass) / 2) * frame.delay / CGFloat(width)
                bodyMass += mass
                bodyMoment += moment
                if y >= stanceStart {
                    stanceMass += mass
                    stanceMoment += moment
                }
            }
        }
        guard bodyMass > 0 else { return 0.5 }
        // A sparse bottom band can be a detached puff or a wing tip instead of feet.
        if stanceMass < bodyMass * 0.1 { return bodyMoment / bodyMass }
        return stanceMoment / stanceMass
    }

    static func contentBounds(_ bitmap: NSBitmapImageRep) -> CGRect? {
        var minX = bitmap.pixelsWide, minY = bitmap.pixelsHigh, maxX = -1, maxY = -1
        let alpha = rgbaPixels(bitmap)
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let opacity = alpha.map { CGFloat($0[(y * bitmap.pixelsWide + x) * 4 + 3]) / 255 }
                    ?? bitmap.colorAt(x:x,y:y)?.alphaComponent ?? 0
                guard opacity > 0.01 else { continue }
                minX = min(minX,x); minY = min(minY,y); maxX = max(maxX,x); maxY = max(maxY,y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1)
    }
    // A shared crop preserves the GIF's native movement instead of re-centering each pose.
    static func croppedFrames(_ frames: [(image: NSImage, delay: TimeInterval)]) -> [(image: NSImage, delay: TimeInterval)] {
        let bitmaps = frames.map { bitmap(for: $0.image) }
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
        guard let bitmap = bitmap(for: image),
              let bounds = contentBounds(bitmap), let cg = bitmap.cgImage?.cropping(to:bounds) else { return image }
        return NSImage(cgImage:cg,size:NSSize(width:cg.width,height:cg.height))
    }
}

/// Preserve battle slot indices while sizing the surface from living displayed actors only.
struct BattlePairGroundLayout {
    let spacing: CGFloat
    let width: CGFloat
    let ground: CGRect?

    init(widths: [CGFloat], living: [Bool], stageWidth: CGFloat) {
        let slotSpacing = widths.count == 2 ? (widths[0] + widths[1]) / 2 + 12 - stageWidth : 0
        spacing = slotSpacing
        width = stageWidth * CGFloat(widths.count) + slotSpacing * CGFloat(max(0, widths.count - 1))
        let bounds = widths.enumerated().compactMap { slot, visibleWidth -> CGRect? in
            guard living.indices.contains(slot), living[slot] else { return nil }
            let center = stageWidth / 2 + CGFloat(slot) * (stageWidth + slotSpacing)
            return CGRect(x: center - visibleWidth / 2, y: 0, width: visibleWidth, height: 22)
        }.reduce(CGRect.null) { $0.union($1) }
        if bounds.isNull { ground = nil }
        else {
            let left = max(0, bounds.minX - 16), right = min(width, bounds.maxX + 16)
            ground = CGRect(x: left, y: 0, width: right - left, height: 22)
        }
    }
}
