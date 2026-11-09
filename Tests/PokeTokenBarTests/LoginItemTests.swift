import XCTest
@testable import PokeTokenBar

@MainActor
final class LoginItemTests: XCTestCase {
    func testMigratesEnabledAbsolutePathJobWithoutNeedingAnEnabledMainAppItem() {
        var actions: [String] = []
        let errors = LoginItem.migrate(current: .notRegistered, legacy: [.enabled, .notRegistered],
                                       register: { actions.append("register") },
                                       unregister: { actions.append("remove-\($0)") })
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(actions, ["register", "remove-0"])
    }

    func testRegistrationFailureStillRemovesStaleJobs() {
        var removed: [Int] = []
        let errors = LoginItem.migrate(current: .notRegistered, legacy: [.enabled, .enabled],
                                       register: { throw CocoaError(.featureUnsupported) },
                                       unregister: { removed.append($0) })
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(removed, [0, 1])
    }

    func testPendingApprovalDoesNotOptInAndMigrationIsIdempotent() {
        var removed: [Int] = []
        let errors = LoginItem.migrate(current: .notRegistered, legacy: [.requiresApproval, .notRegistered],
                                       register: { XCTFail("Pending approval is not opt-in") },
                                       unregister: { removed.append($0) })
        XCTAssertTrue(errors.isEmpty)
        XCTAssertEqual(removed, [0])
        let retry = LoginItem.migrate(current: .enabled, legacy: [.notRegistered, .notRegistered],
                                      register: { XCTFail("Already registered") },
                                      unregister: { _ in XCTFail("Already removed") })
        XCTAssertTrue(retry.isEmpty)
    }

    func testNewerAppCanIdentifyAnOlderRunningCopy() {
        XCTAssertTrue(SingleInstance.isOlderVersion("2.5.5", than: "3.0.9"))
        XCTAssertTrue(SingleInstance.isOlderVersion("3.0.9", than: "3.0.10"))
        XCTAssertFalse(SingleInstance.isOlderVersion("3.0.10", than: "3.0.9"))
        XCTAssertFalse(SingleInstance.isOlderVersion("3.0.9", than: "3.0.9"))
        XCTAssertFalse(SingleInstance.isOlderVersion(nil, than: "3.0.9"))
    }
}
