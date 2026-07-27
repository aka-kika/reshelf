import Foundation
import Combine
import Sparkle

/// The app's only contact point with Sparkle. Everything else talks to this type,
/// so swapping or removing the update framework touches exactly one file.
///
/// Update preferences live in Sparkle's own `UserDefaults` keys, read and written
/// through the updater. Deliberately *not* mirrored into `@AppStorage`: a second
/// copy would drift out of sync with what the updater actually does, and the
/// updater is the one that decides.
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    /// Drives the menu item's enabled state — Sparkle refuses overlapping checks.
    @Published private(set) var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }
}
