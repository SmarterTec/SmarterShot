import AppKit
import Sparkle

/// Sparkle owns download verification, installation, and relaunch. Updates
/// come from signed assets in this repository's GitHub Releases.
@MainActor
final class AppUpdater: NSObject, SPUUpdaterDelegate {
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var waitingForRecording: Timer?

    var automaticallyChecks: Bool { controller.updater.automaticallyChecksForUpdates }
    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func start() { controller.startUpdater() }
    func check() { controller.checkForUpdates(nil) }
    func toggleAutomaticChecks() {
        controller.updater.automaticallyChecksForUpdates.toggle()
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if ScreenRecorder.shared.isRecording {
            throw NSError(domain: "SmarterShot.Updates", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Finish your screen recording before checking for updates."
            ])
        }
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard ScreenRecorder.shared.isRecording else { return false }
        // A recording may have started while the update downloaded. Wait for
        // its file to finish writing; never stop it just to install an update.
        waitingForRecording?.invalidate()
        waitingForRecording = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard !ScreenRecorder.shared.isRecording else { return }
                timer.invalidate()
                self?.waitingForRecording = nil
                installHandler()
            }
        }
        return true
    }
}
