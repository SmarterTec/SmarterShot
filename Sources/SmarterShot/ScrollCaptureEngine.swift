import CoreGraphics
import Foundation
import SmarterShotCore

/// Shared production stitching pipeline; injected frames and scrolling make
/// seam correctness, limits and cancellation independently testable.
@MainActor enum ScrollCaptureEngine {
    struct Failure: LocalizedError {
        let text: String
        static func message(_ text:String)->Failure { Failure(text:text) }
        var errorDescription:String? { text }
    }
    static func restoring<T>(restore: () async -> Bool, operation: () async throws -> T) async throws -> (T,Bool) {
        do { let result = try await operation(); return (result,await restore()) }
        catch { _ = await restore(); throw error }
    }
    static func capture(snapshot: () async throws -> CGImage,
                        setPosition: (Double) async throws -> Void,
                        positionValue: () async throws -> Double,
                        maxSections:Int = 100, pixelLimit:Int = 40_000_000, timeLimit:Double = 60,
                        update:(Int)->Void) async throws -> CGImage {
        try Task.checkCancellation()
        let start=Date()
        func checkedSnapshot() async throws -> CGImage {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(start)<timeLimit else { throw Failure.message("The page did not finish within one minute. Infinite feeds may not have an end.") }
            return try await snapshot()
        }
        func settled() async throws -> CGImage {
            try await Task.sleep(nanoseconds:100_000_000)
            var previous=try await checkedSnapshot()
            for _ in 0..<10 {
                try await Task.sleep(nanoseconds:80_000_000)
                let next=try await checkedSnapshot()
                if ScrollImageMatcher.difference(try plane(previous),try plane(next))<0.003 { return next }
                previous=next
            }
            throw Failure.message("The page keeps changing. Pause animations or loading content, then try again.")
        }
        try await setPosition(0)
        let first=try await settled()
        guard try await positionValue() <= 0.000001 else { throw Failure.message("This app did not scroll to the beginning. No incomplete image was saved.") }
        var oldPlane=try plane(first),position=0.0,step=0.01,footer:Int?=nil
        var tiles:[CGImage]=[],totalHeight=0
        func append(_ image:CGImage,y:Int,height:Int) throws {
            guard height>0 else { return }
            guard (totalHeight+height)*first.width<=pixelLimit else { throw Failure.message("This page exceeds the capture size limit. Capture a smaller section instead.") }
            guard let crop=image.cropping(to:CGRect(x:0,y:y,width:image.width,height:height)),let owned=copy(crop) else { throw Failure.message("The page image couldn’t be assembled.") }
            tiles.append(owned);totalHeight += height
        }
        update(1)
        for count in 2...maxSections {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(start)<timeLimit else { throw Failure.message("The page did not finish within one minute. Infinite feeds may not have an end.") }
            var accepted: (CGImage,ScrollImageMatcher.Plane,Int,Double)?
            for _ in 0..<9 {
                let requested=min(1,position+step)
                try await setPosition(requested)
                let next=try await settled(),nextPlane=try plane(next)
                let actual=try await positionValue()
                if actual<=position+0.0000001 {
                    if requested>=1 { break }
                    step=min(1-position,step*2);continue
                }
                if let match=ScrollImageMatcher.match(previous:oldPlane,current:nextPlane),match.advance>0 {
                    accepted=(next,nextPlane,match.advance,actual);break
                }
                step /= 2
                guard step>=0.000001 else { break }
            }
            guard let (next,nextPlane,advance,actual)=accepted else { throw Failure.message("This app’s scrolling content couldn’t be aligned reliably. No incomplete image was saved.") }
            if footer==nil {
                footer=ScrollImageMatcher.fixedFooter(previous:oldPlane,current:nextPlane)
                try append(first,y:0,height:first.height-footer!)
            }
            let fixed=footer ?? 0
            try append(next,y:next.height-fixed-advance,height:advance)
            step=min(0.25,max(0.000001,(actual-position)*Double(first.height)*0.62/Double(advance)))
            oldPlane=nextPlane;position=actual;update(count)
            if position>=0.999999 {
                try append(next,y:next.height-fixed,height:fixed)
                return try assemble(tiles,width:first.width,height:totalHeight)
            }
        }
        throw Failure.message("This page is too long or keeps adding content. Capture a smaller section instead.")
    }
    /// Browser fallback when overlay scrollbars are absent from Accessibility.
    /// Record actual pixel displacements, then visually verify restoration.
    static func captureRelative(snapshot:@escaping () async throws -> CGImage,
                                scroll:@escaping (Int) async throws -> Void,
                                pixelsPerPoint:Double,
                                maxSections:Int=100,pixelLimit:Int=40_000_000,timeLimit:Double=60,
                                willRestore:()->Void = {},onRestoreFailure:()->Void,update:(Int)->Void) async throws -> CGImage {
        let start=Date()
        func stable(ignoreDeadline:Bool=false) async throws -> CGImage {
            try Task.checkCancellation()
            if !ignoreDeadline && Date().timeIntervalSince(start)>=timeLimit { throw Failure.message("This page took too long to capture.") }
            try await Task.sleep(nanoseconds:100_000_000)
            var previous=try await snapshot()
            for _ in 0..<10 {
                try await Task.sleep(nanoseconds:80_000_000)
                let next=try await snapshot()
                if difference(previous,next)<0.003 { return next };previous=next
            }
            throw Failure.message("The page keeps changing. Pause animations or loading content, then try again.")
        }
        func difference(_ a:CGImage,_ b:CGImage)->Double {
            guard let x=try? plane(a),let y=try? plane(b) else { return .infinity }
            return ScrollImageMatcher.difference(x,y)
        }
        let original=try await stable()
        var current=original,position=0.0
        let scale=max(0.1,pixelsPerPoint),step=max(1,Int(Double(original.height)*0.62/scale))
        func move(_ points:Int) async throws -> Int {
            try Task.checkCancellation()
            let previous=current,oldPosition=position
            try await scroll(points)
            position += Double(points)*scale // Restore if capture fails after a delivered scroll.
            let next=try await stable()
            if difference(previous,next)<0.00005 { position=oldPosition;current=next;return 0 }
            let a=try plane(points>0 ? previous : next),b=try plane(points>0 ? next : previous)
            guard let match=ScrollImageMatcher.match(previous:a,current:b),match.advance>0 else { throw Failure.message("This page’s scrolling sections couldn’t be aligned reliably. No incomplete image was saved.") }
            position=oldPosition+Double(points>0 ? match.advance : -match.advance)
            current=next
            return match.advance
        }
        func restore() async -> Bool {
            willRestore()
            // An unstructured task completes cleanup even after capture cancellation.
            return await Task { @MainActor in
                do {
                    for _ in 0..<4 {
                        if abs(position)>0.1 { try await scroll(Int((-position/scale).rounded())) }
                        let restored=try await stable(ignoreDeadline:true)
                        if difference(original,restored)<0.003 { position=0;return true }
                        let a=try plane(original),b=try plane(restored)
                        // Ignore small visual changes (hover, clocks, fading
                        // scrollbars) when content is aligned at zero offset.
                        let forward=ScrollImageMatcher.match(previous:a,current:b)
                        let backward=ScrollImageMatcher.match(previous:b,current:a)
                        let tolerance=max(2,Int(scale.rounded()))
                        if forward.map({$0.advance<=tolerance}) == true || backward.map({$0.advance<=tolerance}) == true { position=0;return true }
                        if let match=forward { position=Double(match.advance) }
                        else if let match=backward { position = -Double(match.advance) }
                        else { return false }
                    }
                } catch { return false }
                return false
            }.value
        }
        do {
            var reachedTop=false
            for _ in 0..<maxSections {
                if try await move(-step)==0 { reachedTop=true;break }
            }
            guard reachedTop else { throw Failure.message("The beginning of this page could not be reached within the capture limit.") }
            let first=current
            var previous=first,tiles:[CGImage]=[],totalHeight=0,footer:Int?=nil
            func append(_ image:CGImage,y:Int,height:Int) throws {
                guard height>0 else { return }
                guard (totalHeight+height)*first.width<=pixelLimit,
                      let crop=image.cropping(to:CGRect(x:0,y:y,width:image.width,height:height)),let owned=copy(crop) else { throw Failure.message("This page exceeds the capture size limit or could not be assembled.") }
                tiles.append(owned);totalHeight += height
            }
            update(1)
            for count in 2...maxSections {
                let advance=try await move(step)
                if advance==0 {
                    // Confirm an edge with a second deliberate scroll.
                    guard try await move(step)==0 else { throw Failure.message("The page changed while checking its end. Please try again after loading finishes.") }
                    guard !tiles.isEmpty else { throw Failure.message("No off-screen content was detected in this area.") }
                    let fixed=footer ?? 0
                    try append(previous,y:previous.height-fixed,height:fixed)
                    let result=try assemble(tiles,width:first.width,height:totalHeight)
                    if !(await restore()) { onRestoreFailure() }
                    return result
                }
                if footer==nil {
                    footer=ScrollImageMatcher.fixedFooter(previous:try plane(first),current:try plane(current))
                    try append(first,y:0,height:first.height-footer!)
                }
                let fixed=footer ?? 0
                try append(current,y:current.height-fixed-advance,height:advance)
                previous=current;update(count)
            }
            throw Failure.message("This page is too long or keeps adding content. Capture a smaller section instead.")
        } catch {
            if !(await restore()) { onRestoreFailure() }
            throw error
        }
    }
    static func plane(_ image:CGImage) throws -> ScrollImageMatcher.Plane {
        let width=min(96,image.width),height=image.height
        var data=[UInt8](repeating:0,count:width*height)
        let success=data.withUnsafeMutableBytes { bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height));return true
        }
        guard success else { throw Failure.message("Not enough memory to compare capture frames.") }
        return .init(width:width,height:height,pixels:data)
    }
    private static func copy(_ image:CGImage)->CGImage? {
        guard let context=CGContext(data:nil,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height));return context.makeImage()
    }
    private static func assemble(_ tiles:[CGImage],width:Int,height:Int) throws -> CGImage {
        guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.message("Not enough memory to assemble the page.") }
        var y=height
        for tile in tiles { y -= tile.height;context.draw(tile,in:CGRect(x:0,y:y,width:width,height:tile.height)) }
        guard let result=context.makeImage() else { throw Failure.message("The full page image couldn’t be assembled.") };return result
    }
}
