import XCTest
@testable import PokeTokenBar

final class UpdateCheckerTests: XCTestCase {
    func testNewerPatch() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.2", than: "2.0.1"))
    }
    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.1", than: "2.0.1"))
    }
    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("2.0.0", than: "2.0.1"))
        XCTAssertFalse(UpdateChecker.isNewer("2.0.9", than: "2.1.0"))
    }
    func testNumericNotLexical() {
        // "2.0.10" 은 "2.0.9" 보다 높다 (문자열 비교면 반대로 틀림)
        XCTAssertTrue(UpdateChecker.isNewer("2.0.10", than: "2.0.9"))
    }
    func testMinorAndMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("2.1.0", than: "2.0.9"))
        XCTAssertTrue(UpdateChecker.isNewer("3.0.0", than: "2.9.9"))
    }
    func testDifferentComponentCounts() {
        XCTAssertTrue(UpdateChecker.isNewer("2.0.1", than: "2.0"))   // 2.0.1 > 2.0.0
        XCTAssertFalse(UpdateChecker.isNewer("2.0", than: "2.0.0"))  // 동일
    }

    // MARK: - Cooldown stamps only after a successful, validated check

    private static let releaseURL = DriveReleaseSource.shareURL.absoluteString

    @MainActor
    private func isolatedDefaults() -> UserDefaults {
        let suite = "UpdateCheckerTests.check.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// A failed Drive lookup must not start the 30-minute cooldown: otherwise opening the
    /// popover again stays silent until the timer expires, even though no release was seen.
    @MainActor
    func testFailedCheckDoesNotStartTheCooldown() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return nil
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertNil(checker.available)

        now = now.addingTimeInterval(5)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "a failed check must not suppress the next attempt")
    }

    @MainActor
    func testSuccessfulCheckStartsTheCooldownAndAppliesTheRelease() async {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { now }, defaults: isolatedDefaults()) {
            fetches += 1
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: Self.releaseURL)
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertEqual(checker.available?.url, Self.releaseURL)

        now = now.addingTimeInterval(60)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1, "a successful check must honour minInterval")

        now = now.addingTimeInterval(1_800)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "after the cooldown the next check must fetch again")
    }

    @MainActor
    func testRejectedReleaseUrlDoesNotStartTheCooldown() async {
        var fetches = 0
        let checker = UpdateChecker(currentVersion: "2.5.3", clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                    defaults: isolatedDefaults()) {
            fetches += 1
            return UpdateChecker.LatestRelease(tag: "v2.5.5", url: "http://evil.example/x")
        }

        await checker.check(minInterval: 1_800)
        XCTAssertNil(checker.available)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "an unsafe URL is a failed check, not a cooldown start")
    }

    /// Malformed tags and unsupported prerelease tags are failed checks: nothing is applied, and the
    /// very next attempt fetches again and applies a valid release instead of waiting 30 minutes.
    @MainActor
    func testMalformedOrPrereleaseTagIsAFailedCheckAndDoesNotBlockTheNextOne() async {
        let badTags = ["", "latest", "v", "v2.5", "2.5.5.1", "v2..5", "2.5.x", "release-2.5.5", "v 2.5.5",
                       "v2.6.0-beta.1", "2.6.0-rc1", "v2.6.0+build.5", "v2.6.0.beta", "v-2.6.0",
                       "v1234567890.0.0", "v٢.٥.٥"]
        for bad in badTags {
            var tag = bad
            var fetches = 0
            let checker = UpdateChecker(currentVersion: "2.5.3", clock: { Date(timeIntervalSince1970: 1_700_000_000) },
                                        defaults: isolatedDefaults()) {
                fetches += 1
                return UpdateChecker.LatestRelease(tag: tag, url: Self.releaseURL)
            }

            await checker.check(minInterval: 1_800)
            XCTAssertNil(checker.available, "\(bad.debugDescription) must not be offered")
            XCTAssertEqual(checker.settingsNotice, .current, "\(bad.debugDescription)")

            tag = "v2.5.5"
            await checker.check(minInterval: 1_800)
            XCTAssertEqual(fetches, 2, "\(bad.debugDescription) must not start the cooldown")
            XCTAssertEqual(checker.available?.version, "2.5.5", "the next valid release applies at once")
        }
    }

    func testNormalizedReleaseVersion() {
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("v2.5.5"), "2.5.5")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("2.5.10"), "2.5.10")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion(" V2.05.10\n"), "2.5.10", "trimmed, prefix and leading zeros dropped")
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.6.0-beta.1"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.5"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v1234567890.0.0"), "component would overflow comparisons")
    }

    /// With no early stamp, overlapping popover opens would each hit Drive. One fetch at a time.
    @MainActor
    func testOverlappingChecksShareOneFetch() async {
        var fetches = 0
        var release: CheckedContinuation<Void, Never>?
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: isolatedDefaults()) {
            fetches += 1
            if fetches == 1 { await withCheckedContinuation { release = $0 } }
            return nil
        }
        let first = Task { await checker.check(minInterval: 1_800) }
        while release == nil { await Task.yield() }
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1, "a check while one is in flight returns without fetching")

        release?.resume()
        await first.value
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "once the in-flight check finished (failed), the next one fetches")
    }

    /// "Skip this version" hides the banner, but a later check must still know
    /// the release exists. Settings must not treat that as "already latest".
    @MainActor
    func testSkippedReleaseStaysVisibleAndANewerOneReturnsToTheBanner() {
        let suite = "UpdateCheckerTests.skip.\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        defer { box.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: box)

        checker.consider(latest: "2.5.4", url: DriveReleaseSource.shareURL.absoluteString)
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))

        checker.skipCurrent()
        XCTAssertNil(checker.available, "the popover banner stays hidden")
        XCTAssertEqual(checker.skipped?.version, "2.5.4")
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"))
        XCTAssertEqual(box.string(forKey: UpdateChecker.skippedVersionKey), "2.5.4")

        checker.consider(latest: "v2.5.4", url: DriveReleaseSource.shareURL.absoluteString)
        XCTAssertNil(checker.available)
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"), "a skipped version is not the latest installed")

        checker.consider(latest: "2.5.5", url: DriveReleaseSource.shareURL.absoluteString)
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.5"))

        checker.consider(latest: "2.5.3", url: DriveReleaseSource.shareURL.absoluteString)
        XCTAssertEqual(checker.settingsNotice, .current, "the installed release is the latest")
    }

    @MainActor
    func testShowAgainRestoresTheBannerAndUpdateUsesTheSkippedRelease() {
        let suite = "UpdateCheckerTests.restore.\(UUID().uuidString)"
        let box = UserDefaults(suiteName: suite)!
        defer { box.removePersistentDomain(forName: suite) }
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: box)
        let url = DriveReleaseSource.shareURL.absoluteString
        checker.consider(latest: "2.5.4", url: url)
        checker.skipCurrent()

        XCTAssertEqual(checker.updateTarget?.url, url, "Settings can still install a skipped release")

        checker.showSkippedAgain()
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertNil(box.string(forKey: UpdateChecker.skippedVersionKey))
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))
    }

    @MainActor func testDriveVersionOfferClearsOnInstallAndButtonAlwaysOpensPinnedShare()async {
        let defaults=isolatedDefaults();defaults.set("3.0.1",forKey:"skippedUpdateVersion")
        var opened:[URL]=[]
        let checker=UpdateChecker(currentVersion:"3.0.0",defaults:defaults,fetchLatest:{.init(tag:"3.0.1",url:DriveReleaseSource.shareURL.absoluteString)},openDownload:{opened.append($0)})
        await checker.check();XCTAssertEqual(checker.available?.version,"3.0.1","Old GitHub skip must not hide Drive updates")
        checker.applyUpdate();XCTAssertEqual(opened,[DriveReleaseSource.shareURL]);XCTAssertFalse(checker.isUpdating)
        let installed=UpdateChecker(currentVersion:"3.0.1",defaults:defaults,fetchLatest:{.init(tag:"3.0.1",url:DriveReleaseSource.shareURL.absoluteString)})
        await installed.check();XCTAssertNil(installed.available)
        for other in ["2.5.6","3.0.0"]{checker.consider(latest:other,url:DriveReleaseSource.shareURL.absoluteString);XCTAssertNil(checker.available)}
    }
    func testDriveDestinationMustBeTheSpecificSharedFile() {
        XCTAssertTrue(UpdateChecker.isTrustedReleaseURL(DriveReleaseSource.shareURL.absoluteString))
        for url in ["https://github.com/chattymin/PokeTokenBar/releases/latest","https://drive.google.com/file/d/other/view","https://drive.google.com.evil.test/file/d/1NYVOMV8fMqf-UGM-dIfKZ3wKV4PtITrN/view","http://drive.google.com/file/d/1NYVOMV8fMqf-UGM-dIfKZ3wKV4PtITrN/view"]{XCTAssertFalse(UpdateChecker.isTrustedReleaseURL(url))}
    }

}
