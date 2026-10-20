import AppKit
import SwiftData

/// Every catalog save goes through here. They used to be `try? save()` at 29
/// places, so a failed save (full disk, a store problem) looked like success
/// on screen and the change was gone after relaunch. A failure now shows one
/// alert saying what wasn't saved; callers that can retry (the sheets) also
/// stay open.
enum CatalogSave {
    @discardableResult
    static func save(_ context: ModelContext, _ what: String = "your latest change") -> Bool {
        do {
            try context.save()
            return true
        } catch {
            report(error, what: what)
            return false
        }
    }

    /// One alert at a time: a batch of failing saves shouldn't stack dialogs.
    private static var alertShowing = false

    static func report(_ error: Error, what: String) {
        DispatchQueue.main.async {
            guard !alertShowing else { return }
            alertShowing = true
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Couldn't save \(what)"
            alert.informativeText = """
            reshelf couldn't write to its catalog file, so this change may be gone after you quit. \
            Check that the disk has free space, then try again.

            Error: \(error.localizedDescription)
            """
            alert.addButton(withTitle: "OK")
            alert.runModal()
            alertShowing = false
        }
    }
}
