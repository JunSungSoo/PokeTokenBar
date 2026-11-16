import SwiftUI

@MainActor
struct SafariThrownItem: View {
    let action: SafariAction
    let progress: Double
    static let previousSize: CGFloat = 28
    static let rockSize: CGFloat = previousSize * 0.5
    var body: some View {
        Group {
            if action == .rock { SafariCartoonRock().frame(width:Self.rockSize,height:Self.rockSize) }
            else { Text("🍎").font(.system(size:Self.previousSize)) }
        }
        .rotationEffect(.degrees(360*min(1,max(0,progress))))
        .accessibilityHidden(true)
    }
}

/// Crisp, outlined cartoon pebble rather than an OS-dependent realistic emoji.
@MainActor
struct SafariCartoonRock: View {
    var body: some View {
        Canvas { context,size in
            func point(_ x:CGFloat,_ y:CGFloat) -> CGPoint { CGPoint(x:x*size.width,y:y*size.height) }
            var outline = Path()
            outline.move(to:point(0.08,0.65))
            for p in [point(0.16,0.30),point(0.44,0.12),point(0.77,0.21),point(0.93,0.56),point(0.76,0.87),point(0.32,0.91)] { outline.addLine(to:p) }
            outline.closeSubpath()
            context.fill(outline,with:.color(Color(red:0.61,green:0.59,blue:0.56)))
            var shade = Path()
            shade.move(to:point(0.08,0.65));shade.addLine(to:point(0.52,0.67))
            shade.addLine(to:point(0.77,0.21));shade.addLine(to:point(0.93,0.56))
            shade.addLine(to:point(0.76,0.87));shade.addLine(to:point(0.32,0.91));shade.closeSubpath()
            context.fill(shade,with:.color(Color(red:0.42,green:0.40,blue:0.38)))
            var highlight = Path()
            highlight.move(to:point(0.25,0.35));highlight.addLine(to:point(0.46,0.23));highlight.addLine(to:point(0.63,0.27))
            context.stroke(highlight,with:.color(Color(red:0.86,green:0.84,blue:0.78)),style:StrokeStyle(lineWidth:size.width*0.09,lineCap:.round,lineJoin:.round))
            context.stroke(outline,with:.color(Color(red:0.18,green:0.16,blue:0.15)),style:StrokeStyle(lineWidth:size.width*0.08,lineJoin:.round))
        }
    }
}
