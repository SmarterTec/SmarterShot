import AppKit
import Sparkle

// Exercise the real updater integration without launching another app bundle,
// starting capture services, or registering another privacy identity.
enum ScreenRecorder {
    static let shared = State()
    final class State { var isRecording = false }
}
try MainActor.assumeIsolated {
_ = NSApplication.shared
let bundle = Bundle(url:URL(fileURLWithPath:CommandLine.arguments[1]))!
let driver = SPUStandardUserDriver(hostBundle:bundle,delegate:nil)
let updater = SPUUpdater(hostBundle:bundle,applicationBundle:bundle,userDriver:driver,delegate:nil)
let integration = AppUpdater()
try integration.updater(updater,mayPerform:.updates)
ScreenRecorder.shared.isRecording = true
var rejected = false
do { try integration.updater(updater,mayPerform:.updates) }
catch { rejected = (error as NSError).localizedDescription.contains("recording") }
assert(rejected,"Update checks must not interrupt recordings")
ScreenRecorder.shared.isRecording = false
try integration.updater(updater,mayPerform:.updates)
// Sparkle itself validates configuration against the finished app bundle.
// The process exits before any scheduled background check can run.
try updater.start()
assert(updater.canCheckForUpdates,"Finished bundle must start a valid updater")
print("Updater integration passed: valid bundle configuration and recording protection.")
}
