import CryptoKit
import XCTest
@testable import PokeTokenBar

final class GitHubUpdateTests: XCTestCase {
    private let signingKey = Curve25519.Signing.PrivateKey()

    private func manifest(version: String = "3.3.0", asset: String? = nil, size: Int = 1_000,
                          sha256: String = String(repeating: "a", count: 64)) -> Data {
        let fields: [String: Any] = ["version": version, "asset": asset ?? "PokeTokenBar-\(version).zip",
                                     "size": size, "sha256": sha256]
        return try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
    }

    private func signature(_ data: Data, key: Curve25519.Signing.PrivateKey? = nil) -> Data {
        Data(try! (key ?? signingKey).signature(for: data).base64EncodedString().utf8)
    }

    private func release(_ data: Data, signature: Data) -> UpdateRelease? {
        GitHubReleaseSource.release(manifest: data, signature: signature,
                                    publicKey: signingKey.publicKey.rawRepresentation)
    }

    // MARK: - Signed manifest

    func testSignedManifestBuildsDownloadAndPageURLsFromTheVersion() throws {
        let data = manifest()
        let verified = try XCTUnwrap(release(data, signature: signature(data)))
        XCTAssertEqual(verified.version, "3.3.0")
        XCTAssertEqual(verified.size, 1_000)
        XCTAssertEqual(verified.downloadURL.absoluteString,
                       "https://github.com/JunSungSoo/PokeTokenBar/releases/download/v3.3.0/PokeTokenBar-3.3.0.zip")
        XCTAssertEqual(verified.pageURL.absoluteString,
                       "https://github.com/JunSungSoo/PokeTokenBar/releases/tag/v3.3.0")
    }

    func testTamperedManifestOrForeignKeyIsRejected() {
        let data = manifest()
        var tampered = data
        tampered[tampered.count / 2] ^= 0x01
        XCTAssertNil(release(tampered, signature: signature(data)), "one changed byte invalidates the signature")
        XCTAssertNil(release(data, signature: signature(data, key: Curve25519.Signing.PrivateKey())))
        XCTAssertNil(release(data, signature: Data("not base64".utf8)))
        XCTAssertNil(release(Data(), signature: signature(Data())))
    }

    func testSignedButUnsafeFieldsAreRejected() {
        let unsafe = [
            manifest(version: "3.3.0-beta.1"), manifest(version: "v3.3.0"), manifest(version: "3.3"),
            manifest(asset: "PokeTokenBar-3.2.0.zip"), manifest(asset: "../PokeTokenBar-3.3.0.zip"),
            manifest(asset: "PokeTokenBar-3.3.0.zip/../x"), manifest(size: 0),
            manifest(size: GitHubReleaseSource.maximumArchiveSize + 1),
            manifest(sha256: String(repeating: "a", count: 63)), manifest(sha256: String(repeating: "g", count: 64)),
        ]
        for data in unsafe {
            XCTAssertNil(release(data, signature: signature(data)), String(decoding: data, as: UTF8.self))
        }
    }

    func testShippedPublicKeyIsAValidEd25519Key() {
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: GitHubReleaseSource.publicKey))
    }

    // MARK: - Archive and bundle verification

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ptb-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            _ = try? Self.run("/bin/chmod", ["-R", "u+w", directory.path])
            try? FileManager.default.removeItem(at: directory)
        }
        return directory
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private func makeApp(at url: URL, identifier: String = UpdateInstaller.bundleIdentifier, version: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: contents.appendingPathComponent("MacOS/PokeTokenBar").path)
        let info: [String: Any] = ["CFBundleExecutable": "PokeTokenBar", "CFBundleIdentifier": identifier,
                                   "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        XCTAssertEqual(try Self.run("/usr/bin/codesign", ["--force", "-s", "-", url.path]), 0)
    }

    private func archive(_ items: [URL], in directory: URL) throws -> URL {
        let staging = directory.appendingPathComponent("zip-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        for item in items { try FileManager.default.moveItem(at: item, to: staging.appendingPathComponent(item.lastPathComponent)) }
        let zip = directory.appendingPathComponent("archive-\(UUID().uuidString).zip")
        XCTAssertEqual(try Self.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", staging.path, zip.path]), 0)
        return zip
    }

    private func describe(_ file: URL, version: String = "3.3.0") throws -> UpdateRelease {
        let data = try Data(contentsOf: file)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return UpdateRelease(version: version, size: data.count, sha256: digest)
    }

    func testArchiveMustMatchTheSignedSizeAndDigest() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("a.zip")
        try Data("archive".utf8).write(to: file)
        let expected = try describe(file)
        XCTAssertNoThrow(try UpdateInstaller.verifyArchive(at: file, release: expected))
        let wrongDigest = UpdateRelease(version: "3.3.0", size: expected.size, sha256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try UpdateInstaller.verifyArchive(at: file, release: wrongDigest))
        let wrongSize = UpdateRelease(version: "3.3.0", size: expected.size + 1, sha256: expected.sha256)
        XCTAssertThrowsError(try UpdateInstaller.verifyArchive(at: file, release: wrongSize))
    }

    func testExtractedAppMustBeTheSignedVersionOfThisApp() throws {
        let directory = try temporaryDirectory()
        let app = directory.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: app, version: "3.3.0")
        let zip = try archive([app], in: directory)
        let extracted = try UpdateInstaller.extractApp(archive: zip, into: directory.appendingPathComponent("out"),
                                                       version: "3.3.0")
        XCTAssertEqual(extracted.lastPathComponent, "PokeTokenBar.app")

        XCTAssertThrowsError(try UpdateInstaller.extractApp(archive: zip, into: directory.appendingPathComponent("older"),
                                                            version: "3.4.0"), "the bundle must carry the signed version")
    }

    func testForeignIdentifierExtraItemsOrBrokenSignatureAreRejected() throws {
        let directory = try temporaryDirectory()
        let foreign = directory.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: foreign, identifier: "com.example.other", version: "3.3.0")
        let foreignZip = try archive([foreign], in: directory)
        XCTAssertThrowsError(try UpdateInstaller.extractApp(archive: foreignZip, into: directory.appendingPathComponent("a"), version: "3.3.0"))

        let app = directory.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: app, version: "3.3.0")
        let extra = directory.appendingPathComponent("extra.txt")
        try Data("x".utf8).write(to: extra)
        let extraZip = try archive([app, extra], in: directory)
        XCTAssertThrowsError(try UpdateInstaller.extractApp(archive: extraZip, into: directory.appendingPathComponent("b"), version: "3.3.0"))

        let broken = directory.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: broken, version: "3.3.0")
        try Data("changed".utf8).write(to: broken.appendingPathComponent("Contents/MacOS/PokeTokenBar"))
        let brokenZip = try archive([broken], in: directory)
        XCTAssertThrowsError(try UpdateInstaller.extractApp(archive: brokenZip, into: directory.appendingPathComponent("c"), version: "3.3.0"))
    }

    // MARK: - Replacement

    func testReplacementSwapsTheBundleAndLeavesNoStagingFolder() throws {
        let directory = try temporaryDirectory()
        let applications = directory.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: applications, withIntermediateDirectories: true)
        let target = applications.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: target, version: "3.2.1")
        let incoming = directory.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: incoming, version: "3.3.0")

        try UpdateInstaller.replace(target: target, with: incoming, expectedInstalledVersion: "3.2.1")

        let info = NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "3.3.0")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: applications.path), ["PokeTokenBar.app"])
    }

    func testReplacementRefusesWhenTheInstalledVersionChanged() throws {
        let directory = try temporaryDirectory()
        let target = directory.appendingPathComponent("Installed/PokeTokenBar.app")
        try makeApp(at: target, version: "3.2.5")
        let incoming = directory.appendingPathComponent("PokeTokenBar.app")
        try makeApp(at: incoming, version: "3.3.0")
        XCTAssertThrowsError(try UpdateInstaller.replace(target: target, with: incoming, expectedInstalledVersion: "3.2.1"))
        let info = NSDictionary(contentsOf: target.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, "3.2.5", "the other installation is left alone")
    }

    func testTranslocatedOrReadOnlyLocationsCannotBeUpdatedInPlace() throws {
        let directory = try temporaryDirectory()
        let writable = directory.appendingPathComponent("PokeTokenBar.app")
        XCTAssertEqual(try UpdateInstaller.installTarget(for: writable), writable)
        // A writable folder, so only the translocation rule can reject it.
        let mount = directory.appendingPathComponent("AppTranslocation/ABC/d")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        XCTAssertThrowsError(try UpdateInstaller.installTarget(for: mount.appendingPathComponent("PokeTokenBar.app")))
        let locked = directory.appendingPathComponent("Locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        XCTAssertThrowsError(try UpdateInstaller.installTarget(for: locked.appendingPathComponent("PokeTokenBar.app")))
    }

    /// Opt-in: the output of `scripts/publish-github-update.sh` passes the app's own checks with the shipped key.
    func testPublishedArtifactsPassTheAppVerificationWithTheShippedKey() throws {
        guard let path = ProcessInfo.processInfo.environment["PTB_UPDATE_ARTIFACTS"] else {
            throw XCTSkip("Set PTB_UPDATE_ARTIFACTS=build/github-update/<version>")
        }
        let folder = URL(fileURLWithPath: path)
        let manifest = try Data(contentsOf: folder.appendingPathComponent(GitHubReleaseSource.manifestName))
        let signature = try Data(contentsOf: folder.appendingPathComponent(GitHubReleaseSource.manifestName + ".sig"))
        let release = try XCTUnwrap(GitHubReleaseSource.release(manifest: manifest, signature: signature))
        let archive = folder.appendingPathComponent(GitHubReleaseSource.assetName(release.version))
        try UpdateInstaller.verifyArchive(at: archive, release: release)
        let app = try UpdateInstaller.extractApp(archive: archive, into: try temporaryDirectory().appendingPathComponent("app"),
                                                 version: release.version)
        XCTAssertTrue(FileManager.default.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/PokeTokenBar").path))
    }

    // MARK: - Relaunch hand-off

    func testRelaunchArgumentRoundTripsOnlyAPositiveProcessID() {
        XCTAssertEqual(UpdateRelaunch.waitPID(in: ["/x"] + UpdateRelaunch.arguments(waitingFor: 4321)), 4321)
        XCTAssertNil(UpdateRelaunch.waitPID(in: ["/x"]))
        XCTAssertNil(UpdateRelaunch.waitPID(in: ["/x", UpdateRelaunch.argument]))
        XCTAssertNil(UpdateRelaunch.waitPID(in: ["/x", UpdateRelaunch.argument, "abc"]))
        XCTAssertNil(UpdateRelaunch.waitPID(in: ["/x", UpdateRelaunch.argument, "0"]))
    }
}
