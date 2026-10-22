import AppKit
import SmarterShotCore

var failures = 0
func check(_ value:Bool,_ text:String) { print("\(value ? "PASS" : "FAIL"): \(text)"); if !value { failures += 1 } }
// An asymmetric, deterministic document proves orientation and every stitch pixel.
let width = 96, viewHeight = 240, documentHeight = 910
func row(_ y:Int,_ x:Int)->UInt8 {
    var v = UInt64(y*width+x+1);v = (v ^ (v >> 16)) &* 0x45d9f3b;v = (v ^ (v >> 16)) &* 0x45d9f3b
    return UInt8(truncatingIfNeeded:v ^ (v >> 16))
}
func image(offset:Int,footer:Int=0)->CGImage {
    let pixels = (0..<viewHeight).flatMap { y in (0..<width).map { x in y>=viewHeight-footer ? UInt8(33) : row(y+offset,x) } }
    let provider = CGDataProvider(data:Data(pixels) as CFData)!
    return CGImage(width:width,height:viewHeight,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:width,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:0),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
}
@MainActor func run() async {
    do {
        let a = try ScrollCaptureEngine.plane(image(offset:0)), b = try ScrollCaptureEngine.plane(image(offset:71))
        check(ScrollImageMatcher.match(previous:a,current:b)?.advance == 71,"odd pixel translation and correct image orientation")
        check(ScrollImageMatcher.match(previous:a,current:try ScrollCaptureEngine.plane(image(offset:5000))) == nil,"unrelated pages rejected")
        let blank = ScrollImageMatcher.Plane(width:width,height:viewHeight,pixels:[UInt8](repeating:255,count:width*viewHeight))
        check(ScrollImageMatcher.match(previous:blank,current:blank) == nil,"ambiguous blank overlap rejected")
        let fa = try ScrollCaptureEngine.plane(image(offset:0,footer:12)),fb = try ScrollCaptureEngine.plane(image(offset:71,footer:12))
        check(ScrollImageMatcher.fixedFooter(previous:fa,current:fb) == 12,"sticky footer recognized")
        var position = 0.0, sections = 0, restored = 0
        let (result,didRestore) = try await ScrollCaptureEngine.restoring(restore:{ position=0.37;restored += 1;return true },operation:{
            try await ScrollCaptureEngine.capture(snapshot:{ image(offset:Int((position*Double(documentHeight-viewHeight)).rounded())) },
                setPosition:{ position=$0 },positionValue:{ position },update:{ sections=$0 })
        })
        check(didRestore && restored == 1 && position == 0.37,"original position restored once after success")
        check(result.width == width && result.height == documentHeight && sections>2,"full document dimensions and multiple sections")
        let final = try ScrollCaptureEngine.plane(result)
        let expected = (0..<documentHeight).flatMap { y in (0..<width).map { row(y,$0) } }
        // RGB conversion may alter grayscale slightly; geometry must be exact.
        let errors = zip(final.pixels,expected).filter { abs(Int($0)-Int($1))>2 }.count
        check(errors == 0,"all stitched pixels preserve document order without duplicate or missing rows")
        let footerHeight = 12
        position = 0
        let footerResult = try await ScrollCaptureEngine.capture(snapshot:{ image(offset:Int((position*Double(documentHeight-viewHeight)).rounded()),footer:footerHeight) },setPosition:{position=$0},positionValue:{position},update:{_ in})
        check(footerResult.height == documentHeight,"sticky footer retained once at final edge")
        let footerPixels = try ScrollCaptureEngine.plane(footerResult).pixels
        check(zip(footerPixels.prefix((documentHeight-footerHeight)*width),expected).allSatisfy { abs(Int($0)-Int($1))<=2 },"sticky footer never covers intermediate content")
        position=0.4;restored=0
        do {
            _ = try await ScrollCaptureEngine.restoring(restore:{position=0.4;restored += 1;return true},operation:{
                try await ScrollCaptureEngine.capture(snapshot:{image(offset:Int((position*670).rounded()))},setPosition:{position=$0},positionValue:{position},pixelLimit:10,update:{_ in})
            })
            check(false,"size limit must stop capture")
        } catch { check(restored == 1 && position == 0.4,"size limit fails without output and restores position") }
        position=0
        do {
            _ = try await ScrollCaptureEngine.capture(snapshot:{image(offset:Int((position*670).rounded()))},setPosition:{position=$0},positionValue:{position},maxSections:2,update:{_ in})
            check(false,"section limit must stop incomplete capture")
        } catch { check(true,"section limit rejects incomplete output") }
        do {
            _ = try await ScrollCaptureEngine.capture(snapshot:{image(offset:0)},setPosition:{_ in},positionValue:{0.5},update:{_ in})
            check(false,"failure to reach page top must be rejected")
        } catch { check(true,"failed scroll-to-top cannot silently save a partial page") }
        restored=0
        do {
            _ = try await ScrollCaptureEngine.restoring(restore:{restored += 1;return true},operation:{
                try await ScrollCaptureEngine.capture(snapshot:{throw NSError(domain:"Snapshot unavailable",code:1)},setPosition:{_ in},positionValue:{0},update:{_ in})
            })
            check(false,"snapshot failure must throw")
        } catch { check(restored == 1,"snapshot failures restore original position") }
        let (_, restoreFailed) = try await ScrollCaptureEngine.restoring(restore:{false},operation:{42})
        check(!restoreFailed,"restore failure is reported to caller")
        restored=0
        let task=Task { @MainActor in
            try await ScrollCaptureEngine.restoring(restore:{restored += 1;return true},operation:{
                try await ScrollCaptureEngine.capture(snapshot:{image(offset:0)},setPosition:{_ in},positionValue:{0},update:{_ in})
            })
        }
        task.cancel()
        do { _ = try await task.value;check(false,"cancel must throw") }
        catch is CancellationError { check(restored == 1,"cancellation restores before completion") }
        catch { check(false,"unexpected cancellation error: \(error)") }
    } catch { check(false,"unexpected error: \(error)") }
}
Task { @MainActor in await run();exit(failures == 0 ? 0 : 1) }
dispatchMain()
