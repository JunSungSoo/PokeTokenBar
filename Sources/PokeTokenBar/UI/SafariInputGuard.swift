import Foundation

/// Ignores action clicks briefly after a new wild Pokémon appears, since it replaces the Next button under the cursor.
struct SafariInputGuard: Equatable {
    static let duration: TimeInterval = 0.5
    private(set) var lockedUntil: Date?

    mutating func lock(at now: Date) { lockedUntil = now.addingTimeInterval(Self.duration) }

    func accepts(at now: Date) -> Bool { lockedUntil.map { now >= $0 } ?? true }
}
