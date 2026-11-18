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

    // MARK: - Cooldown stamps only after a successful, verified check

    private static func release(_ version: String) -> UpdateRelease {
        UpdateRelease(version: version, size: 1_000, sha256: String(repeating: "a", count: 64))
    }

    @MainActor
    private func isolatedDefaults() -> UserDefaults {
        let suite = "UpdateCheckerTests.check.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// A failed lookup must not start the 30-minute cooldown: otherwise opening the
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
            return Self.release("2.5.5")
        }

        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1)
        XCTAssertEqual(checker.available, Self.release("2.5.5"))

        now = now.addingTimeInterval(60)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 1, "a successful check must honour minInterval")

        now = now.addingTimeInterval(1_800)
        await checker.check(minInterval: 1_800)
        XCTAssertEqual(fetches, 2, "after the cooldown the next check must fetch again")
    }

    func testNormalizedReleaseVersion() {
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("v2.5.5"), "2.5.5")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion("2.5.10"), "2.5.10")
        XCTAssertEqual(UpdateChecker.normalizedReleaseVersion(" V2.05.10\n"), "2.5.10", "trimmed, prefix and leading zeros dropped")
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.6.0-beta.1"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v2.5"))
        XCTAssertNil(UpdateChecker.normalizedReleaseVersion("v1234567890.0.0"), "component would overflow comparisons")
    }

    /// With no early stamp, overlapping popover opens would each hit GitHub. One fetch at a time.
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
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: isolatedDefaults())

        checker.consider(Self.release("2.5.4"))
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))

        checker.skipCurrent()
        XCTAssertNil(checker.available, "the popover banner stays hidden")
        XCTAssertEqual(checker.skipped?.version, "2.5.4")
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"))

        checker.consider(Self.release("2.5.4"))
        XCTAssertNil(checker.available)
        XCTAssertEqual(checker.settingsNotice, .skipped("2.5.4"), "a skipped version is not the latest installed")

        checker.consider(Self.release("2.5.5"))
        XCTAssertEqual(checker.available?.version, "2.5.5")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.5"))

        for installedOrOlder in ["2.5.3", "2.5.0"] {
            checker.consider(Self.release(installedOrOlder))
            XCTAssertEqual(checker.settingsNotice, .current, "\(installedOrOlder) is never offered")
        }
    }

    @MainActor
    func testShowAgainRestoresTheBannerAndUpdateUsesTheSkippedRelease() async {
        var installed: [UpdateRelease] = []
        let checker = UpdateChecker(currentVersion: "2.5.3", defaults: isolatedDefaults(),
                                    install: { release, _ in installed.append(release) })
        checker.consider(Self.release("2.5.4"))
        checker.skipCurrent()
        XCTAssertEqual(checker.updateTarget, Self.release("2.5.4"), "Settings can still install a skipped release")
        await checker.applyUpdate()
        XCTAssertEqual(installed, [Self.release("2.5.4")])

        checker.showSkippedAgain()
        XCTAssertEqual(checker.available?.version, "2.5.4")
        XCTAssertNil(checker.skipped)
        XCTAssertEqual(checker.settingsNotice, .offer("2.5.4"))
    }

    // MARK: - Installing

    @MainActor
    func testUpdateIsRefusedDuringABattleOrTradeWithoutDownloading() async {
        var installs = 0
        var blocked = true
        let checker = UpdateChecker(currentVersion: "3.2.1", defaults: isolatedDefaults(),
                                    install: { _, _ in installs += 1 }, installBlocked: { blocked })
        checker.consider(Self.release("3.3.0"))

        await checker.applyUpdate()
        XCTAssertEqual(installs, 0)
        XCTAssertEqual(checker.installFailure, .busy)
        XCTAssertFalse(checker.isUpdating)

        blocked = false
        await checker.applyUpdate()
        XCTAssertEqual(installs, 1)
        XCTAssertNil(checker.installFailure)
        XCTAssertTrue(checker.isUpdating, "a successful install hands over to the relaunched app")
    }

    @MainActor
    func testFailedInstallReportsAndOffersTheReleasePage() async {
        var opened: [URL] = []
        let checker = UpdateChecker(currentVersion: "3.2.1", defaults: isolatedDefaults(),
                                    openDownload: { opened.append($0) },
                                    install: { _, _ in throw UpdateInstaller.Failure.integrity })
        checker.consider(Self.release("3.3.0"))

        await checker.applyUpdate()
        XCTAssertEqual(checker.installFailure, .failed)
        XCTAssertFalse(checker.isUpdating)

        checker.openReleasePage()
        XCTAssertEqual(opened, [Self.release("3.3.0").pageURL])
    }

    @MainActor
    func testInstallerSeesABattleThatStartsDuringTheDownload() async {
        var blocked = false
        var seenByInstaller: Bool?
        let checker = UpdateChecker(currentVersion: "3.2.1", defaults: isolatedDefaults(),
                                    install: { _, isBlocked in
                                        blocked = true
                                        seenByInstaller = isBlocked()
                                        throw UpdateInstaller.Failure.busy
                                    },
                                    installBlocked: { blocked })
        checker.consider(Self.release("3.3.0"))

        await checker.applyUpdate()
        XCTAssertEqual(seenByInstaller, true, "the installer re-reads the live state before swapping")
        XCTAssertEqual(checker.installFailure, .busy)
        XCTAssertFalse(checker.isUpdating)
    }

    @MainActor
    func testRelaunchFailureAfterTheSwapAsksForARestartAndStopsRetrying() async {
        var installs = 0
        let checker = UpdateChecker(currentVersion: "3.2.1", defaults: isolatedDefaults(),
                                    install: { _, _ in
                                        installs += 1
                                        throw UpdateInstaller.Failure.relaunch
                                    })
        checker.consider(Self.release("3.3.0"))

        await checker.applyUpdate()
        XCTAssertEqual(checker.installFailure, .restartRequired)
        await checker.applyUpdate()
        XCTAssertEqual(installs, 1, "the new version is already on disk; a second swap would fail")
    }

    @MainActor
    func testBusyNoticeClearsOnTheNextCheck() async {
        let checker = UpdateChecker(currentVersion: "3.2.1", defaults: isolatedDefaults(),
                                    fetchLatest: { Self.release("3.3.0") },
                                    install: { _, _ in }, installBlocked: { true })
        await checker.check()
        await checker.applyUpdate()
        XCTAssertEqual(checker.installFailure, .busy)
        await checker.check(minInterval: 0)
        XCTAssertNil(checker.installFailure)
    }

    @MainActor
    func testNoInstallWithoutAnOffer() async {
        var installs = 0
        let checker = UpdateChecker(currentVersion: "3.2.1", defaults: isolatedDefaults(), install: { _, _ in installs += 1 })
        await checker.applyUpdate()
        XCTAssertEqual(installs, 0)
        XCTAssertNil(checker.installFailure)
    }
}
