import AppKit
import Darwin

@MainActor
enum ZipInstaller {
    static func run(source: URL, target: URL, identifier: String, reinstallSameVersion: Bool = false) async throws {
        let parent = target.deletingLastPathComponent()
        let lock = try BundleInstallation.lockDirectory(parent)
        defer { close(lock) }

        try BundleInstallation.validateSignature(at: source)
        let incoming = try BundleInstallation.version(at: source, identifier: identifier)
        let installed = try BundleInstallation.exists(target)
        let old = installed ? try BundleInstallation.version(at: target, identifier: identifier) : nil
        if let old, BundleInstallation.keepsInstalledVersion(old, incoming: incoming, reinstallSameVersion: reinstallSameVersion) {
            try BundleInstallation.validateSignature(at: target)
            try await launch(target)
            return
        }

        // Stage first so a permission or integrity failure cannot interrupt a running app.
        let copy = try await Task.detached { try BundleInstallation.stage(source, in: parent) }.value
        var keepBackup = false
        defer {
            if !keepBackup { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { !$0.isTerminated }
        for app in running {
            if let location = app.bundleURL,
               let version = try? BundleInstallation.version(at: location, identifier: identifier),
               version > incoming { throw BundleInstallation.Failure.busy }
        }
        for app in running { app.terminate() }
        for _ in 0..<100 where !running.allSatisfy(\.isTerminated) {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .allSatisfy(\.isTerminated) else { throw BundleInstallation.Failure.didNotQuit }

        let stillInstalled = try BundleInstallation.exists(target)
        guard stillInstalled == installed,
              !installed || (try? BundleInstallation.version(at: target, identifier: identifier)) == old
        else { throw BundleInstallation.Failure.busy }
        try BundleInstallation.move(copy, target, replacing: installed)
        do {
            try await launch(target)
        } catch {
            do {
                if installed { try BundleInstallation.move(copy, target, replacing: true) }
                else { try BundleInstallation.move(target, copy, replacing: false) }
            } catch {
                keepBackup = true
                throw BundleInstallation.Failure.rollback(copy)
            }
            if installed { try? await launch(target) }
            throw error
        }
    }

    private static func launch(_ target: URL) async throws {
        let app = try await NSWorkspace.shared.openApplication(at: target, configuration: .init())
        guard app.bundleURL?.resolvingSymlinksInPath().path == target.resolvingSymlinksInPath().path else {
            throw BundleInstallation.Failure.busy
        }
    }
}

@main
@MainActor
final class Launcher: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = Launcher()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            let payload = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/PokeTokenBar.app")
            let target = URL(fileURLWithPath: "/Applications/PokeTokenBar.app", isDirectory: true)
            do {
                try await ZipInstaller.run(source: payload, target: target,
                                           identifier: "io.github.chattymin.poketokenbar",
                                           reinstallSameVersion: Bundle.main.object(forInfoDictionaryKey: "PTBReinstallSameVersion") as? Bool ?? false)
            } catch {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                let korean = Locale.preferredLanguages.first?.hasPrefix("ko") == true
                alert.messageText = korean ? "PokeTokenBar 설치를 완료하지 못했습니다" : "Could not install PokeTokenBar"
                alert.informativeText = error.localizedDescription + "\n\n" + (korean
                    ? "권한이 필요한 경우 아래 버튼으로 실제 앱을 열어 응용 프로그램 폴더에 복사하세요."
                    : "If permissions are required, reveal the app and copy it to Applications in Finder.")
                alert.addButton(withTitle: korean ? "확인" : "OK")
                alert.addButton(withTitle: korean ? "앱 위치 보기" : "Reveal App")
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([payload])
                }
            }
            NSApp.terminate(nil)
        }
    }
}
