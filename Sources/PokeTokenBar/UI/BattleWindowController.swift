import AppKit
import SwiftUI
import AVFoundation

@MainActor
final class BattleWindowController: NSObject, NSWindowDelegate {
    private let battle: BattleCoordinator
    private let store: CompanionStore
    private(set) var window: NSWindow?
    private var windowMode: BattleMode?
    private(set) var contentMeasurement: BattleContentMeasurement?
    let auxiliaryState = BattleAuxiliaryState()
    private(set) var fieldWindow: NSWindow?
    private(set) var statsWindow: NSWindow?
    private var player: BattleMusicPlayer?
    private let allowsAudio: Bool
    let audioSettings: BattleAudioSettings
    var isMusicPlaying: Bool { player?.isPlaying == true }
    var musicOutputVolume: Double? { player?.volume }
    private var confirmingClose = false
    private(set) var muted = false
    init(battle: BattleCoordinator, store: CompanionStore, allowsAudio: Bool = true, audioDefaults: UserDefaults = .standard) {
        audioSettings = BattleAudioSettings(defaults:audioDefaults)
        self.allowsAudio = allowsAudio
        self.battle = battle; self.store = store
        super.init()
        audioSettings.onVolumeChange = { [weak self] volume in self?.player?.volume = volume }
        battle.onBattleWindow = { [weak self] in self?.show() }
        battle.onStopMusic = { [weak self] in self?.stopMusic() }
    }
    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: BattleWindowLayout.preferredWidth(for: battle.mode), height: 680),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "PokeTokenBar · " + store.l.battle
            window.minSize = NSSize(width: BattleWindowLayout.preferredWidth(for: battle.mode), height: 400)
            window.isReleasedWhenClosed = false
            window.delegate = self
            let hosting = NSHostingController(rootView: BattleView(battle: battle, store: store,
                onSurrender: { [weak self] in self?.confirmSurrender() }, onMusic: { [weak self] in self?.toggleMusic() },
                onPlayMusic: { [weak self] in self?.playMusic() }, audioSettings:audioSettings, allowsEffectsAudio:allowsAudio, auxiliaryState: auxiliaryState,
                onShowField: { [weak self] in self?.showAuxiliary(.field) },
                onShowStats: { [weak self] in self?.showAuxiliary(.stats) },
                onLayout: { [weak self] measurement in
                    Task { @MainActor [weak self] in self?.fitContent(measurement) }
                }))
            hosting.sizingOptions = []
            window.contentViewController = hosting
            self.window = window
            if let screen = NSScreen.main { window.setFrame(BattleWindowLayout(screen: screen.visibleFrame, mode: battle.mode).main, display: false) }
            else { window.center() }
        }
        if windowMode != battle.mode, let window {
            windowMode = battle.mode
            let width = BattleWindowLayout.preferredWidth(for: battle.mode)
            window.minSize.width = width
            window.setContentSize(NSSize(width: width, height: window.contentRect(forFrameRect: window.frame).height))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if auxiliaryState.fieldVisible { showAuxiliary(.field) }
        if auxiliaryState.statsVisible { showAuxiliary(.stats) }
        window?.makeKey()
        if battle.phase == .playing { playMusic() }
    }
    private func fitContent(_ measurement: BattleContentMeasurement) {
        contentMeasurement = measurement
        guard let window else { return }
        let titleHeight = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        let height = min(ceil(measurement.content.height) + titleHeight, visible?.height ?? .greatestFiniteMagnitude)
        let minimum = NSSize(width: BattleWindowLayout.preferredWidth(for: battle.mode), height: height)
        if window.minSize != minimum { window.minSize = minimum }
        guard abs(window.frame.height - height) > 0.5 else { return }
        var rect = window.frame
        rect.origin.y = max(visible?.minY ?? rect.minY, rect.maxY - height)
        rect.size.height = height
        window.setFrame(rect, display: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === fieldWindow { auxiliaryState.fieldVisible = false; return true }
        if sender === statsWindow { auxiliaryState.statsVisible = false; return true }
        guard battle.isActive else { stopMusic(); hideAuxiliaries(); return true }
        confirmSurrender(); return false
    }
    func showAuxiliary(_ kind: BattleAuxiliaryKind) {
        guard let window else { return }
        var panel = kind == .field ? fieldWindow : statsWindow
        if panel == nil {
            let created = NSPanel(contentRect: .zero, styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
            created.isReleasedWhenClosed = false
            created.hidesOnDeactivate = false
            created.minSize = NSSize(width: 200, height: 200)
            created.delegate = self
            created.title = kind == .field ? store.l.battleFieldWindow : store.l.battleStatsWindow
            created.contentViewController = NSHostingController(rootView: BattleAuxiliaryView(kind: kind, battle: battle, store: store))
            if kind == .field { fieldWindow = created } else { statsWindow = created }
            panel = created
        }
        if kind == .field { auxiliaryState.fieldVisible = true } else { auxiliaryState.statsVisible = true }
        positionAuxiliaries()
        if let panel {
            if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
            panel.makeKeyAndOrderFront(nil)
        }
    }
    private func hideAuxiliaries() {
        fieldWindow?.orderOut(nil); statsWindow?.orderOut(nil)
    }
    private func positionAuxiliaries() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let layout = BattleWindowLayout(screen: screen.visibleFrame, mode: battle.mode, main: window.frame)
        fieldWindow?.setFrame(layout.field, display: true)
        statsWindow?.setFrame(layout.stats, display: true)
    }
    func windowDidMove(_ notification: Notification) {
        if notification.object as? NSWindow === window { positionAuxiliaries() }
    }
    func windowDidResize(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        // AppKit may notify while laying out its view tree; resize on the next main-actor turn.
        Task { @MainActor [weak self] in
            guard let self, let window = self.window, let measurement = self.contentMeasurement,
                  abs(measurement.content.width - window.contentRect(forFrameRect: window.frame).width) < 1 else { return }
            self.fitContent(measurement)
        }
        positionAuxiliaries()
    }
    func confirmSurrender() {
        guard let window, battle.isActive, !confirmingClose else { return }
        confirmingClose = true
        let alert = NSAlert()
        alert.messageText = store.l.battleConfirmClose
        alert.informativeText = store.l.battleCloseDetail
        alert.alertStyle = .warning
        alert.addButton(withTitle: store.l.battleSurrender)
        alert.addButton(withTitle: store.l.cancel)
        alert.beginSheetModal(for: window) { [weak self] response in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.confirmingClose = false
                if response == .alertFirstButtonReturn {
                    self.battle.surrender(); self.stopMusic(); self.hideAuxiliaries(); self.window?.orderOut(nil)
                }
            }
        }
    }
    func playMusic() {
        guard allowsAudio, !muted, battle.phase == .playing, player?.isPlaying != true else { return }
        do {
            player = try BattleMusicPlayer(directory:BattleEngineProcess.resourceDirectory,volume:audioSettings.volume)
            try player?.play()
        } catch { AppLog.write("battle BGM unavailable: \(error.localizedDescription)") }
    }
    private func stopMusic() { player?.stop(); player = nil }
    private func toggleMusic() { muted.toggle(); if muted { stopMusic() } else { playMusic() } }
}
