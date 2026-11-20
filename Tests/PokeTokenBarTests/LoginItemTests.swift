import ServiceManagement
import XCTest
@testable import PokeTokenBar

final class LoginItemTests: XCTestCase {
    @MainActor
    func testEnablingRegistersMainAppWithoutOpeningSettings() throws {
        let main = Service(.notRegistered)
        let legacy = Service(.notRegistered)
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {
            XCTFail("An enabled login item does not require settings")
        }

        try item.setEnabled(true)

        XCTAssertEqual(item.status, .enabled)
        XCTAssertEqual(main.registrations, 1)
        XCTAssertEqual(legacy.registrations, 0)
    }

    @MainActor
    func testApprovalRetiresUnsafeAgentButKeepsBundleAgentUntilActivated() throws {
        let main = Service(.notRegistered, afterRegistration: .requiresApproval)
        let absolute = Service(.enabled)
        let bundle = Service(.enabled)
        var settingsOpens = 0
        let item = LoginItem(mainApp: main, legacyAgent: absolute, launchedByLegacyAgent: false,
                             bundleAgent: bundle) { settingsOpens += 1 }

        try item.setEnabled(true)
        try item.setEnabled(true)
        XCTAssertEqual(item.status, .requiresApproval)
        XCTAssertEqual(settingsOpens, 2)
        XCTAssertEqual(main.registrations, 1)
        XCTAssertEqual(absolute.status, .notRegistered)
        XCTAssertEqual(bundle.status, .enabled)
        XCTAssertTrue(item.isEnabled)

        main.status = .enabled
        try item.removeLegacyAgentAfterActivation()
        XCTAssertEqual(bundle.status, .notRegistered)
    }

    @MainActor
    func testStartupMigratesBundleAgentAndDefersRemovingItsOwnJob() {
        let main = Service(.notRegistered)
        let absolute = Service(.enabled)
        let bundle = Service(.enabled)
        let owned = LoginItem(mainApp: main, legacyAgent: absolute, launchedByLegacyAgent: false,
                              bundleAgent: bundle, launchedByBundleAgent: true) {}
        owned.migrateFromLegacyAgentIfNeeded()
        XCTAssertEqual(main.registrations, 1)
        XCTAssertEqual(absolute.status, .notRegistered)
        XCTAssertEqual(bundle.status, .enabled)

        let regular = LoginItem(mainApp: main, legacyAgent: absolute, launchedByLegacyAgent: false,
                                bundleAgent: bundle) {}
        regular.migrateFromLegacyAgentIfNeeded()
        regular.migrateFromLegacyAgentIfNeeded()
        XCTAssertEqual(bundle.status, .notRegistered)
        XCTAssertEqual(main.registrations, 1)
    }

    @MainActor
    func testFailedDirectRegistrationStillRetiresAbsolutePathAgent() {
        let main = Service(.notRegistered, failsRegistration: true)
        let absolute = Service(.enabled)
        let item = LoginItem(mainApp: main, legacyAgent: absolute, launchedByLegacyAgent: false) {}
        item.migrateFromLegacyAgentIfNeeded()
        XCTAssertEqual(main.registrations, 1)
        XCTAssertEqual(absolute.status, .notRegistered)
    }

    func testNewerAppCanIdentifyAnOlderRunningCopy() {
        XCTAssertTrue(SingleInstance.isOlderVersion("2.5.5", than: "3.0.9"))
        XCTAssertTrue(SingleInstance.isOlderVersion("3.0.9", than: "3.0.10"))
        XCTAssertFalse(SingleInstance.isOlderVersion("3.0.10", than: "3.0.9"))
        XCTAssertFalse(SingleInstance.isOlderVersion("3.0.9", than: "3.0.9"))
        XCTAssertFalse(SingleInstance.isOlderVersion(nil, than: "3.0.9"))
    }

    @MainActor
    func testStartupMigratesEnabledLegacyAgentButDoesNotOverrideRevokedConsent() {
        for previous in [SMAppService.Status.enabled, .requiresApproval, .notRegistered] {
            let main = Service(.notRegistered)
            let legacy = Service(previous)
            let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {
                XCTFail("Startup should not open System Settings")
            }

            item.migrateFromLegacyAgentIfNeeded()
            item.migrateFromLegacyAgentIfNeeded()

            XCTAssertEqual(item.status, previous == .enabled ? .enabled : .notRegistered)
            XCTAssertEqual(legacy.status, previous == .enabled ? .notRegistered : previous)
            XCTAssertEqual(main.registrations, previous == .enabled ? 1 : 0)
        }
    }

    @MainActor
    func testMigrationDefersUnregisteringTheAgentThatLaunchedThisProcess() {
        let main = Service(.notRegistered)
        let legacy = Service(.enabled)
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: true) {}

        item.migrateFromLegacyAgentIfNeeded()

        XCTAssertEqual(item.status, .enabled)
        XCTAssertEqual(legacy.status, .enabled)
    }

    @MainActor
    func testDisablingClearsLegacyRegistrationSoNextLaunchStaysOff() throws {
        let main = Service(.requiresApproval)
        let legacy = Service(.enabled)
        let item = LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false) {}

        try item.setEnabled(false)
        item.migrateFromLegacyAgentIfNeeded()

        XCTAssertEqual(item.status, .notRegistered)
        XCTAssertEqual(legacy.status, .notRegistered)
        XCTAssertFalse(item.isEnabled)
    }

    @MainActor
    func testSettingsStateIsQueriedOffTheMainThreadAndRetiresTheBundleAgent() async {
        let threads = ThreadLog()
        let main = Service(.enabled, threads: threads)
        let legacy = Service(.notRegistered, threads: threads)
        let bundle = Service(.enabled, threads: threads)
        let state = await LoginItem.loadState {
            LoginItem(mainApp: main, legacyAgent: legacy, launchedByLegacyAgent: false, bundleAgent: bundle) {}
        }
        XCTAssertEqual(state, LoginItem.State(isEnabled: true, needsApproval: false))
        // Check threads before reading status here: this assertion itself runs on the main thread.
        XCTAssertFalse(threads.isEmpty, "The probe must observe the status queries")
        XCTAssertFalse(threads.ranOnMain, "Settings must not block the main thread on SMAppService queries")
        XCTAssertEqual(bundle.status, .notRegistered, "Once the main app is enabled, the old bundle agent is retired")
    }

    func testSettingsStateReportsApprovalWithoutRemovingAgents() async {
        let state = await LoginItem.loadState {
            LoginItem(mainApp: Service(.requiresApproval), legacyAgent: Service(.notRegistered),
                      launchedByLegacyAgent: false, bundleAgent: Service(.enabled)) {}
        }
        XCTAssertEqual(state, LoginItem.State(isEnabled: true, needsApproval: true))
    }

    /// Records which threads queried a service; written from a background task.
    private final class ThreadLog: @unchecked Sendable {
        private let lock = NSLock()
        private var mainFlags: [Bool] = []
        func record() { lock.withLock { mainFlags.append(Thread.isMainThread) } }
        var isEmpty: Bool { lock.withLock { mainFlags.isEmpty } }
        var ranOnMain: Bool { lock.withLock { mainFlags.contains(true) } }
    }

    /// Shared with the background task under test; each test drives it from one task at a time.
    private final class Service: LoginItemService, @unchecked Sendable {
        var status: SMAppService.Status {
            get { threads?.record(); return storedStatus }
            set { storedStatus = newValue }
        }
        private var storedStatus: SMAppService.Status
        let afterRegistration: SMAppService.Status
        let failsRegistration: Bool
        private let threads: ThreadLog?
        private(set) var registrations = 0

        init(_ status: SMAppService.Status, afterRegistration: SMAppService.Status = .enabled,
             failsRegistration: Bool = false, threads: ThreadLog? = nil) {
            self.storedStatus = status
            self.afterRegistration = afterRegistration
            self.failsRegistration = failsRegistration
            self.threads = threads
        }

        func register() throws {
            registrations += 1
            if failsRegistration { throw CocoaError(.featureUnsupported) }
            status = afterRegistration
        }

        func unregister() throws {
            status = .notRegistered
        }
    }
}
