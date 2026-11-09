import Foundation
import ServiceManagement

/// Login launch and crash restart are managed together by a bundle-local LaunchAgent.
@MainActor
enum LoginItem {
    static let plistName = "io.github.chattymin.poketokenbar.login.bundle.plist"
    static let legacyPlistName = "io.github.chattymin.poketokenbar.login.plist"
    private static var agent: SMAppService { SMAppService.agent(plistName: plistName) }
    private static var legacyAgent: SMAppService { SMAppService.agent(plistName: legacyPlistName) }

    static var isEnabled: Bool { agent.status == .enabled }

    static func setEnabled(_ on: Bool) throws {
        if on {
            try agent.register()
        } else {
            // Turning off login launch must also remove any stale registration.
            for service in [legacyAgent, .mainApp, agent] where isRegistered(service.status) {
                try service.unregister()
            }
        }
    }

    static func migrateFromLegacyLoginItemIfNeeded() {
        guard AppEnv.isBundledApp,
              FileManager.default.fileExists(atPath: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Library/LaunchAgents")
                .appendingPathComponent(plistName).path) else { return }
        let current = agent
        let legacy = [legacyAgent, SMAppService.mainApp]
        let errors = migrate(
            current: current.status,
            legacy: legacy.map(\.status),
            register: { try current.register() },
            unregister: { try legacy[$0].unregister() }
        )
        for error in errors {
            AppLog.write("login item migration failed: \(error)")
        }
    }

    /// A failed registration must not leave an enabled job pointing at an obsolete executable.
    /// Disabled or pending approval legacy entries do not opt the user in to the replacement.
    static func migrate(
        current: SMAppService.Status,
        legacy: [SMAppService.Status],
        register: () throws -> Void,
        unregister: (Int) throws -> Void
    ) -> [Error] {
        var errors: [Error] = []
        if current == .notRegistered, legacy.contains(.enabled) {
            do { try register() } catch { errors.append(error) }
        }
        for (index, status) in legacy.enumerated() where isRegistered(status) {
            do { try unregister(index) } catch { errors.append(error) }
        }
        return errors
    }

    private static func isRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}
