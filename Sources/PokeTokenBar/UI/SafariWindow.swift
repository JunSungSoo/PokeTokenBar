import AppKit
import ImageIO
import SwiftUI

@MainActor
final class SafariWindowController: NSObject, NSWindowDelegate {
    static let shared = SafariWindowController()
    private(set) var window: NSWindow?
    private var store: CompanionStore?
    private var closing = false
    func show(store: CompanionStore) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        self.store = store; closing = false
        window.title = store.l.safariTitle; window.isReleasedWhenClosed = false; window.delegate = self
        window.contentViewController = NSHostingController(rootView: SafariView(store: store))
        self.window = window
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, let store, let session = store.safariSession else { return true }
        guard session.phase != .replacement else { NSSound.beep(); return false }
        if session.phase == .finished {
            do { try store.finishAndDismissSafari(); return true } catch { showError(error, in: sender); return false }
        }
        let alert = NSAlert()
        alert.messageText = store.l.safariExitQuestion
        alert.addButton(withTitle: store.l.quit); alert.addButton(withTitle: store.l.cancel)
        alert.beginSheetModal(for: sender) { [weak self, weak sender] response in
            guard response == .alertFirstButtonReturn, let self, let sender else { return }
            do {
                try store.finishAndDismissSafari()
                self.closing = true; sender.close()
            } catch { self.showError(error, in: sender) }
        }
        return false
    }
    private func showError(_ error: Error, in window: NSWindow) {
        let alert = NSAlert(); alert.messageText = store?.l.userFacingError(error) ?? error.localizedDescription
        alert.beginSheetModal(for: window)
    }
    func windowWillClose(_ notification: Notification) { window = nil; store = nil }
}

@MainActor enum SafariArtwork {
    static func resource(_ name: String, extension ext: String) -> URL? {
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("BattleText/\(name).\(ext)")
        return bundled.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? AppResources.module.url(forResource: name, withExtension: ext, subdirectory: "BattleText")
    }
    static let redBack = redBackImage(frame: 0)
    private static func redBackImage(frame: Int) -> NSImage? {
        guard let url = resource("safari-red-back", extension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let crop = sheet.cropping(to: CGRect(x: 0, y: min(4, max(0, frame)) * 64, width: 64, height: 64)),
              let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                  bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return nil }
        // Decode palette PNGs into RGBA before color-keying. Indexed colorAt conversions can fail.
        context.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        let pixels = data.bindMemory(to: UInt8.self, capacity: 64 * 64 * 4)
        let key = (pixels[0], pixels[1], pixels[2])
        for i in 0..<(64 * 64) {
            let offset = i * 4
            if pixels[offset] == key.0 && pixels[offset + 1] == key.1 && pixels[offset + 2] == key.2 {
                pixels[offset] = 0; pixels[offset + 1] = 0; pixels[offset + 2] = 0; pixels[offset + 3] = 0
            }
        }
        guard let image = context.makeImage() else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 64, height: 64))
    }
    static let redDisplaySize = 192
    /// Bypass NSImage's Retina resampling and fractional scale/position interpolation.
    static var redDisplayPixels: CGImage? { redDisplayFrames[0] }
    static func redDisplayFrame(_ index: Int) -> CGImage? { redDisplayFrames[min(4, max(0, index))] }
    private static let redDisplayFrames: [CGImage?] = (0..<5).map { frame in
        guard let original = redBackImage(frame: frame)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: redDisplaySize, height: redDisplaySize,
                  bitsPerComponent: 8, bytesPerRow: redDisplaySize * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return nil }
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(original, in: CGRect(x: 0, y: 0, width: redDisplaySize, height: redDisplaySize))
        return context.makeImage()
    }
    private static var arenas: [SafariArea:NSImage] = [:]
    static func arena(_ area: SafariArea) -> NSImage? {
        if let image = arenas[area] { return image }
        let image = NSImage(contentsOf: PokeRogueOriginalCatalog.directory.appendingPathComponent("images/arenas/\(area.rawValue)_bg.png"))
        arenas[area] = image
        return image
    }
}

@MainActor
struct SafariView: View {
    let store: CompanionStore
    var playsMusic = true
    @State private var catalog: SafariCatalog? = try? SafariCatalog.load()
    @State private var selected: SafariArea = .plains
    @State private var error: String?
    @State private var busy = false
    @State private var playbackSession: SafariSession?
    @State private var projectile: SafariAction?
    @State private var projectileStartedAt: Date?
    @State private var capture: SafariCapturePlayback?
    @State private var captureAudio = SafariCaptureAudio()
    @State private var actionPlayback: Task<Void,Never>?
    @State private var music: BattleMusicPlayer?
    @State private var audio = BattleAudioSettings(defaults: .standard)
    @State private var inputGuard = SafariInputGuard()
    @State private var choosingArea = false
    private var l: L { store.l }

    var body: some View {
        VStack(spacing: 10) {
            if let session = playbackSession ?? store.safariSession { journey(session) }
            else { locationPicker }
            if let error { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14).frame(width: 660, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(choosingArea)
        .overlay {
            if choosingArea, let session = store.safariSession, canTravel(session) {
                SafariAreaTransferModal(options: session.travelDestinations, catalog: catalog, language: store.language,
                                        warnsAboutFleeing: session.phase == .encounter,
                                        confirm: { destination in
                                            choosingArea = false
                                            guard let catalog else { return }
                                            perform { try store.safariTravel(to: destination, catalog: catalog) }
                                        },
                                        cancel: { choosingArea = false })
            }
        }
        .task {
            do { catalog = try SafariCatalog.load(); try SafariRogueAssets.validate() }
            catch { self.error = l.userFacingError(error) }
            updateMusic()
        }
        .task(id: store.safariSession?.wild?.id) {
            guard playsMusic, let id = store.safariSession?.wild?.species.id else { return }
            await store.loadPokemonDetails(speciesID: id)
        }
        .onChange(of: store.safariSession?.phase) { _, _ in updateMusic() }
        .onChange(of: store.safariSession?.wild?.id) { _, _ in inputGuard.lock(at: Date()) }
        .onDisappear { actionPlayback?.cancel(); captureAudio.stop(); music?.stop(); music = nil }

    }
    private var locationPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l.safariChooseArea).font(.headline)
            Text(l.safariTicketDescription).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(SafariArea.allCases, id: \.self) { area in
                        Button { selected = area } label: {
                            SafariAreaCard(area: area, representative: catalog?.representative(in: area),
                                           selected: selected == area, language: store.language)
                        }.buttonStyle(.plain).accessibilityIdentifier("safari-area-" + area.rawValue)
                    }
                }.reservesScrollerLane()
            }
            Button(l.safariEnter) {
                guard let catalog else { return }
                perform { try store.startSafari(area: selected, catalog: catalog) }; updateMusic()
            }.buttonStyle(.borderedProminent).disabled(catalog == nil || !store.canEnterSafari)
                .accessibilityIdentifier("safari-enter")
        }
    }
    private func journey(_ session: SafariSession) -> some View {
        VStack(spacing: 10) {
            HStack {
                Text(l.safariArea(session.area)).font(.headline)
                Spacer()
                Text("\(l.safariBalls): \(session.ballsRemaining)")
                Text("\(l.safariEncounters): \(session.encounters)")
            }.font(.caption).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            battlefield(session)
            VStack(alignment: .leading, spacing: 3) {
                if capture != nil { Text(l.safariThrowingBall).font(.callout) }
                else {
                    ForEach(Array(session.notices.enumerated()), id: \.offset) { _, notice in
                        Text(l.safariNotice(notice)).font(.callout)
                    }
                }
            }.frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            if session.phase == .replacement, let old = session.carried, let new = session.pendingCatch {
                VStack(spacing: 8) {
                    Text(l.safariReplacement(old: name(old), new: name(new))).font(.headline)
                    HStack {
                        Button(l.safariKeep) { perform { try store.safariResolveCatch(replace: false) } }
                        Button(l.safariReplace) { perform { try store.safariResolveCatch(replace: true) } }.buttonStyle(.borderedProminent)
                    }
                }.frame(maxWidth: .infinity).disabled(busy).accessibilityIdentifier("safari-replacement")
            } else if session.phase == .between {
                Button(l.safariNext) {
                    if let catalog { perform { try store.safariContinue(catalog: catalog) } }
                }.buttonStyle(.borderedProminent).disabled(busy || catalog == nil)
            } else if session.phase == .encounter {
                HStack(spacing: 8) {
                    actionButton(.ball, title:l.safariBall,hint:"\(l.safariCatchRate) \(String(format:"%.1f",session.catchChance))%")
                    actionButton(.rock, title:l.safariRock,hint:l.safariRockHint)
                    actionButton(.bait, title:l.safariBait,hint:l.safariBaitHint)
                    actionButton(.run, title: l.safariRun)
                }.disabled(busy)
            }
            HStack {
                if let kept = session.carried {
                    SpriteView(speciesID: kept.species.id, size: 38, animated: true, shiny: kept.shiny)
                    Text(l.safariCarried + ": " + name(kept)).font(.caption)
                } else { Text(l.safariCarried + ": " + l.safariNone).font(.caption) }
                Spacer()
                Image(systemName: "music.note")
                Slider(value: Binding(get: { audio.volume }, set: { audio.setVolume($0); music?.volume = $0 }), in: 0...1)
                    .frame(width: 65).accessibilityLabel(l.battleVolume)
                Image(systemName:"speaker.wave.2.fill")
                Slider(value:Binding(get:{audio.effectsVolume},set:{audio.setEffectsVolume($0);captureAudio.setVolume($0)}),in:0...1)
                    .frame(width:65).accessibilityLabel(l.battleEffectsVolume)
            }
            HStack {
                Text(l.safariSaveHint).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                // The container's environment overrides a native button's own flag, so disable through SwiftUI too.
                SafariFinishButton(title: l.safariTravelButton, enabled: canTravel(session), identifier: "safari-travel") {
                    if canTravel(session) { choosingArea = true }
                }.fixedSize().disabled(!canTravel(session))
                SafariFinishButton(title:l.quit,enabled:!busy && session.phase != .replacement) {
                    do {
                        try store.finishAndDismissSafari()
                        SafariWindowController.shared.window?.performClose(nil)
                    } catch { self.error = l.userFacingError(error) }
                }.fixedSize().disabled(busy || session.phase == .replacement)
            }
        }
        // Re-armed when the picker closes, so cancelling it resumes the automatic advance.
        .task(id: "\(session.phase.rawValue)-\(choosingArea)") {
            guard session.shouldAdvanceAutomatically else { return }
            do { try await Task.sleep(for: .milliseconds(1200)) } catch { return }
            guard !Task.isCancelled, !busy, !choosingArea,
                  store.safariSession?.id == session.id, store.safariSession?.shouldAdvanceAutomatically == true,
                  let catalog else { return }
            perform { try store.safariContinue(catalog: catalog) }
        }
    }
    private func battlefield(_ session: SafariSession) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: capture == nil && projectile == nil)) { context in
            SafariBattlefield(session: session, language: store.language,
                captureFrame: capture.map { $0.sequence.frame(at: context.date.timeIntervalSince($0.startedAt)) },
                projectile: projectile, projectileProgress: projectileStartedAt.map { context.date.timeIntervalSince($0)/SafariThrowPath.itemDuration } ?? 0)
        }
    }
    private func actionButton(_ action: SafariAction, title: String, hint:String = "") -> some View {
        Button {
            guard !busy, inputGuard.accepts(at: Date()) else { return }
            // Commit the outcome before playing its animation; a closed window cannot reroll it.
            playbackSession = store.safariSession; busy = true
            perform { try store.safariAct(action) }
            guard error == nil else { playbackSession = nil; busy = false; return }
            let sequence = action == .ball ? store.safariSession?.lastCapture.map { SafariCaptureSequence(result:$0) } : nil
            actionPlayback = Task { @MainActor in
                do {
                    if let sequence {
                        let playback = SafariCapturePlayback(startedAt:Date(),sequence:sequence)
                        capture = playback
                        if playsMusic { captureAudio.start(playback,speciesID:playbackSession?.wild?.species.id,volume:audio.effectsVolume) }
                        try await Task.sleep(for: .seconds(sequence.duration))
                    } else if action != .run {
                        projectile = action; projectileStartedAt = Date()
                        try await Task.sleep(for: .milliseconds(650))
                    }
                } catch { }
                capture = nil; projectile = nil; projectileStartedAt = nil
                playbackSession = nil; busy = false; actionPlayback = nil
            }
        } label: {
            VStack(spacing:3) {
                Text(title).font(.callout.weight(.semibold))
                Text(hint).font(.system(size:9)).lineLimit(2).frame(height:25).help(hint)
            }.frame(maxWidth:.infinity,minHeight:54)
        }.buttonStyle(.bordered).accessibilityIdentifier("safari-action-" + action.rawValue)
    }
    /// Travel waits for capture playback and never interrupts the replacement choice or a finished trip.
    private func canTravel(_ session: SafariSession) -> Bool {
        !busy && playbackSession == nil && (session.phase == .encounter || session.phase == .between) && session.ballsRemaining > 0
    }
    private func name(_ pokemon: SafariPokemon) -> String {
        BattleTextCatalog.shared.speciesName(pokemon.species.id, language: store.language) + (pokemon.shiny ? " ✨" : "")
    }
    private func perform(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = l.userFacingError(error) }
    }
    private func updateMusic() {
        guard playsMusic, let session = store.safariSession, session.phase != .finished else { music?.stop(); music = nil; return }
        guard music == nil else { return }
        do {
            let player = try BattleMusicPlayer(directory: BattleEngineProcess.resourceDirectory, volume: audio.volume)
            try player.play(); music = player
        } catch { AppLog.write("Safari music unavailable: \(error)") }
    }
}

/// Explicitly marked QA bundles use an isolated save and open directly to the real Bag UI.
@MainActor
struct SafariBagTestView: View {
    let store: CompanionStore
    @State private var navigation = PopoverNavigation()
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.l.bag).font(.headline)
            BagView(store: store, nav: navigation)
        }.padding(16).frame(width: 420, height: 600)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

@MainActor
struct SafariAreaCard: View {
    let area: SafariArea
    let representative: SafariSpecies?
    let selected: Bool
    let language: AppLanguage
    var body: some View {
        let l = L(language)
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Text(l.safariArea(area)).font(.callout.weight(.semibold))
                if selected { Image(systemName: "checkmark.circle.fill") }
            }
            if let representative {
                SpriteView(speciesID: representative.id, size: 72, animated: true)
                Text(BattleTextCatalog.shared.speciesName(representative.id, language: language))
                    .font(.caption.weight(.semibold))
                Text(l.safariRepresentative).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(8).frame(maxWidth: .infinity, minHeight: 136)
        .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 8))
    }
}
