import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateController: NSObject, ObservableObject {
    enum ConfigurationState {
        case ready
        case localBuild
    }

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var configurationState: ConfigurationState = .localBuild

    private var updaterController: SPUStandardUpdaterController?
    private var canCheckObservation: NSKeyValueObservation?

    override init() {
        super.init()

        guard Self.hasSparkleConfiguration(in: .main) else {
            return
        }

        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController = controller
        configurationState = .ready
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            Task { @MainActor in
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    private static func hasSparkleConfiguration(in bundle: Bundle) -> Bool {
        let feedURL = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String
        let publicKey = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String

        return !(feedURL?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            && !(publicKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}
