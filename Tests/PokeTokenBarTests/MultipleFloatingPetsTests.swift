import AppKit
import Darwin
import XCTest
@testable import PokeTokenBar

@MainActor
final class MultipleFloatingPetsTests: XCTestCase {
    private struct Fixture {
        let suite: String
        let directory: URL
        var file: URL { directory.appendingPathComponent("state.json") }
        let defaults: UserDefaults
        let store: UsageStore
        let companion: CompanionStore
        let sprites: SpriteStore
    }

    private func fixture(released: Bool = false, realSprites: Bool = false) throws -> Fixture {
        let suite = "MultipleFloatingPets-\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("state.json")
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var state = CompanionState()
        state.active = MonState(baseID: 25, pathIDs: [25], stageIndex: 0, usedAtStage: 0,
                                rarity: .common, totalForms: 1)
        state.dex = [
            .init(baseID: 1, finalID: 1, chainOrder: [1], rarity: .common,
                  caughtAt: nil, releasedAt: released ? Date() : nil),
            .init(baseID: 4, finalID: 6, chainOrder: [4, 5, 6], rarity: .common, caughtAt: nil)
        ]
        try JSONEncoder().encode(state).write(to: file)
        let (seed, seedDirectory) = try PokeRogueFaithfulTests().gifStore()
        defer { try? FileManager.default.removeItem(at: seedDirectory) }
        let gifs = SpriteStore(directory: directory.appendingPathComponent("sprites"))
        let sample = try Data(contentsOf: seed.directory.appendingPathComponent("25-a.gif"))
        let installed = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PokeTokenBar/sprites")
        let staticSample = try XCTUnwrap(NSBitmapImageRep(data: sample)?.representation(using: .png, properties: [:]))
        for id in [1, 6, 25] {
            let gif = realSprites ? try Data(contentsOf: installed.appendingPathComponent("\(id)-a.gif")) : sample
            try gif.write(to: gifs.directory.appendingPathComponent("\(id)-a.gif"))
            try staticSample.write(to: gifs.directory.appendingPathComponent("\(id)-s.png"))
        }
        addTeardownBlock {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        return Fixture(suite: suite, directory: directory, defaults: defaults,
                       store: UsageStore(providers: [], autoRefresh: false, defaults: defaults),
                       companion: CompanionStore(fileURL: file, defaults: defaults), sprites: gifs)
    }

    private func select(_ id: Int) -> FloatingPetSelection { .init(speciesID: id, form: nil) }

    func testAssignmentsPersistAndMoveBetweenSlotsWithoutChangingFollowMode() throws {
        let f = try fixture()
        XCTAssertTrue(f.companion.additionalFloatingPetSubjects.isEmpty)
        XCTAssertEqual(f.companion.representativeSubject.speciesID, 25)
        XCTAssertTrue(f.companion.setFloatingPet(.second, selection: select(1)))
        XCTAssertTrue(f.companion.setFloatingPet(.third, selection: select(6)))
        XCTAssertTrue(f.companion.setRepresentativeSpeciesID(1))
        XCTAssertNil(f.companion.additionalFloatingPetSubjects[.second])
        XCTAssertEqual(f.companion.representativeSubject.speciesID, 1)
        let loaded = CompanionStore(fileURL: f.file, defaults: f.defaults)
        XCTAssertEqual(loaded.additionalFloatingPetSubjects[.third]?.speciesID, 6)
        XCTAssertEqual(loaded.representativeSubject.speciesID, 1)
        let charizard = try XCTUnwrap(loaded.dexSpecies.first { $0.id == 6 })
        loaded.toggleFloatingPet(.third, species: charizard)
        XCTAssertTrue(loaded.additionalFloatingPetSubjects.isEmpty)
        XCTAssertTrue(loaded.setRepresentativeSpeciesID(nil))
        XCTAssertEqual(loaded.representativeSubject.speciesID, 25)
    }

    func testReleasedRecordCannotSupplySlotAndImportClearsMissingSpecies() throws {
        let f = try fixture(released: true)
        XCTAssertFalse(f.companion.setFloatingPet(.second, selection: select(1)))
        XCTAssertTrue(f.companion.setFloatingPet(.second, selection: select(6)))
        var state = f.companion.state
        state.dex.removeAll { $0.finalID == 6 }
        let sanitized = SaveTransfer.sanitized(state)
        XCTAssertNil(sanitized.secondFloatingPet)

        let sent = try XCTUnwrap(f.companion.state.dex.first { $0.finalID == 6 })
        let received = DexEntry(baseID: 7, finalID: 7, chainOrder: [7], rarity: .common, caughtAt: nil)
        _ = try f.companion.applyTradeCommit(sending: .dexEntry(sent), receiving: .dexEntry(received))
        XCTAssertNil(f.companion.additionalFloatingPetSubjects[.second])
        XCTAssertNil(CompanionStore(fileURL: f.file, defaults: f.defaults).state.secondFloatingPet)
    }

    func testDistinctWindowOriginsRestoreWithNewStoresAndControllers() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let f = try fixture()
        let slots = FloatingPetSlot.allCases
        for (i, slot) in slots.enumerated() {
            let position = NSPoint(x: screen.minX + CGFloat(100 + i * 125), y: screen.minY + 100)
            FloatingPetPosition(slot: slot, defaults: f.defaults).save(position)
            XCTAssertEqual(f.defaults.double(forKey: slot == .primary ? "floatingPetOriginX" : "floatingPet\(slot.rawValue)OriginX"),
                           Double(position.x))
        }
        XCTAssertTrue(f.companion.setFloatingPet(.second, selection: select(1)))
        XCTAssertTrue(f.companion.setFloatingPet(.third, selection: select(6)))
        f.store.floatingPetEnabled = true
        f.store.secondFloatingPetEnabled = true
        f.store.thirdFloatingPetEnabled = true
        let primary = FloatingPetController(store: f.store, companion: f.companion,
                                            defaults: f.defaults, spriteStore: f.sprites)
        let primaryBefore = try XCTUnwrap(primary.visibleFrame)
        primary.setDisplayAwake(false)
        let first = AdditionalFloatingPets(store: f.store, companion: f.companion,
                                          defaults: f.defaults, spriteStore: f.sprites)
        let before = FloatingPetSlot.additional.map { first.visibleFrame(for: $0) }
        XCTAssertTrue(before.allSatisfy { $0 != nil })
        first.setDisplayAwake(false)
        XCTAssertNil(first.visibleFrame(for: .third))
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: f.suite))
        let reopenedUsage = UsageStore(providers: [], autoRefresh: false, defaults: reopenedDefaults)
        let reopenedCompanion = CompanionStore(fileURL: f.file, defaults: reopenedDefaults)
        let primaryReopened = FloatingPetController(store: reopenedUsage, companion: reopenedCompanion,
                                                    defaults: reopenedDefaults, spriteStore: f.sprites)
        XCTAssertEqual(primaryReopened.visibleFrame, primaryBefore)
        primaryReopened.setDisplayAwake(false)
        let reopened = AdditionalFloatingPets(store: reopenedUsage, companion: reopenedCompanion,
                                              defaults: reopenedDefaults, spriteStore: f.sprites)
        XCTAssertEqual(FloatingPetSlot.additional.map { reopened.visibleFrame(for: $0) }, before)
        XCTAssertNotEqual(before[0]?.origin, before[1]?.origin)
        XCTAssertEqual(FloatingPetPosition(slot: .primary, defaults: reopenedDefaults).origin?.x,
                       screen.minX + 100)

        // An automatically followed primary hides its duplicate only while the primary is visible.
        XCTAssertTrue(reopenedCompanion.setFloatingPet(.second, selection: select(25)))
        reopenedUsage.floatingPetEnabled = true
        try await wait { reopened.visibleFrame(for: .second) == nil }
        XCTAssertTrue(reopenedUsage.secondFloatingPetEnabled)
        reopenedUsage.floatingPetEnabled = false
        try await wait { reopened.visibleFrame(for: .second) != nil }
        XCTAssertNotNil(reopened.visibleFrame(for: .third))
        XCTAssertTrue(reopenedCompanion.setFloatingPet(.second, selection: nil))
        try await wait { !reopenedUsage.secondFloatingPetEnabled && reopened.visibleFrame(for: .second) == nil }
        reopened.setDisplayAwake(false)
    }

    func testMouseDragMovesAndPersistsEachRealPetWindowIndependently() throws {
        let app = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let f = try fixture()
        let slots = FloatingPetSlot.allCases
        let origins = slots.map { slot in
            NSPoint(x: screen.minX + 124 * CGFloat(slot.rawValue), y: screen.minY + 100)
        }
        for (slot, origin) in zip(slots, origins) {
            FloatingPetPosition(slot: slot, defaults: f.defaults).save(origin)
            f.store[floatingPet: slot] = true
        }
        XCTAssertTrue(f.companion.setFloatingPet(.second, selection: select(1)))
        XCTAssertTrue(f.companion.setFloatingPet(.third, selection: select(6)))
        var primaryClicks = 0
        let primary = FloatingPetController(store: f.store, companion: f.companion, defaults: f.defaults,
                                            onOpenPopover: { primaryClicks += 1 }, spriteStore: f.sprites)
        let additional = AdditionalFloatingPets(store: f.store, companion: f.companion,
                                                defaults: f.defaults, spriteStore: f.sprites)
        defer { primary.setDisplayAwake(false); additional.setDisplayAwake(false) }

        let panels = try origins.map { origin in
            try XCTUnwrap(app.windows.first {
                $0.isVisible && $0.frame.origin == origin && $0.contentView is PetHostingView
            })
        }
        var expected = origins
        for (index, panel) in panels.enumerated() {
            let host = try XCTUnwrap(panel.contentView as? PetHostingView)
            panel.layoutIfNeeded()
            let center = NSPoint(x: host.bounds.midX, y: host.bounds.midY)
            let start = panel.convertPoint(toScreen: host.convert(center, to: nil))
            let end = NSPoint(x: start.x + 21, y: start.y + 23)
            func send(_ type: NSEvent.EventType, at point: NSPoint) throws {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: panel.convertPoint(fromScreen: point),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                if type == .leftMouseDown {
                    let hit = host.hitTest(host.convert(center, to: host.superview))
                    XCTAssertTrue(hit === host, "Slot \(index + 1) must route the press to its drag handler")
                    XCTAssertTrue(host.acceptsFirstMouse(for: event), "A background pet must drag on the first press")
                }
                panel.sendEvent(event)
            }
            try send(.leftMouseDown, at: start)
            try send(.leftMouseDragged, at: NSPoint(x: start.x + 9, y: start.y + 11))
            try send(.leftMouseDragged, at: end)
            try send(.leftMouseUp, at: end)
            expected[index] = NSPoint(x: origins[index].x + 21, y: origins[index].y + 23)
            XCTAssertEqual(panels.map { $0.frame.origin }, expected)
            XCTAssertEqual(slots.map { FloatingPetPosition(slot: $0, defaults: f.defaults).origin }, expected.map(Optional.some))

            if index == 0 {
                try send(.leftMouseDown, at: end)
                try send(.leftMouseUp, at: end)
                XCTAssertEqual(primaryClicks, 1, "Dragging must not open the popover and a plain click still should")
            }
        }
    }

    func testNewSlotAvoidsAnotherPetThatWasEnabledFirst() async throws {
        _ = NSApplication.shared
        _ = try XCTUnwrap(NSScreen.main)
        let f = try fixture()
        XCTAssertTrue(f.companion.setFloatingPet(.second, selection: select(1)))
        XCTAssertTrue(f.companion.setFloatingPet(.third, selection: select(6)))
        f.store.floatingPetEnabled = true
        f.store.thirdFloatingPetEnabled = true
        let pets = AdditionalFloatingPets(store: f.store, companion: f.companion,
                                           defaults: f.defaults, spriteStore: f.sprites)
        defer { pets.setDisplayAwake(false) }
        let third = try XCTUnwrap(pets.visibleFrame(for: .third))
        f.store.secondFloatingPetEnabled = true
        try await wait { pets.visibleFrame(for: .second) != nil }
        let second = try XCTUnwrap(pets.visibleFrame(for: .second))
        XCTAssertFalse(second.intersects(third))
        XCTAssertEqual(pets.visibleFrame(for: .third), third)
    }

    /// The same test runs twice in separate XCTest processes with the same isolated save and preference suite.
    func testPositionsAcrossProcessRelaunch() throws {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["PTB_FLOATING_RELAUNCH_DIRECTORY"], let phase = env["PTB_FLOATING_RELAUNCH_PHASE"] else {
            throw XCTSkip("Set the isolated relaunch directory and use the write/read phases")
        }
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main).visibleFrame
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let file = directory.appendingPathComponent("state.json")
        let suite = directory.lastPathComponent
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let sprites = SpriteStore(directory: directory.appendingPathComponent("sprites"))
        let expected = FloatingPetSlot.allCases.map { slot in
            NSPoint(x: screen.minX + 125 * CGFloat(slot.rawValue), y: screen.minY + 125)
        }

        if phase == "write" {
            var state = CompanionState()
            state.dex = [1, 6, 25].map {
                DexEntry(baseID: $0, finalID: $0, chainOrder: [$0], rarity: .common, caughtAt: nil)
            }
            try JSONEncoder().encode(state).write(to: file)
            let companion = CompanionStore(fileURL: file, defaults: defaults)
            let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
            for (slot, id) in zip(FloatingPetSlot.allCases, [25, 1, 6]) {
                XCTAssertTrue(companion.setFloatingPet(slot, selection: select(id)))
                store[floatingPet: slot] = true
                FloatingPetPosition(slot: slot, defaults: defaults).save(expected[slot.rawValue - 1])
            }
            for id in [1, 6, 25] {
                let cached = SpriteLoader.cacheDir.appendingPathComponent("\(id)-a.gif")
                try FileManager.default.copyItem(at: cached, to: sprites.directory.appendingPathComponent("\(id)-a.gif"))
            }
        } else {
            XCTAssertEqual(phase, "read")
            defer { defaults.removePersistentDomain(forName: suite) }
            let companion = CompanionStore(fileURL: file, defaults: defaults)
            let store = UsageStore(providers: [], autoRefresh: false, defaults: defaults)
            let primary = FloatingPetController(store: store, companion: companion, defaults: defaults, spriteStore: sprites)
            let extra = AdditionalFloatingPets(store: store, companion: companion, defaults: defaults, spriteStore: sprites)
            defer { primary.setDisplayAwake(false); extra.setDisplayAwake(false) }
            XCTAssertEqual(companion.representativeSubject.speciesID, 25)
            XCTAssertEqual(companion.additionalFloatingPetSubjects[.second]?.speciesID, 1)
            XCTAssertEqual(companion.additionalFloatingPetSubjects[.third]?.speciesID, 6)
            XCTAssertEqual(primary.visibleFrame?.origin, expected[0])
            XCTAssertEqual(extra.visibleFrame(for: .second)?.origin, expected[1])
            XCTAssertEqual(extra.visibleFrame(for: .third)?.origin, expected[2])
        }
        XCTAssertTrue(defaults.synchronize())
    }

    private func wait(for condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(15)) }
        XCTAssertTrue(condition())
    }

    private func measure(seconds: Int) async throws -> (cpu: Double, wakeups: Double) {
        var info = task_power_info_data_t()
        func wakeups() throws -> UInt64 {
            var count = mach_msg_type_number_t(MemoryLayout<task_power_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_POWER_INFO), $0, &count)
                }
            }
            XCTAssertEqual(result, KERN_SUCCESS)
            return info.task_interrupt_wakeups
        }
        let before = try wakeups()
        let start = ProcessInfo.processInfo.systemUptime
        let startCPU = clock()
        try await Task.sleep(for: .seconds(seconds))
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        return (Double(clock() - startCPU) / Double(CLOCKS_PER_SEC) * 100 / elapsed,
                Double(try wakeups() - before) / elapsed)
    }

    func testIdlePerformanceWithRealFloatingPanels() async throws {
        guard ProcessInfo.processInfo.environment["PTB_BENCHMARK_FLOATING_PETS"] == "1" else {
            throw XCTSkip("Set PTB_BENCHMARK_FLOATING_PETS=1 for real-window idle measurements")
        }
        _ = NSApplication.shared
        _ = try XCTUnwrap(NSScreen.main)
        XCTAssertFalse(ProcessInfo.processInfo.isLowPowerModeEnabled, "The comparison must exercise animated GIFs")
        let f = try fixture(realSprites: true)
        XCTAssertTrue(f.companion.setFloatingPet(.second, selection: select(1)))
        XCTAssertTrue(f.companion.setFloatingPet(.third, selection: select(6)))
        let primary = FloatingPetController(store: f.store, companion: f.companion,
                                            defaults: f.defaults, spriteStore: f.sprites)
        let extras = AdditionalFloatingPets(store: f.store, companion: f.companion,
                                            defaults: f.defaults, spriteStore: f.sprites)
        defer { primary.setDisplayAwake(false); extras.setDisplayAwake(false) }
        f.store.floatingPetEnabled = true
        for count in [1, 3, 3, 1] {
            f.store.secondFloatingPetEnabled = count == 3
            f.store.thirdFloatingPetEnabled = count == 3
            try await wait {
                primary.visibleFrame != nil
                    && FloatingPetSlot.additional.filter { extras.visibleFrame(for: $0) != nil }.count == count - 1
            }
            try await Task.sleep(for: .seconds(2))
            let result = try await measure(seconds: 12)
            print(String(format: "PTB floating benchmark: pets=%d CPU=%.3f%% interrupt wakeups=%.3f/s frame floor=%.2fs",
                         count, result.cpu, result.wakeups, f.store.animationQuality.frameFloor))
        }
    }
}
