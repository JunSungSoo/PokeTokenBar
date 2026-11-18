import AppKit
import Observation

/// Compare the installed app version with the signed manifest on GitHub Releases and install on request.
@MainActor
@Observable
final class UpdateChecker {
    typealias Available = UpdateRelease

    /// What Settings should say after a check. A skipped release is not "up to date".
    enum SettingsNotice: Equatable {
        case offer(String)
        case skipped(String)
        case current
    }

    /// Why the last install attempt did not finish.
    enum InstallFailure: Equatable {
        case busy
        case failed
        /// The new bundle is installed but could not be started; a second swap would fail.
        case restartRequired
    }

    private(set) var available: Available?
    /// Newer release the user chose to skip. Hidden from the banner, still shown in Settings.
    private(set) var skipped: Available?
    private(set) var isUpdating = false
    private(set) var installFailure: InstallFailure?

    let currentVersion: String
    private let clock: () -> Date
    private let defaults: UserDefaults
    /// Injected so tests can fail or succeed without hitting the network.
    private let fetchLatest: () async -> UpdateRelease?
    private var lastChecked: Date?
    private let openDownload: (URL) -> Void
    private let install: @MainActor (UpdateRelease, @escaping @MainActor () -> Bool) async throws -> Void
    private let installBlocked: @MainActor () -> Bool
    /// Overlapping popover opens must not stack concurrent requests once the early
    /// cooldown stamp is gone (a failed check no longer blocks the next attempt).
    private var checkInFlight = false

    static let skippedVersionKey = "skippedGitHubUpdateVersion"

    init(currentVersion: String? = nil, clock: @escaping () -> Date = Date.init, defaults: UserDefaults = .standard,
         fetchLatest: (() async -> UpdateRelease?)? = nil,
         openDownload: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         install: @escaping @MainActor (UpdateRelease, @escaping @MainActor () -> Bool) async throws -> Void = {
             try await UpdateInstaller.install($0, isBlocked: $1)
         },
         installBlocked: @escaping @MainActor () -> Bool = { false }) {
        self.currentVersion = currentVersion
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
        self.clock = clock
        self.defaults = defaults
        self.fetchLatest = fetchLatest ?? { await GitHubReleaseSource.fetch() }
        self.openDownload = openDownload
        self.install = install
        self.installBlocked = installBlocked
    }

    var settingsNotice: SettingsNotice {
        if let available { return .offer(available.version) }
        if let skipped { return .skipped(skipped.version) }
        return .current
    }

    /// Release Settings can install. A skip hides the banner; it does not throw the release away.
    var updateTarget: Available? { available ?? skipped }

    /// 최신 릴리스 조회. 스킵한 버전은 배너(`available`)에 안 올리고 Settings(`skipped`)에만 남긴다.
    /// minInterval 은 **성공한** 조회 사이에만 적용한다(레이트리밋 보호). 실패 — 네트워크·서명 불일치·
    /// 지원하지 않는 버전 — 는 쿨다운을 시작하지 않아, 팝오버를 다시 열면 곧장 재시도한다.
    func check(minInterval: TimeInterval = 1800) async {
        if checkInFlight { return }
        if installFailure == .busy { installFailure = nil }
        if let last = lastChecked, clock().timeIntervalSince(last) < minInterval { return }
        checkInFlight = true
        defer { checkInFlight = false }

        guard let release = await fetchLatest() else { return }
        lastChecked = clock()
        consider(release)
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

    /// Apply one verified release.
    func consider(_ release: UpdateRelease) {
        guard Self.isNewer(release.version, than: currentVersion) else {
            available = nil
            skipped = nil
            return
        }
        if release.version == defaults.string(forKey: Self.skippedVersionKey) {
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

    /// Download, verify and swap in the release; on success the relaunched app takes over.
    func applyUpdate() async {
        guard let target = updateTarget, !isUpdating, installFailure != .restartRequired else { return }
        guard !installBlocked() else {
            installFailure = .busy
            return
        }
        installFailure = nil
        isUpdating = true
        do {
            try await install(target, installBlocked)
        } catch {
            AppLog.write("update \(target.version) failed: \(error)")
            switch error as? UpdateInstaller.Failure {
            case .busy: installFailure = .busy
            case .relaunch: installFailure = .restartRequired
            default: installFailure = .failed
            }
            isUpdating = false
        }
    }

    /// Manual fallback when the in-place install cannot finish.
    func openReleasePage() {
        openDownload(updateTarget?.pageURL ?? GitHubReleaseSource.releasesURL)
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
