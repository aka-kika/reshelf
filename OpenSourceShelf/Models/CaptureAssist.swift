import Foundation

/// The one AI feature in the app: on-device Apple Intelligence filling use
/// cases, a note, and tags during Quick Capture. On by default, zero setup,
/// nothing leaves the Mac — this key only turns it off.
///
/// (Was LabsFeatures.swift, which also held the v2 Intelligence gate and a
/// `SidebarItem.requiresLabs` helper. Both went with the v2 surfaces; this
/// enum was the only part that ever mattered to the shipping app.)
enum CaptureAssist {
    static let storageKey = "reshelf.captureAssistEnabled"
    /// When on, capture assist runs by itself right after a capture is saved —
    /// no need to open More Details and press Generate.
    static let autoGenerateKey = "reshelf.captureAutoGenerate"
}
