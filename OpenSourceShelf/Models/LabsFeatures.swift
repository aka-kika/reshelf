import Foundation

/// Optional intelligence surfaces (Compare, Ecosystems, etc.) — off by default for v1.
enum LabsFeatures {
    static let storageKey = "reshelf.labsFeaturesEnabled"
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
