import AppKit
import CryptoKit
import Darwin

/// Downloads a verified release and swaps it in; app-downloaded files carry no quarantine flag.
enum UpdateInstaller {
    static let bundleIdentifier = "io.github.chattymin.poketokenbar"
    private static let appName = "PokeTokenBar.app"

    enum Failure: LocalizedError, Equatable {
        case notBundled, notWritable, notNewer, busy, download, integrity, invalidApp, installationChanged, relaunch

        var errorDescription: String? { "Update failed: \(self)" }
    }

    static func verifyArchive(at file: URL, release: UpdateRelease) throws {
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue
        guard size == release.size else { throw Failure.integrity }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == release.sha256 else { throw Failure.integrity }
    }

    /// The archive must hold exactly one validly signed bundle of this app at the signed version.
    static func extractApp(archive: URL, into folder: URL, version: String) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        guard run("/usr/bin/ditto", ["-x", "-k", archive.path, folder.path]) == 0 else { throw Failure.invalidApp }
        let items = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0 != "__MACOSX" }
        guard items == [appName] else { throw Failure.invalidApp }
        let app = folder.appendingPathComponent(appName, isDirectory: true)
        guard try BundleInstallation.exists(app),
              let expected = BundleInstallation.Version(version),
              (try? BundleInstallation.version(at: app, identifier: bundleIdentifier)) == expected else {
            throw Failure.invalidApp
        }
        try BundleInstallation.validateSignature(at: app)
        return app
    }

    /// Only a writable, non-translocated location can be swapped in place.
    static func installTarget(for bundle: URL) throws -> URL {
        let parent = bundle.deletingLastPathComponent()
        guard !bundle.pathComponents.contains("AppTranslocation"), access(parent.path, W_OK) == 0 else {
            throw Failure.notWritable
        }
        return bundle
    }

    /// Stage beside the target, then swap atomically; the staging folder then holds the old bundle and is removed.
    static func replace(target: URL, with app: URL, expectedInstalledVersion: String) throws {
        let parent = target.deletingLastPathComponent()
        let lock = try BundleInstallation.lockDirectory(parent)
        defer { close(lock) }
        guard let expected = BundleInstallation.Version(expectedInstalledVersion),
              (try? BundleInstallation.version(at: target, identifier: bundleIdentifier)) == expected else {
            throw Failure.installationChanged
        }
        let staged = try BundleInstallation.stage(app, in: parent)
        defer { try? FileManager.default.removeItem(at: staged.deletingLastPathComponent()) }
        try BundleInstallation.move(staged, target, replacing: true)
    }

    static func updatesFolder() throws -> URL {
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return caches.appendingPathComponent("PokeTokenBar/Updates", isDirectory: true)
    }

    /// Clears downloads left by an update that ended with the app quitting or crashing.
    static func removeLeftoverDownloads() {
        if let folder = try? updatesFolder() { try? FileManager.default.removeItem(at: folder) }
    }

    /// `isBlocked` is read again just before the swap: a battle or trade may start during the download.
    @MainActor
    static func install(_ release: UpdateRelease, isBlocked: @MainActor () -> Bool) async throws {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard AppEnv.isBundledApp else { throw Failure.notBundled }
        guard UpdateChecker.isNewer(release.version, than: current) else { throw Failure.notNewer }
        let target = try installTarget(for: Bundle.main.bundleURL)
        let work = try workFolder()
        defer { try? FileManager.default.removeItem(at: work) }

        let archive = work.appendingPathComponent("update.zip")
        try await download(release.downloadURL, to: archive)
        let app = try await Task.detached {
            try verifyArchive(at: archive, release: release)
            return try extractApp(archive: archive, into: work.appendingPathComponent("app"), version: release.version)
        }.value
        guard !isBlocked() else { throw Failure.busy }
        try await Task.detached {
            try replace(target: target, with: app, expectedInstalledVersion: current)
        }.value
        // Termination below skips `defer`, so remove the download now.
        try? FileManager.default.removeItem(at: work)
        AppLog.writeAndFlush("update \(current) -> \(release.version) installed; relaunching")
        do {
            try await UpdateRelaunch.launchReplacement(at: target)
        } catch {
            throw Failure.relaunch
        }
        NSApp.terminate(nil)
    }

    private static func workFolder() throws -> URL {
        let folder = try updatesFolder().appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        return folder
    }

    private static func download(_ url: URL, to destination: URL) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30 * 60
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (file, response) = try? await session.download(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw Failure.download }
        try FileManager.default.moveItem(at: file, to: destination)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

/// The relaunched bundle waits for this process to exit; otherwise `SingleInstance` makes it yield.
enum UpdateRelaunch {
    static let argument = "--ptb-wait-for-pid"

    static func arguments(waitingFor processID: Int32) -> [String] { [argument, String(processID)] }

    static func waitPID(in arguments: [String]) -> Int32? {
        guard let index = arguments.firstIndex(of: argument), arguments.indices.contains(index + 1),
              let processID = Int32(arguments[index + 1]), processID > 0 else { return nil }
        return processID
    }

    /// True once the process is gone; false if it is still running after the timeout.
    static func waitForExit(of processID: Int32, timeout: Duration = .seconds(30)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while kill(processID, 0) == 0 || errno == EPERM {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }

    @MainActor
    static func launchReplacement(at target: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments(waitingFor: ProcessInfo.processInfo.processIdentifier)
        let app = try await NSWorkspace.shared.openApplication(at: target, configuration: configuration)
        guard let actual = app.bundleURL, try BundleInstallation.matchesLaunchedBundle(actual, target: target) else {
            throw UpdateInstaller.Failure.relaunch
        }
    }
}
