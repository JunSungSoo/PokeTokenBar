import Foundation

/// A ballistic parabola with constant horizontal velocity in screen coordinates.
/// Height is measured above the straight line joining the two endpoints.
struct SafariThrowPath {
    let start: CGPoint
    let end: CGPoint
    let height: CGFloat
    func point(at progress: Double) -> CGPoint {
        let p = CGFloat(min(1,max(0,progress)))
        return CGPoint(x:start.x+(end.x-start.x)*p,
                       y:start.y+(end.y-start.y)*p-4*height*p*(1-p))
    }
    static let ball = Self(start:CGPoint(x:16,y:80),end:CGPoint(x:236,y:16),height:48)
    static let itemDuration = 0.55
    static func item(width:CGFloat) -> Self {
        Self(start:CGPoint(x:width*0.25,y:200),end:CGPoint(x:width*0.75,y:110),height:75)
    }
}
