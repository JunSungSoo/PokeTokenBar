import AppKit
import SwiftUI

/// Store the sprite origin independently of any extra panel space for bubbles.
@MainActor
struct FloatingPetPosition {
    let slot: FloatingPetSlot
    let defaults: UserDefaults

    private var prefix: String {
        slot == .primary ? "floatingPetOrigin" : "floatingPet\(slot.rawValue)Origin"
    }

    var origin: NSPoint? {
        guard let x = defaults.object(forKey: prefix + "X") as? Double, x.isFinite,
              let y = defaults.object(forKey: prefix + "Y") as? Double, y.isFinite else { return nil }
        return NSPoint(x: x, y: y)
    }

    func save(_ origin: NSPoint) {
        defaults.set(Double(origin.x), forKey: prefix + "X")
        defaults.set(Double(origin.y), forKey: prefix + "Y")
    }

    static func firstOrigin(size: CGFloat, near anchor: NSPoint, occupied: [NSRect],
                            visibleFrame: NSRect) -> NSPoint {
        let step = size + 12
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - size)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - size)
        func clamp(_ point: NSPoint) -> NSPoint {
            NSPoint(x: min(max(point.x, visibleFrame.minX), maxX),
                    y: min(max(point.y, visibleFrame.minY), maxY))
        }

        let candidates = [
            NSPoint(x: anchor.x - step, y: anchor.y), NSPoint(x: anchor.x + step, y: anchor.y),
            NSPoint(x: anchor.x, y: anchor.y + step), NSPoint(x: anchor.x, y: anchor.y - step),
            NSPoint(x: anchor.x - 2 * step, y: anchor.y), NSPoint(x: anchor.x + 2 * step, y: anchor.y),
            NSPoint(x: anchor.x - step, y: anchor.y + step), NSPoint(x: anchor.x + step, y: anchor.y + step),
            NSPoint(x: visibleFrame.minX, y: visibleFrame.minY), NSPoint(x: visibleFrame.minX, y: maxY),
            NSPoint(x: maxX, y: maxY), NSPoint(x: maxX, y: visibleFrame.minY)
        ].map(clamp)
        return candidates.first { point in
            let frame = NSRect(origin: point, size: NSSize(width: size, height: size))
            return occupied.allSatisfy { !$0.intersects(frame) }
        } ?? clamp(NSPoint(x: anchor.x - step, y: anchor.y + step))
    }
}

/// One observation for both optional windows. Only the primary controller subscribes to agent and usage events.
@MainActor
final class AdditionalFloatingPets {
    private let store: UsageStore
    private let companion: CompanionStore
    private let defaults: UserDefaults
    private let windows: [FloatingPetSlot: AdditionalFloatingPetWindow]
    private var displayAwake = true
    private var powerObservation: (any NSObjectProtocol)?

    init(store: UsageStore, companion: CompanionStore, defaults: UserDefaults = .standard,
         spriteStore: SpriteStore = .shared) {
        self.store = store
        self.companion = companion
        self.defaults = defaults
        windows = Dictionary(uniqueKeysWithValues: FloatingPetSlot.additional.map { slot in
            (slot, AdditionalFloatingPetWindow(position: .init(slot: slot, defaults: defaults),
                                               store: store, companion: companion, spriteStore: spriteStore))
        })
        observe()
        powerObservation = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
        sync()
    }

    isolated deinit {
        if let powerObservation { NotificationCenter.default.removeObserver(powerObservation) }
        for window in windows.values { window.hide() }
    }

    func setDisplayAwake(_ awake: Bool) {
        displayAwake = awake
        sync()
    }

    func visibleFrame(for slot: FloatingPetSlot) -> NSRect? { windows[slot]?.visibleFrame }

    private func observe() {
        withObservationTracking {
            _ = companion.additionalFloatingPetSubjects
            _ = companion.representativeSubject
            _ = store.floatingPetEnabled
            _ = store.secondFloatingPetEnabled
            _ = store.thirdFloatingPetEnabled
            _ = store.floatingPetSize
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observe()
                self.sync()
            }
        }
    }

    private func sync() {
        let size = CGFloat(store.floatingPetSize)
        let primary = companion.representativeSubject
        let screens = NSScreen.screens.map(\.visibleFrame)
        let savedPrimary = FloatingPetPosition(slot: .primary, defaults: defaults).origin
        let anchor = savedPrimary.flatMap { point in
            screens.contains(where: { $0.contains(point) }) ? point : nil
        } ?? FloatingPetController.defaultPetOrigin(petSize: size)
        let screen = screens.first { $0.contains(anchor) } ?? NSScreen.main?.visibleFrame
        let dimensions = NSSize(width: size, height: size)
        var occupied: [FloatingPetSlot: NSRect] = [:]
        if store.floatingPetEnabled { occupied[.primary] = NSRect(origin: anchor, size: dimensions) }
        let subjects = companion.additionalFloatingPetSubjects.filter { slot, subject in
            let duplicate = store.floatingPetEnabled && primary.speciesID == subject.speciesID
                && primary.form == subject.form
            return displayAwake && store[floatingPet: slot] && !duplicate
        }
        // Reserve enabled pets' saved positions first. Enabling slot 2 after slot 3 must
        // not place a fresh window on top of slot 3 just because slot 2 is visited first.
        for slot in subjects.keys {
            guard let origin = windows[slot]?.position.origin else { continue }
            let frame = NSRect(origin: origin, size: dimensions)
            if screens.contains(where: { $0.intersects(frame) }) { occupied[slot] = frame }
        }
        for slot in FloatingPetSlot.additional {
            guard let window = windows[slot] else { continue }
            guard let subject = subjects[slot] else {
                window.hide()
                if companion.additionalFloatingPetSubjects[slot] == nil, store[floatingPet: slot] {
                    store[floatingPet: slot] = false
                }
                continue
            }
            let neighbors = occupied.filter { $0.key != slot }.map(\.value)
            let fallback = screen.map {
                FloatingPetPosition.firstOrigin(size: size, near: anchor, occupied: neighbors, visibleFrame: $0)
            } ?? anchor
            window.show(subject: subject, size: size, screens: screens, fallback: fallback)
            occupied[slot] = window.visibleFrame
        }
    }
}

@MainActor
private final class AdditionalFloatingPetWindow {
    let position: FloatingPetPosition
    private let store: UsageStore
    private let companion: CompanionStore
    private let spriteStore: SpriteStore
    private var panel: NSPanel?
    private var renderedSubject: CompanionStore.RepresentativeSubject?
    private var renderedAnimated: Bool?
    private var heartExpiry: Task<Void, Never>?
    private let hearts = PetHeartState()

    var visibleFrame: NSRect? { panel.flatMap { $0.isVisible ? $0.frame : nil } }

    init(position: FloatingPetPosition, store: UsageStore, companion: CompanionStore, spriteStore: SpriteStore) {
        self.position = position
        self.store = store
        self.companion = companion
        self.spriteStore = spriteStore
    }

    func show(subject: CompanionStore.RepresentativeSubject, size: CGFloat, screens: [NSRect], fallback: NSPoint) {
        let panel = self.panel ?? FloatingPetController.makePetPanel()
        self.panel = panel
        let animated = FloatingPetController.shouldAnimate(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        if panel.contentView == nil || renderedSubject != subject || renderedAnimated != animated {
            let hosting = PetHostingView(rootView: AnyView(
                AdditionalFloatingPetView(subject: subject, animated: animated, spriteStore: spriteStore, hearts: hearts)
                    .environment(store).environment(companion)
            ))
            hosting.onDrag = { [position] in position.save($0) }
            hosting.onStroke = { [weak self] in self?.stroke() }
            hosting.onHide = { [weak self] in
                guard let self else { return }
                self.store[floatingPet: self.position.slot] = false
            }
            hosting.languageProvider = { [weak self] in self?.companion.language ?? .systemDefault }
            panel.contentView = hosting
            renderedSubject = subject
            renderedAnimated = animated
        }
        let hosting = panel.contentView as? PetHostingView
        hosting?.strokeDistance = max(10, size * 0.15)
        let dimensions = NSSize(width: size, height: size)
        let saved = position.origin
        let requested = NSRect(origin: saved ?? fallback, size: dimensions)
        let frame = screens.contains(where: { $0.intersects(requested) })
            ? requested : NSRect(origin: fallback, size: dimensions)
        if saved == nil, !screens.isEmpty { position.save(frame.origin) }
        if hosting?.isDragging != true, panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        heartExpiry?.cancel()
        heartExpiry = nil
        hearts.isShowing = false
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func stroke() {
        hearts.isShowing = true
        heartExpiry?.cancel()
        heartExpiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: FloatingPetController.heartDuration)
            guard !Task.isCancelled else { return }
            self?.hearts.isShowing = false
        }
    }
}

@MainActor
private struct AdditionalFloatingPetView: View {
    let subject: CompanionStore.RepresentativeSubject
    let animated: Bool
    let spriteStore: SpriteStore
    let hearts: PetHeartState
    @Environment(UsageStore.self) private var store
    @Environment(CompanionStore.self) private var companion

    var body: some View {
        SpriteView(speciesID: subject.speciesID, size: CGFloat(store.floatingPetSize), animated: animated,
                   shiny: subject.isShiny, minFrameDelay: store.animationQuality.frameFloor, spriteStore: spriteStore,
                   form: subject.form, back: store.alwaysFacesBack, reportsVisibleTop: true)
            .overlayPreferenceValue(SpriteVisibleTopKey.self, alignment: .top) { top in
                if hearts.isShowing {
                    HeartBubbleView(l: companion.l)
                        .offset(y: max(0, SpriteVisibleTop.bubbleTopOffset(visibleTop: top ?? 0,
                                                                        bubbleHeight: HeartBubbleArt.height,
                                                                        overlap: HeartBubbleArt.tailOverlap)))
                        .allowsHitTesting(false)
                }
            }
    }
}
