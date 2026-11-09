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
    private final class Service: LoginItemService {
        var status: SMAppService.Status
        let afterRegistration: SMAppService.Status
        let failsRegistration: Bool
        private(set) var registrations = 0

        init(_ status: SMAppService.Status, afterRegistration: SMAppService.Status = .enabled,
             failsRegistration: Bool = false) {
            self.status = status
            self.afterRegistration = afterRegistration
            self.failsRegistration = failsRegistration
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
