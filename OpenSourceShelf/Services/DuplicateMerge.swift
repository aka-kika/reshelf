import Foundation

/// Remove Duplicate Repos keeps one copy of each repo. What a person typed or
/// chose on a dropped copy must not vanish with it, so it moves to the kept
/// one first: tags and use cases are joined, notes that differ are both kept
/// (one after the other), and empty fields are filled. Nothing the kept copy
/// already has is overwritten.
enum DuplicateMerge {
    static func merge(from victim: ToolProject, into keeper: ToolProject) {
        keeper.tags = union(keeper.tags, victim.tags)
        keeper.useCases = union(keeper.useCases, victim.useCases)
        keeper.personalNote = joined(keeper.personalNote, victim.personalNote)
        keeper.notes = joined(keeper.notes, victim.notes)
        if keeper.folderID == nil { keeper.folderID = victim.folderID }
        if keeper.longDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keeper.longDescription = victim.longDescription
        }
        if keeper.shortDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            keeper.shortDescription = victim.shortDescription
        }
        if keeper.websiteURL.trimmingCharacters(in: .whitespaces).isEmpty {
            keeper.websiteURL = victim.websiteURL
        }
        if keeper.license.trimmingCharacters(in: .whitespaces).isEmpty {
            keeper.license = victim.license
        }
        // A flag set on either copy stays set. Never turn one off.
        if victim.isLocalFirst { keeper.isLocalFirst = true }
        if victim.isSelfHosted { keeper.isSelfHosted = true }
    }

    /// Higher = keep. A higher shelf wins, then richer data, then the flags.
    /// The list uses this so the copy you invested in survives.
    static func keepScore(_ p: ToolProject) -> Int {
        var score = 0
        switch p.status {
        case .topShelf: score += 3000
        case .collector: score += 2000
        case .yardSale: score += 1000
        }
        if !p.personalNote.isEmpty { score += 60 }
        if !p.notes.isEmpty { score += 50 }
        if p.folderID != nil { score += 40 }
        score += min(p.tags.count, 20)
        score += min(p.useCases.count, 20) * 2
        if !p.longDescription.isEmpty { score += 20 }
        if !p.websiteURL.isEmpty { score += 10 }
        if !p.license.isEmpty { score += 5 }
        if p.lastCheckedDate != nil { score += 10 }
        if p.isLocalFirst { score += 15 }
        if p.isSelfHosted { score += 15 }
        return score
    }

    /// Kept order first, then the dropped copy's new entries; case-insensitive.
    static func union(_ kept: [String], _ dropped: [String]) -> [String] {
        var seen = Set(kept.map { $0.lowercased() })
        var result = kept
        for item in dropped where seen.insert(item.lowercased()).inserted {
            result.append(item)
        }
        return result
    }

    /// Both texts when they differ; one when the other is empty or already
    /// contains it.
    static func joined(_ kept: String, _ dropped: String) -> String {
        let a = kept.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = dropped.trimmingCharacters(in: .whitespacesAndNewlines)
        if b.isEmpty || a.contains(b) { return kept }
        if a.isEmpty || b.contains(a) { return dropped }
        return kept + "\n\n" + dropped
    }
}
