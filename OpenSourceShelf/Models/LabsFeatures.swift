import Foundation

/// Optional intelligence surfaces (Compare, Ecosystems, etc.) — off by default for v1.
enum LabsFeatures {
    static let storageKey = "reshelf.labsFeaturesEnabled"
}

/// The one AI feature in the main app: on-device Apple Intelligence filling
/// use cases, a note, and tags during Quick Capture. On by default, zero setup,
/// independent of Labs — this key only turns the capture assist off.
enum CaptureAssist {
    static let storageKey = "reshelf.captureAssistEnabled"
    /// When on, capture assist runs by itself right after a capture is saved —
    /// no need to open More Details and press Generate.
    static let autoGenerateKey = "reshelf.captureAutoGenerate"
}

extension SidebarItem {
    /// Discovery / compare surfaces that stay hidden until Labs is enabled in Settings.
    var requiresLabs: Bool {
        switch self {
        case .compare, .ecosystems, .workflows, .myStack:
            return true
        default:
            return false
        }
    }
}
