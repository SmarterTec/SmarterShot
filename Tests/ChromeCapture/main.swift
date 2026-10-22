import Foundation

@main struct Tests {
    @MainActor static func main() async throws {
        var cleaned=0,invoked=0,polls=0
        var driver=ChromeCaptureEngine.Driver(prepare:{},invoke:{invoked+=1;return 17},image:{ baseline in
            precondition(baseline==17);polls+=1
            return polls==3 ? Data([1,2,3]) : nil
        },cleanup:{cleaned+=1})
        let image=try await ChromeCaptureEngine.capture(driver:driver,pause:{})
        precondition(image==Data([1,2,3]) && invoked==1 && polls==3 && cleaned==1)
        print("PASS fresh image waits; exact baseline; one cleanup")
        cleaned=0;invoked=0
        driver.prepare={throw ChromeCaptureError.message("Wrong tab")}
        do { _=try await ChromeCaptureEngine.capture(driver:driver,pause:{});fatalError("accepted wrong tab") } catch {}
        precondition(invoked==0 && cleaned==1)
        print("PASS failed preparation never invokes capture; cleanup runs")
        cleaned=0
        driver.prepare={};driver.invoke={throw ChromeCaptureError.message("Unverified command")}
        driver.image={_ in fatalError("image read after unsafe command")}
        do { _=try await ChromeCaptureEngine.capture(driver:driver,pause:{});fatalError("unsafe command") } catch {}
        precondition(cleaned==1)
        print("PASS command failure never reads clipboard")
        cleaned=0;polls=0
        driver.invoke={17};driver.image={_ in polls+=1;return nil}
        do { _=try await ChromeCaptureEngine.capture(driver:driver,attempts:3,pause:{});fatalError("accepted stale clipboard") } catch {}
        precondition(cleaned==1 && polls==3)
        print("PASS bounded stale clipboard timeout; no scrolling fallback")
        cleaned=0
        driver.image={_ in throw ChromeCaptureError.message("invalid image")}
        do { _=try await ChromeCaptureEngine.capture(driver:driver,pause:{});fatalError("accepted invalid image") } catch {}
        precondition(cleaned==1)
        print("PASS invalid image cleanup")
        cleaned=0;invoked=0
        driver.prepare={try await Task.sleep(nanoseconds:10_000_000_000)}
        let cancelDriver=driver
        let task=Task { try await ChromeCaptureEngine.capture(driver:cancelDriver,pause:{}) }
        task.cancel()
        do { _=try await task.value;fatalError("cancellation ignored") } catch is CancellationError {} catch {fatalError("unexpected error")}
        precondition(cleaned==1 && invoked==0)
        print("PASS cancellation cleans up without command")
    }
}
