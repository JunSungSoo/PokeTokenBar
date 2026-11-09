import Foundation
import ServiceManagement

@MainActor
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

@MainActor
struct LoginItem {
    private static let legacyLabel = "io.github.chattymin.poketokenbar.login"
    private static let bundleAgentLabel = "\(legacyLabel).bundle"

    let mainApp: any LoginItemService
    let legacyAgent: any LoginItemService
    let bundleAgent: (any LoginItemService)?
    let launchedByLegacyAgent: Bool
    let launchedByBundleAgent: Bool
    let openLoginItemsSettings: () -> Void

    init(mainApp: any LoginItemService, legacyAgent: any LoginItemService,
         launchedByLegacyAgent: Bool, bundleAgent: (any LoginItemService)? = nil,
         launchedByBundleAgent: Bool = false, openLoginItemsSettings: @escaping () -> Void) {
        self.mainApp = mainApp
        self.legacyAgent = legacyAgent
        self.bundleAgent = bundleAgent
        self.launchedByLegacyAgent = launchedByLegacyAgent
        self.launchedByBundleAgent = launchedByBundleAgent
        self.openLoginItemsSettings = openLoginItemsSettings
    }

    static var system: LoginItem {
        LoginItem(
            mainApp: SMAppService.mainApp,
            legacyAgent: SMAppService.agent(plistName: "\(legacyLabel).plist"),
            launchedByLegacyAgent: AppEnv.xpcServiceName == legacyLabel,
            bundleAgent: SMAppService.agent(plistName: "\(bundleAgentLabel).plist"),
            launchedByBundleAgent: AppEnv.xpcServiceName == bundleAgentLabel,
            openLoginItemsSettings: SMAppService.openSystemSettingsLoginItems
        )
    }

    var status: SMAppService.Status { mainApp.status }
    var isEnabled: Bool {
        status == .enabled || legacyAgent.status == .enabled || bundleAgent?.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if !enabled {
            // Unregister the owner last because launchd can terminate this process.
            if !launchedByLegacyAgent { try unregisterIfNeeded(legacyAgent) }
            if let bundleAgent, !launchedByBundleAgent { try unregisterIfNeeded(bundleAgent) }
            try unregisterIfNeeded(mainApp)
            if launchedByLegacyAgent { try unregisterIfNeeded(legacyAgent) }
            if let bundleAgent, launchedByBundleAgent { try unregisterIfNeeded(bundleAgent) }
            return
        }

        do {
            try registerMainAppIfNeeded()
        } catch {
            guard status == .requiresApproval else {
                try? retireAbsolutePathAgent()
                throw error
            }
        }
        try retireAbsolutePathAgent()
        if status == .requiresApproval {
            openLoginItemsSettings()
        } else {
            try removeLegacyAgentAfterActivation()
        }
    }

    func migrateFromLegacyAgentIfNeeded() {
        let absolutePathWasEnabled = legacyAgent.status == .enabled
        if absolutePathWasEnabled || bundleAgent?.status == .enabled {
            do { try registerMainAppIfNeeded() }
            catch { AppLog.write("login item registration failed: \(error)") }
        }
        do {
            // The old absolute-path job can start an obsolete app even while macOS
            // is waiting for approval or after direct registration fails.
            if absolutePathWasEnabled { try retireAbsolutePathAgent() }
            try removeLegacyAgentAfterActivation()
        } catch {
            AppLog.write("login item migration failed: \(error)")
        }
    }

    func removeLegacyAgentAfterActivation() throws {
        guard status == .enabled else { return }
        try retireAbsolutePathAgent()
        if let bundleAgent, !launchedByBundleAgent { try unregisterIfNeeded(bundleAgent) }
    }

    private func registerMainAppIfNeeded() throws {
        if !isRegistered(status) { try mainApp.register() }
    }

    private func retireAbsolutePathAgent() throws {
        // Removing the job that owns this process would kill it mid-launch.
        if !launchedByLegacyAgent { try unregisterIfNeeded(legacyAgent) }
    }

    private func unregisterIfNeeded(_ service: any LoginItemService) throws {
        if isRegistered(service.status) { try service.unregister() }
    }

    private func isRegistered(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }
}
