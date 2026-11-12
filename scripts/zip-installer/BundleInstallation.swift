import Darwin
import Foundation
import Security

enum BundleInstallation {
    enum Failure: LocalizedError {
        case invalidBundle(URL), invalidSignature(URL), busy, didNotQuit, rollback(URL)
        case newerVersionRunning, installationChanged, unexpectedLaunch(URL, URL?)

        var errorDescription: String? {
            switch self {
            case .invalidBundle(let url): "Invalid app bundle: \(url.path)"
            case .invalidSignature(let url): "App signature verification failed: \(url.path)"
            case .busy: "Another installation is in progress. Try again when it finishes."
            case .newerVersionRunning: "A newer PokeTokenBar version is running. Quit it before installing this version."
            case .installationChanged: "The installed app changed during installation. Please try again."
            case .unexpectedLaunch(let expected, let actual): "macOS opened a different app. Expected: \(expected.path). Opened: \(actual?.path ?? "unknown")."
            case .didNotQuit: "PokeTokenBar is still running. Finish any active battle or trade, then try again."
            case .rollback(let backup): "Could not restore the previous app. It is available at \(backup.path)."
            }
        }
    }

    struct Version: Comparable {
        let components: [Int]

        init?(_ value: String) {
            let parts = value.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 3 else { return nil }
            let components = parts.compactMap { part in
                part.allSatisfy { $0.isASCII && $0.isNumber } ? Int(part) : nil
            }
            guard components.count == 3 else { return nil }
            self.components = components
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.components.lexicographicallyPrecedes(rhs.components)
        }
    }

    static func keepsInstalledVersion(_ installed: Version, incoming: Version, reinstallSameVersion: Bool) -> Bool {
        installed > incoming || (installed == incoming && !reinstallSameVersion)
    }

    static func version(at url: URL, identifier: String) throws -> Version {
        let file = url.appendingPathComponent("Contents/Info.plist")
        let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil)
        guard let info = info as? [String: Any],
              info["CFBundleIdentifier"] as? String == identifier,
              let text = info["CFBundleShortVersionString"] as? String,
              let version = Version(text) else { throw Failure.invalidBundle(url) }
        return version
    }

    static func validateSignature(at url: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckNestedCode), nil)
                == errSecSuccess else { throw Failure.invalidSignature(url) }
    }

    static func matchesLaunchedBundle(_ actual: URL, target: URL) throws -> Bool {
        var actualInfo = stat(), targetInfo = stat()
        if stat(actual.path, &actualInfo) == 0, stat(target.path, &targetInfo) == 0,
           actualInfo.st_dev == targetInfo.st_dev, actualInfo.st_ino == targetInfo.st_ino { return true }
        // Gatekeeper can virtualize a quarantined app into a read-only AppTranslocation mount.
        // Accept that mount only when both full signatures validate and their code identities match.
        guard actual.pathComponents.contains("AppTranslocation") else { return false }
        try validateSignature(at: actual)
        try validateSignature(at: target)
        return try codeIdentity(at: actual) == codeIdentity(at: target)
    }

    private static func codeIdentity(at url: URL) throws -> Data {
        var code: SecStaticCode?, information: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let info = information as? [String: Any], let identity = info[kSecCodeInfoUnique as String] as? Data
        else { throw Failure.invalidSignature(url) }
        return identity
    }

    static func exists(_ url: URL) throws -> Bool {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            guard (info.st_mode & S_IFMT) == S_IFDIR else { throw Failure.invalidBundle(url) }
            return true
        }
        if errno == ENOENT { return false }
        throw posixError(url)
    }

    static func lockDirectory(_ directory: URL) throws -> Int32 {
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { throw posixError(directory) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(fd)
            if failure == EWOULDBLOCK || failure == EAGAIN { throw Failure.busy }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure), userInfo: [NSFilePathErrorKey: directory.path])
        }
        return fd
    }

    static func stage(_ source: URL, in parent: URL) throws -> URL {
        let folder = parent.appendingPathComponent(".poketokenbar-install-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        let copy = folder.appendingPathComponent("PokeTokenBar.app", isDirectory: true)
        do {
            // Preserve symlinks, executable modes and macOS bundle metadata.
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = [source.path, copy.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw Failure.invalidBundle(source) }
            try validateSignature(at: copy)
            return copy
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    static func move(_ from: URL, _ to: URL, replacing: Bool) throws {
        let flags = replacing ? RENAME_SWAP : RENAME_EXCL
        guard renameatx_np(AT_FDCWD, from.path, AT_FDCWD, to.path, UInt32(flags)) == 0 else {
            throw posixError(to)
        }
    }

    private static func posixError(_ url: URL) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
}
