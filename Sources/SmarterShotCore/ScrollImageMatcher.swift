import Foundation

/// Vertical translation matching on narrow, full-height grayscale thumbnails.
/// No UI state or text recognition. Dynamic/unrelated frames fail closed.
public enum ScrollImageMatcher {
    public struct Plane {
        public let width:Int, height:Int
        public let pixels:[UInt8]
        public init(width:Int,height:Int,pixels:[UInt8]) { self.width=width; self.height=height; self.pixels=pixels }
    }
    public struct Match { public let advance:Int; public let error:Double }
    public static func match(previous:Plane,current:Plane) -> Match? {
        guard previous.width == current.width,previous.height == current.height,previous.width >= 8,previous.height >= 40,
              previous.pixels.count == previous.width*previous.height,current.pixels.count == current.width*current.height else { return nil }
        let w=previous.width,h=previous.height,edge=max(4,h/10),maxAdvance=h*3/4
        func score(_ dy:Int)->Double {
            let available=h-dy-edge*2
            guard available >= h/14 else { return .infinity }
            var total=0.0,count=0
            for row in stride(from:edge,to:h-dy-edge,by:max(1,available/48)) {
                for x in stride(from:w/10,to:w-w/10,by:max(1,w/24)) {
                    total += abs(Double(previous.pixels[(row+dy)*w+x])-Double(current.pixels[row*w+x]));count += 1
                }
            }
            return total/Double(max(1,count))/255
        }
        var best=0,bestError=Double.infinity
        for dy in stride(from:0,through:maxAdvance,by:1) { let e=score(dy); if e<bestError { best=dy;bestError=e } }
        for dy in max(0,best-3)...min(maxAdvance,best+3) { let e=score(dy); if e<bestError { best=dy;bestError=e } }
        guard bestError < 0.035 else { return nil }
        // Blank/repeated regions cannot establish a trustworthy displacement.
        let rivals=stride(from:0,through:maxAdvance,by:max(2,h/80)).filter { abs($0-best)>max(5,h/100) }.map(score)
        if let rival=rivals.min(),rival-bestError < 0.0015 { return nil }
        return Match(advance:best,error:bestError)
    }
    public static func difference(_ a:Plane,_ b:Plane)->Double {
        guard a.width==b.width,a.height==b.height,a.pixels.count==b.pixels.count else { return .infinity }
        var sum=0.0,count=0
        for i in stride(from:0,to:a.pixels.count,by:max(1,a.pixels.count/12000)) {
            sum += abs(Double(a.pixels[i])-Double(b.pixels[i])); count += 1
        }
        return sum/Double(max(1,count))/255
    }
    /// Retain a sticky footer only at the end of the finished image.
    public static func fixedFooter(previous:Plane,current:Plane)->Int {
        guard previous.width==current.width,previous.height==current.height else { return 0 }
        var rows=0
        for y in stride(from:previous.height-1,through:previous.height*9/10,by:-1) {
            var error=0.0
            for x in 0..<previous.width { error += abs(Double(previous.pixels[y*previous.width+x])-Double(current.pixels[y*previous.width+x])) }
            if error/Double(previous.width)>1.0 { break }
            rows += 1
        }
        return rows
    }
}
