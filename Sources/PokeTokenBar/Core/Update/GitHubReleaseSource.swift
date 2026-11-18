import CryptoKit
import Foundation

/// One release whose manifest passed signature verification.
struct UpdateRelease: Equatable, Sendable {
    let version: String
    let size: Int
    let sha256: String

    var downloadURL: URL {
        GitHubReleaseSource.releasesURL.appendingPathComponent("download/v\(version)/\(GitHubReleaseSource.assetName(version))")
    }
    var pageURL: URL { GitHubReleaseSource.releasesURL.appendingPathComponent("tag/v\(version)") }
}

/// Fork GitHub Releases, trusted only via the signed manifest; download URLs come from the signed version.
enum GitHubReleaseSource {
    static let releasesURL = URL(string: "https://github.com/JunSungSoo/PokeTokenBar/releases")!
    /// Changing this key requires re-signing with `scripts/update-signing-key.sh`; installed apps trust only this one.
    static let publicKey = Data(base64Encoded: "C/cGzOI7dmh4kVMKZSX33pHYWEJ7eWt82AgIiffLL8c=")!
    static let manifestName = "PokeTokenBar-update.json"
    static let maximumArchiveSize = 600 * 1_024 * 1_024
    private static let maximumMetadataSize = 64 * 1_024

    static func assetName(_ version: String) -> String { "PokeTokenBar-\(version).zip" }

    private struct Manifest: Decodable {
        let version: String
        let asset: String
        let size: Int
        let sha256: String
    }

    static func release(manifest: Data, signature: Data, publicKey: Data = publicKey) -> UpdateRelease? {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey),
              let text = String(data: signature, encoding: .utf8),
              let signatureBytes = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(signatureBytes, for: manifest),
              let fields = try? JSONDecoder().decode(Manifest.self, from: manifest),
              UpdateChecker.normalizedReleaseVersion(fields.version) == fields.version,
              fields.asset == assetName(fields.version),
              (1...maximumArchiveSize).contains(fields.size),
              fields.sha256.count == 64,
              fields.sha256.allSatisfy({ $0.isHexDigit && ($0.isNumber || $0.isLowercase) }) else { return nil }
        return UpdateRelease(version: fields.version, size: fields.size, sha256: fields.sha256)
    }

    static func fetch() async -> UpdateRelease? {
        let latest = releasesURL.appendingPathComponent("latest/download")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let manifest = await metadata(latest.appendingPathComponent(manifestName), session: session),
              let signature = await metadata(latest.appendingPathComponent(manifestName + ".sig"), session: session)
        else { return nil }
        return release(manifest: manifest, signature: signature)
    }

    private static func metadata(_ url: URL, session: URLSession) async -> Data? {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https" else { return nil }
        var data = Data()
        do {
            for try await byte in bytes {
                guard data.count < maximumMetadataSize, !Task.isCancelled else { return nil }
                data.append(byte)
            }
        } catch { return nil }
        return data
    }
}
