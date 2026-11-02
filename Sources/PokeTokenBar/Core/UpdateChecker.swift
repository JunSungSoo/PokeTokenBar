import AppKit
import Observation

/// Compare the installed app version with the ZIP version on the pinned Drive share.
@MainActor
@Observable
final class UpdateChecker {
    struct Available: Equatable { let version: String; let url: String }

    /// What Settings should say after a check. A skipped release is not "up to date".
    enum SettingsNotice: Equatable {
        case offer(String)
        case skipped(String)
        case current
    }

    /// Version + pinned Drive URL from the public filename (or a test double).
    struct LatestRelease: Equatable, Sendable {
        let tag: String
        let url: String
    }

    private(set) var available: Available?
    /// Newer release the user chose to skip. Hidden from the banner, still shown in Settings.
    private(set) var skipped: Available?
    private(set) var isUpdating = false

    let currentVersion: String
    private let clock: () -> Date
    private let defaults: UserDefaults
    /// Injected so tests can fail or succeed without hitting the network.
    private let fetchLatest: () async -> LatestRelease?
    private var lastChecked: Date?
    private let openDownload:(URL)->Void
    /// Overlapping popover opens must not stack concurrent Drive calls once the early
    /// cooldown stamp is gone (a failed check no longer blocks the next attempt).
    private var checkInFlight = false

    static let skippedVersionKey = "skippedDriveUpdateVersion"

    init(currentVersion: String? = nil, clock: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard,
         fetchLatest: (() async -> LatestRelease?)? = nil,
         openDownload:@escaping (URL)->Void = {NSWorkspace.shared.open($0)}) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.defaults = defaults
        self.fetchLatest = fetchLatest ?? { await DriveReleaseSource.fetch() }
        self.openDownload=openDownload
    }

    var settingsNotice: SettingsNotice {
        if let available { return .offer(available.version) }
        if let skipped { return .skipped(skipped.version) }
        return .current
    }

    /// Release Settings can install. A skip hides the banner; it does not throw the URL away.
    var updateTarget: Available? { available ?? skipped }

    /// 최신 릴리스 조회. 스킵한 버전은 배너(`available`)에 안 올리고 Settings(`skipped`)에만 남긴다.
    /// minInterval 은 **성공한** 조회 사이에만 적용한다(레이트리밋 보호). 실패 — 네트워크·비정상 응답·
    /// 불안전 URL·지원하지 않는 태그 — 는 쿨다운을 시작하지 않아, 팝오버를 다시 열면 곧장 재시도한다.
    func check(minInterval: TimeInterval = 1800) async {
        if checkInFlight { return }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        checkInFlight = true
        defer { checkInFlight = false }

        guard let release = await fetchLatest(),
              Self.isTrustedReleaseURL(release.url),
              let version = Self.normalizedReleaseVersion(release.tag) else { return }
        lastChecked = clock()
        consider(latest: version, url: release.url)
    }

    /// Only the configured public Drive file is an update destination.
    nonisolated static func isTrustedReleaseURL(_ string:String)->Bool {
        string == DriveReleaseSource.shareURL.absoluteString
    }

    /// Release tag → comparable version, or nil when the tag is not a plain `MAJOR.MINOR.PATCH`
    /// (optionally `v`-prefixed). `isNewer` reads non-numeric parts as 0, so a prerelease such as
    /// `v2.6.0-beta.1` would compare equal to `2.6.0` and garbage would compare as `0.0.0`; neither
    /// may be applied or counted as a successful check.
    nonisolated static func normalizedReleaseVersion(_ tag: String) -> String? {
        var version = Substring(tag.trimmingCharacters(in: .whitespacesAndNewlines))
        if version.first == "v" || version.first == "V" { version = version.dropFirst() }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts.allSatisfy({ part in
                  !part.isEmpty && part.count <= 9 && part.allSatisfy { $0.isASCII && $0.isNumber }
              }) else { return nil }
        return parts.map { String(Int($0)!) }.joined(separator: ".")
    }

    /// Apply one fetched release. `latest` may be a tag (`v2.5.4`) or a bare version.
    func consider(latest tag: String, url: String) {
        let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        let skippedVersion = defaults.string(forKey: Self.skippedVersionKey)
        guard Self.isNewer(latest, than: currentVersion) else {
            available = nil
            skipped = nil
            return
        }
        let release = Available(version: latest, url: url)
        if latest == skippedVersion {
            available = nil
            skipped = release
        } else {
            available = release
            skipped = nil
        }
    }

    /// Hide the banner for this version. Settings can still see it and install it.
    func skipCurrent() {
        guard let release = available else { return }
        defaults.set(release.version, forKey: Self.skippedVersionKey)
        skipped = release
        available = nil
    }

    /// Undo a skip so the banner can show the same release again.
    func showSkippedAgain() {
        defaults.removeObject(forKey: Self.skippedVersionKey)
        if let release = skipped {
            available = release
            skipped = nil
        }
    }

    /// Open the download page in the default browser; never run brew or replace a live app.
    func applyUpdate() {
        guard updateTarget != nil,!isUpdating else{return}
        openDownload(DriveReleaseSource.shareURL)
    }

    // MARK: 버전 비교

    /// a 가 b 보다 높은 semver 인가. ("2.0.10" > "2.0.9" 등 숫자 비교)
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

}
