// Reconstruct native frames from original PokéRogue TexturePacker atlases.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct Size:Decodable {let w:Int;let h:Int}
struct Box:Decodable {let x:Int;let y:Int;let w:Int;let h:Int}
struct Frame:Decodable {let filename:String;let rotated:Bool;let sourceSize:Size;let spriteSourceSize:Box;let frame:Box}
struct Texture:Decodable {let frames:[Frame]}
struct Atlas:Decodable {
    let textures:[Texture]
    enum CodingKeys:String,CodingKey {case textures,frames}
    init(from decoder:Decoder)throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        if let t=try c.decodeIfPresent([Texture].self,forKey:.textures){textures=t}
        else {textures=[Texture(frames:try c.decode([Frame].self,forKey:.frames))]}
    }
}
struct Job:Decodable {let atlas:String;let image:String;let destination:String}
let jobs=try JSONDecoder().decode([Job].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
for job in jobs {
    let atlas=try JSONDecoder().decode(Atlas.self,from:Data(contentsOf:URL(fileURLWithPath:job.atlas)))
    precondition(atlas.textures.count==1,"Unexpected multiple textures")
    let frames=atlas.textures[0].frames.sorted{$0.filename<$1.filename}
    let source=CGImageSourceCreateWithURL(URL(fileURLWithPath:job.image) as CFURL,nil)!
    let sheet=CGImageSourceCreateImageAtIndex(source,0,nil)!
    let width=frames.map{$0.sourceSize.w}.max()!,height=frames.map{$0.sourceSize.h}.max()!
    let animated=frames.count>1
    let destination=CGImageDestinationCreateWithURL(URL(fileURLWithPath:job.destination) as CFURL,(animated ? UTType.gif.identifier:UTType.png.identifier) as CFString,frames.count,nil)!
    if animated {CGImageDestinationSetProperties(destination,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)}
    for f in frames {
        precondition(!f.rotated,"Rotated frames require an explicit importer")
        let b=f.frame,s=f.spriteSourceSize
        guard let crop=sheet.cropping(to:CGRect(x:b.x,y:b.y,width:b.w,height:b.h)) else {fatalError("Invalid frame in \(job.image): \(b), image \(sheet.width)x\(sheet.height)")}
        let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(crop,in:CGRect(x:s.x,y:height-s.y-s.h,width:s.w,height:s.h))
        let image=context.makeImage()!
        // The pinned PokéRogue runtime plays Pokémon atlases at 10 FPS.
        let properties:[CFString:Any]=animated ? [kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1,kCGImagePropertyGIFUnclampedDelayTime:0.1]]:[:]
        CGImageDestinationAddImage(destination,image,properties as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination),"Image export failed")
}
print("Exported \(jobs.count) original PokéRogue sprite variants")
