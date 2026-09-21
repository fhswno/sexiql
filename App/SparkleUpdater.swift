import Foundation
import Sparkle

@MainActor
final class SparkleUpdater: NSObject, ObservableObject {
    static let shared = SparkleUpdater()

    private let controller: SPUStandardUpdaterController

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    override private init() {
        UserDefaults.standard.register(defaults: [
            "SUEnableAutomaticChecks": true,
            "SUScheduledCheckInterval": 86400.0,
        ])
        let delegate = TestFeedURLDelegate()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: delegate,
            userDriverDelegate: nil
        )
        controller.updater.automaticallyDownloadsUpdates = true
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
}

final class TestFeedURLDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "SUFeedURL")
    }
}
