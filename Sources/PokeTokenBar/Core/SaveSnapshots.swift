import Foundation

/// A point-in-time local snapshot of CompanionState, with summary metadata for listing and rollback.
struct SaveSnapshot: Identifiable, Sendable, Equatable {
    let id: String
    let fileURL: URL
    let date: Date
    let dexCount: Int
    let lifetimeTokens: Int
    let currentSpeciesID: Int?
    let currentIsShiny: Bool
    let currentForm: PokemonForm?
}

enum SaveSnapshotManager {
    static let snapshotPrefix = "companion-snapshot-"
    static let maxSnapshotsToKeep = 10
    static let minAutoSnapshotInterval: TimeInterval = 12 * 3600 // 12 hours between auto-snapshots

    static var defaultDeviceName: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    static var defaultAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.5.0"
    }

    /// Directory where local snapshots are stored: `<stateDir>/.snapshots/<stateFileName>/`
    static func snapshotsDirectory(for stateURL: URL) -> URL {
        let dir = stateURL.deletingLastPathComponent()
            .appendingPathComponent(".snapshots")
            .appendingPathComponent(stateURL.lastPathComponent, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a snapshot filename for the given timestamp.
    static func snapshotFileName(date: Date) -> String {
        "\(snapshotPrefix)\(secondStamp(date)).json"
    }

    private static func secondStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: date)
    }

    private static func parseStamp(_ filename: String) -> Date? {
        guard filename.hasPrefix(snapshotPrefix) && filename.hasSuffix(".json") else { return nil }
        var raw = String(filename.dropFirst(snapshotPrefix.count).dropLast(".json".count))
        if let dash = raw.lastIndex(of: "-"), let _ = Int(raw[raw.index(after: dash)...]) {
            raw = String(raw[..<dash])
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.date(from: raw)
    }

    /// Lists all available snapshots in chronological order (newest first).
    static func listSnapshots(for stateFileURL: URL) -> [SaveSnapshot] {
        let dir = snapshotsDirectory(for: stateFileURL)
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
            return []
        }

        var results: [SaveSnapshot] = []
        var current: [String: SnapshotSummaryCache.Entry] = [:]
        for file in files where file.hasPrefix(snapshotPrefix) && file.hasSuffix(".json") {
            let url = dir.appendingPathComponent(file)
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let version = SnapshotSummaryCache.Version(size: values?.fileSize, modified: values?.contentModificationDate)
            if let cached = summaryCache.snapshot(path: url.path, version: version) {
                results.append(cached)
                current[url.path] = .init(version: version, snapshot: cached)
                continue
            }
            guard let data = try? Data(contentsOf: url) else { continue }
            let countBefore = results.count
            if let envelope = try? SaveTransfer.decode(data) {
                let st = envelope.state
                results.append(SaveSnapshot(
                    id: file,
                    fileURL: url,
                    date: envelope.exportedAt,
                    dexCount: st.dex.count,
                    lifetimeTokens: st.usedSinceInstall,
                    currentSpeciesID: st.active?.currentID,
                    currentIsShiny: st.active?.displaysShiny ?? false,
                    currentForm: st.active.flatMap { PokemonForm.resolved(speciesID: $0.currentID, form: $0.form) }
                ))
            } else if let st = try? JSONDecoder().decode(CompanionState.self, from: data) {
                let date = parseStamp(file) ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
                results.append(SaveSnapshot(
                    id: file,
                    fileURL: url,
                    date: date,
                    dexCount: st.dex.count,
                    lifetimeTokens: st.usedSinceInstall,
                    currentSpeciesID: st.active?.currentID,
                    currentIsShiny: st.active?.displaysShiny ?? false,
                    currentForm: st.active.flatMap { PokemonForm.resolved(speciesID: $0.currentID, form: $0.form) }
                ))
            }
            if results.count > countBefore, let decoded = results.last {
                current[url.path] = .init(version: version, snapshot: decoded)
            }
        }

        summaryCache.replace(directory: dir.path, with: current)
        return results.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id > $1.id
        }
    }

    /// Settings lists snapshots on every open; decoding each multi-hundred-KB save took ~100ms on the main thread.
    private static let summaryCache = SnapshotSummaryCache()

    /// Loads and returns the SaveEnvelope from a snapshot file.
    static func loadEnvelope(from url: URL) throws -> SaveEnvelope {
        let data = try Data(contentsOf: url)
        if let envelope = try? SaveTransfer.decode(data) {
            return envelope
        }
        if let st = try? JSONDecoder().decode(CompanionState.self, from: data) {
            let date = parseStamp(url.lastPathComponent)
                ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
                ?? Date()
            return SaveEnvelope(
                format: SaveEnvelope.formatID,
                schema: SaveEnvelope.schemaVersion,
                appVersion: defaultAppVersion,
                exportedAt: date,
                sourceDevice: defaultDeviceName,
                state: SaveTransfer.sanitized(st)
            )
        }
        throw SaveTransferError.notASaveFile
    }

    /// Loads sanitized CompanionState from a snapshot file.
    static func loadState(from url: URL) -> CompanionState? {
        try? loadEnvelope(from: url).state
    }

    /// Creates a snapshot from the current CompanionState and saves it into the snapshots directory.
    @discardableResult
    static func createSnapshot(
        state: CompanionState,
        for stateFileURL: URL,
        date: Date,
        appVersion: String = defaultAppVersion,
        deviceName: String = defaultDeviceName
    ) throws -> SaveSnapshot {
        let dir = snapshotsDirectory(for: stateFileURL)
        let filename = snapshotFileName(date: date)
        var targetURL = dir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let base = filename.dropLast(".json".count)
            var counter = 1
            while FileManager.default.fileExists(atPath: dir.appendingPathComponent("\(base)-\(counter).json").path) {
                counter += 1
            }
            targetURL = dir.appendingPathComponent("\(base)-\(counter).json")
        }
        let data = try SaveTransfer.encode(state: state, appVersion: appVersion, deviceName: deviceName, now: date)
        try data.write(to: targetURL, options: .atomic)
        pruneOldSnapshots(for: stateFileURL)
        return SaveSnapshot(
            id: targetURL.lastPathComponent,
            fileURL: targetURL,
            date: date,
            dexCount: state.dex.count,
            lifetimeTokens: state.usedSinceInstall,
            currentSpeciesID: state.active?.currentID,
            currentIsShiny: state.active?.displaysShiny ?? false,
            currentForm: state.active.flatMap { PokemonForm.resolved(speciesID: $0.currentID, form: $0.form) }
        )
    }

    /// Prunes snapshots keeping only the newest `maxSnapshotsToKeep`.
    static func pruneOldSnapshots(for stateFileURL: URL) {
        let snapshots = listSnapshots(for: stateFileURL)
        guard snapshots.count > maxSnapshotsToKeep else { return }
        for old in snapshots.dropFirst(maxSnapshotsToKeep) {
            try? FileManager.default.removeItem(at: old.fileURL)
        }
    }

    /// Returns the most recent valid snapshot, if any.
    static func latestSnapshot(for stateFileURL: URL) -> SaveSnapshot? {
        listSnapshots(for: stateFileURL).first
    }

    /// Loads the latest valid snapshot as CompanionState, if available.
    static func loadLatestValidSnapshot(for stateFileURL: URL) -> CompanionState? {
        guard let latest = latestSnapshot(for: stateFileURL) else { return nil }
        return loadState(from: latest.fileURL)
    }
}

/// Snapshot summaries per file, valid while the file's size and modification date stay the same.
final class SnapshotSummaryCache: @unchecked Sendable {
    struct Version: Equatable {
        let size: Int?
        let modified: Date?
    }
    struct Entry {
        let version: Version
        let snapshot: SaveSnapshot
    }

    private let lock = NSLock()
    private var directories: [String: [String: Entry]] = [:]

    func snapshot(path: String, version: Version) -> SaveSnapshot? {
        // A file without size or date cannot prove it is unchanged.
        guard version.size != nil, version.modified != nil else { return nil }
        let directory = (path as NSString).deletingLastPathComponent
        return lock.withLock {
            guard let entry = directories[directory]?[path], entry.version == version else { return nil }
            return entry.snapshot
        }
    }

    /// Keeps only the files present in the latest listing, so deleted snapshots leave the cache.
    func replace(directory: String, with entries: [String: Entry]) {
        lock.withLock { directories[directory] = entries }
    }
}
