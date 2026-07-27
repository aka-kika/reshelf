import Foundation

/// Parses the ISO-8601 timestamps GitHub returns (`pushed_at`, `updated_at`) and
/// the ones `git log --format=%cI` prints. One shared formatter: `ISO8601DateFormatter`
/// is expensive to build and this runs once per repo during a backfill over
/// hundreds of rows.
enum GitHubDate {
    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Same, but tolerating fractional seconds — some APIs include them, and a
    /// formatter configured without the option rejects those strings outright.
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        return formatter.date(from: string) ?? fractionalFormatter.date(from: string)
    }
}
