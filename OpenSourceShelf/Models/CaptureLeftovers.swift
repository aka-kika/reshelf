import Foundation

/// What Quick Capture's own fields held when a fetch for another link started.
/// They belong to the previous repo, so the new repo must not keep them; text
/// typed while the fetch ran is the user's and stays.
struct CaptureLeftovers: Equatable {
    var useCases: String
    var notes: String
    var personalNote: String
    var isSelfHosted: Bool
    var isLocalFirst: Bool

    /// The fields after the fetch: a value still equal to the leftover is
    /// cleared, anything changed during the fetch is kept.
    func cleared(from current: CaptureLeftovers) -> CaptureLeftovers {
        CaptureLeftovers(
            useCases: current.useCases == useCases ? "" : current.useCases,
            notes: current.notes == notes ? "" : current.notes,
            personalNote: current.personalNote == personalNote ? "" : current.personalNote,
            isSelfHosted: current.isSelfHosted == isSelfHosted ? false : current.isSelfHosted,
            isLocalFirst: current.isLocalFirst == isLocalFirst ? false : current.isLocalFirst)
    }
}
