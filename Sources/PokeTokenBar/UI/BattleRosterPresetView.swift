import SwiftUI

@MainActor
struct BattleRosterPresetEditor: View {
    let store: CompanionStore
    let mode: BattleMode
    @Environment(\.dismiss) private var dismiss
    @AppStorage(BattleRosterPresets.storageKey) private var saved = Data()
    @State private var slot = 1
    @State private var ids: [String] = []
    @State private var itemOverrides: [String: String] = [:]
    @State private var editingItem: DexEntry?

    private var l: L { store.l }
    private var candidates: [DexEntry] {
        BattleTeamBuilder.storedCandidates(store.state.dex).filter { BattleTeamBuilder.isSpeciesEligible($0.finalID) }
    }
    private var loadout: BattleItemLoadout {
        var loadout = BattleItemLoadout()
        loadout.restore(roster: ids.compactMap { id in candidates.first { $0.id == id } },
                        remembered: BattlePokemonItemStore.shared.items, overrides: itemOverrides)
        return loadout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(l.battleRosterPresets).font(.headline)
                Spacer()
                Text(mode == .singles ? l.battleSingles : l.battleDoubles)
                    .foregroundStyle(.secondary)
            }
            Picker(l.battleRosterPresets, selection: $slot) {
                ForEach(BattleRosterPresets.slots, id: \.self) { Text(l.battlePresetSlot($0)).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            HStack {
                Text(l.battleFinalOnly).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(ids.count)/\(mode.teamSize)").monospacedDigit()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(candidates) { entry in
                        let position = ids.firstIndex(of: entry.id)
                        HStack {
                            row(entry, position: position) {
                                BattleRosterPresets.toggle(entry.id, in: &ids, mode: mode, candidates: candidates)
                                if !ids.contains(entry.id) { itemOverrides.removeValue(forKey: entry.id) }
                            }
                            .disabled(position == nil && (ids.count >= mode.teamSize ||
                                BattleTeamBuilder.hasSelectedSpecies(entry, selectedIDs: ids, entries: candidates)))
                            if position != nil {
                                Button(BattleHeldItems.item(loadout.items[entry.id])?.name(store.language) ?? l.battleNoItem) {
                                    editingItem = entry
                                }.lineLimit(1).help(l.battleChooseItem)
                            }
                        }
                    }
                }
            }.frame(height: 260)
            HStack {
                Button(l.battleCancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(l.battleSavePreset) {
                    var presets = BattleRosterPresets(data: saved)
                    if let data = try? presets.save(ids, mode: mode, slot: slot, candidates: candidates, items: loadout.items) {
                        saved = data
                        dismiss()
                    }
                }.buttonStyle(.borderedProminent)
                    .disabled(!BattleRosterPresets.isValid(ids, mode: mode, candidates: candidates))
            }
        }.padding(16).frame(width: 350)
            .onChange(of: slot, initial: true) { _, _ in
                let presets = BattleRosterPresets(data: saved)
                ids = presets.roster(mode: mode, slot: slot)
                    .filter { id in candidates.contains { $0.id == id } }
                itemOverrides = presets.itemOverrides(mode: mode, slot: slot)
            }
            .onChange(of: candidates.map(\.id)) { _, available in
                ids.removeAll { !available.contains($0) }
                itemOverrides = itemOverrides.filter { ids.contains($0.key) }
            }
            .sheet(item: $editingItem) { entry in
                BattleItemPicker(pokemon: entry, current: loadout.items[entry.id] ?? "",
                                 assignments: loadout.items, language: store.language, onApply: { item in
                    guard let current = candidates.first(where: { $0.id == entry.id }),
                          loadout.canApply(item, to: current, roster: ids) else { return false }
                    // Preserve the other displayed assignments even when defaults conflict.
                    let currentItems = loadout.items
                    itemOverrides = Dictionary(uniqueKeysWithValues: ids.map { ($0, currentItems[$0] ?? "") })
                    itemOverrides[entry.id] = item
                    editingItem = nil
                    return true
                }, onCancel: { editingItem = nil })
            }
    }

    private func row(_ entry: DexEntry, position: Int?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: position == nil ? "circle" : "checkmark.circle.fill")
                SpriteView(speciesID: entry.finalID, size: 26, shiny: entry.isShiny, form: entry.form)
                Text(BattleTextCatalog.shared.speciesName(entry.finalID, language: store.language)).lineLimit(1)
                Spacer()
                if let position {
                    Text("\(position + 1)").font(.caption.monospacedDigit()).foregroundStyle(Color.accentColor)
                }
                Text("\(l.level) \(entry.profile?.level ?? 0)").font(.caption.monospacedDigit())
            }.contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityAddTraits(position == nil ? [] : .isSelected)
    }
}

struct BattleRosterPresetMenu: View {
    let l: L
    let mode: BattleMode
    let candidates: [DexEntry]
    let apply: ([String], [String: String]) -> Void
    @AppStorage(BattleRosterPresets.storageKey) private var saved = Data()

    var body: some View {
        let presets = BattleRosterPresets(data: saved)
        Menu(l.battleLoadPreset) {
            ForEach(BattleRosterPresets.slots, id: \.self) { slot in
                let ids = presets.roster(mode: mode, slot: slot)
                let valid = BattleRosterPresets.isValid(ids, mode: mode, candidates: candidates)
                Button(l.battlePresetSlot(slot) + (valid ? "" : " · " + (ids.isEmpty ? l.battlePresetEmpty : l.battlePresetUnavailable))) {
                    apply(ids, presets.itemOverrides(mode: mode, slot: slot))
                }.disabled(!valid)
            }
        }.fixedSize()
    }
}
