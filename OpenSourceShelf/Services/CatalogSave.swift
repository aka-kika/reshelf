import AppKit
import SwiftData

/// Every catalog save goes through here. They used to be `try? save()` at 29
/// places, so a failed save (full disk, a store problem) looked like success
/// on screen and the change was gone after relaunch. A failure now shows one
/// alert saying what wasn't saved; callers that can retry (the sheets) also
/// stay open.
enum CatalogSave {
    /// Tests set this to make every save fail with it, without an alert.
    /// The app never sets it.
    static var failureForTesting: Error?

    @discardableResult
    static func save(_ context: ModelContext, _ what: String = "your latest change") -> Bool {
        do {
            if let failureForTesting { throw failureForTesting }
            try context.save()
            // Shelf moves, tags, notes and folder edits do not change the
            // project count, so the list's count observer never saw them.
            // Every successful save schedules the same 2-second snapshot.
            scheduleBackup(from: context)
            return true
        } catch {
            report(error, what: what)
            return false
        }
    }

    /// `scheduleSnapshot` is main-actor. Saves from the UI are already there;
    /// a save from a background queue hops across before touching the context.
    private static func scheduleBackup(from context: ModelContext) {
        let hop = {
            MainActor.assumeIsolated {
                CatalogBackupService.scheduleSnapshot(from: context)
            }
        }
        if Thread.isMainThread {
            hop()
        } else {
            DispatchQueue.main.async(execute: hop)
        }
    }

    /// One alert at a time: a batch of failing saves shouldn't stack dialogs.
    private static var alertShowing = false

    static func report(_ error: Error, what: String) {
        guard failureForTesting == nil else { return }
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
            // A sheet on the front window, not runModal: a save can fail from
            // async code while a SwiftUI sheet is up, and a nested modal loop
            // there could freeze the window. The front window can be that sheet.
            if let window = NSApp.keyWindow ?? NSApp.mainWindow, window.isVisible {
                alert.beginSheetModal(for: window) { _ in alertShowing = false }
            } else {
                alert.runModal()
                alertShowing = false
            }
        }
    }
}
