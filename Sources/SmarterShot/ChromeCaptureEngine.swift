import Foundation

/// The orchestration is tested without launching Chrome or posting input events.
@MainActor enum ChromeCaptureEngine {
    struct Driver {
        var prepare: () async throws -> Void
        var invoke: () async throws -> Int
        var image: (Int) async throws -> Data?
        var cleanup: () async -> Void
    }
    static func capture(driver:Driver, attempts:Int = 160, pause:() async throws -> Void = {
        try await Task.sleep(nanoseconds:150_000_000)
    }) async throws -> Data {
        do {
            try Task.checkCancellation()
            try await driver.prepare()
            try Task.checkCancellation()
            let baseline = try await driver.invoke()
            for _ in 0..<attempts {
                try Task.checkCancellation()
                if let data = try await driver.image(baseline) {
                    try Task.checkCancellation()
                    await driver.cleanup()
                    return data
                }
                try await pause()
            }
            throw ChromeCaptureError.message("Chrome didn’t provide a fresh screenshot. Its download may still be available in Chrome. You can try Scroll Capture instead.")
        } catch {
            await driver.cleanup()
            throw error
        }
    }
}
enum ChromeCaptureError:LocalizedError {
    case message(String)
    var errorDescription:String? { if case .message(let text) = self { return text }; return nil }
}
