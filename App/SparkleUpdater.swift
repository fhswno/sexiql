import Foundation

@MainActor
final class SparkleUpdater {
    static let shared = SparkleUpdater()

    static let feedURLString = ""

    private init() {}

    func configureIfEnabled() {
        guard !Self.feedURLString.isEmpty,
              let url = URL(string: Self.feedURLString) else { return }
        #if SPARKLE
        _ = url
        #endif
    }
}
