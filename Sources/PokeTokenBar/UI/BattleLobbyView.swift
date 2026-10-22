import SwiftUI

@MainActor
struct BattleLobbyView: View {
    let store: CompanionStore
    let battle: BattleCoordinator
    var tradeActive = false
    @State private var selectedIDs: [String] = []
    @State private var lineupIDs: [String] = []
    @State private var selectingLineup = false
    @State private var building = false
    @State private var buildError: String?
    @State private var code = ""
    private var l: L { store.l }
    private var entries: [DexEntry] { BattleTeamBuilder.storedCandidates(store.state.dex) }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(l.battleRules).font(.caption).foregroundStyle(.secondary)
                if battle.isActive || battle.phase == .ended {
                    if let outcome = battle.outcome { Text(l.battleResult(outcome)).font(.headline) }
                    Button(l.battleOpen) { battle.onBattleWindow?() }
                    if battle.phase == .ended { Button(l.battleFind) { resetSelection(); battle.search() } }
                } else {
                    Picker(l.battle, selection: Binding(get: { battle.mode }, set: { value in
                        resetSelection(); battle.setMode(value)
                    })) {
                        Text(l.battleSingles).tag(BattleMode.singles)
                        Text(l.battleDoubles).tag(BattleMode.doubles)
                    }.pickerStyle(.segmented).disabled(!battle.canEditMode)
                    if battle.phase == .idle {
                        Text(l.battleSearchHint).font(.caption).foregroundStyle(.secondary)
                        Button(l.battleFind) { resetSelection(); battle.search() }.disabled(tradeActive)
                    } else {
                        HStack { Spacer(); Button(l.battleCancel) { battle.cancelLobby() }.buttonStyle(.link) }
                        peers
                        if battle.opponent != nil { teamPicker.id("battle-team-picker") }
                        else if let ownCode = battle.manualCode {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(l.tradeManualMyCode + ": " + ownCode).font(.caption).textSelection(.enabled)
                                HStack {
                                    TextField(l.tradeManualEnterCode, text: $code).textFieldStyle(.roundedBorder)
                                    Button(l.tradeManualConnect) { battle.connectManual(code) }.disabled(code.isEmpty)
                                }
                            }
                        }
                        if battle.phase == .searching && battle.manualCode == nil {
                            Button(l.battleManual) { battle.enableManualConnection() }.buttonStyle(.link)
                        }
                    }
                }
                if let error = buildError ?? battle.error { Text(l.battleUserError(error)).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                Divider()
                history
            }.frame(width: PopoverMetrics.scrollContentWidth, alignment: .leading)
                .reservesScrollerLane()
        }.frame(height: 392)
        .environment(\.locale,store.state.language.displayLocale)
        .onAppear { if !battle.registeredTeam.isEmpty {
            selectedIDs = battle.registeredTeam.map(\.id)
            if battle.localReady { lineupIDs = Array(battle.ownTeam.prefix(battle.mode.battleSize)).map(\.id) }
            selectingLineup = battle.canSelectLineup
        } }
        .onChange(of: battle.mode) { _, _ in selectedIDs = []; lineupIDs = []; selectingLineup = false }
        .onChange(of: entries.map(\.id)) { _, ids in
            selectedIDs.removeAll { !ids.contains($0) }
            lineupIDs.removeAll { !selectedIDs.contains($0) }
            if selectedIDs.count != battle.mode.teamSize { selectingLineup = false }
        }
        .onChange(of: battle.canSelectLineup) { _, value in selectingLineup = value; lineupIDs = [] }
        .onChange(of: battle.opponentRoster) { _, _ in lineupIDs = [] }
        .onChange(of: selectingLineup) { _, _ in proxy.scrollTo("battle-team-picker", anchor: .top) }
        }
    }
    private var peers: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let opponent = battle.opponent {
                Label(opponent.nickname + " · " + l.battleSelected, systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(Color.accentColor)
                Text(opponent.code).font(.caption.monospaced()).foregroundStyle(.secondary)
            } else if battle.phase == .connecting {
                if let peer = battle.selectedPeer {
                    Label(peer.nickname + " · " + l.battleSelected, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                HStack { ProgressView().controlSize(.small); Text(l.battleConnecting).font(.caption) }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(l.battleMatching).font(.callout.bold())
                    Spacer()
                    Text("\(battle.peers.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Text(l.battleMatchingHint).font(.caption).foregroundStyle(.secondary)
                if battle.peers.isEmpty {
                    Text(l.battleMatchingEmpty).font(.caption).foregroundStyle(.secondary).padding(.vertical, 12)
                }
                ForEach(battle.peers) { peer in
                    Button { battle.select(peer) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(peer.nickname).font(.callout.bold())
                                Text(peer.code).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }.padding(10).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private var selectedRoster: some View {
        let orderedIDs = selectedIDs
        let limit = battle.mode.teamSize
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 8) {
            ForEach(Array(orderedIDs.enumerated()), id: \.element) { position, id in
                if let entry = entries.first(where: { $0.id == id }) {
                    VStack(spacing: 3) {
                        SpriteView(speciesID: entry.finalID, size: 52, shiny: entry.isShiny, form: entry.form)
                            .frame(maxWidth: .infinity).padding(.top, 16)
                        Text(BattleTextCatalog.shared.speciesName(entry.finalID, language: store.state.language)).font(.caption2).lineLimit(1)
                        HStack(spacing: 6) {
                            Button { reorder(position, position - 1) } label: { Image(systemName: "chevron.left") }
                                .disabled(position == 0)
                            Text("\(position + 1)").font(.caption.monospacedDigit())
                            Button { reorder(position, position + 1) } label: { Image(systemName: "chevron.right") }
                                .disabled(position == orderedIDs.count - 1)
                        }.buttonStyle(.borderless)
                    }.padding(5).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            ForEach(orderedIDs.count..<limit, id: \.self) { position in
                VStack(spacing: 8) {
                    Image(systemName: "plus.circle.dashed").font(.largeTitle)
                    Text("\(position + 1)").font(.caption.monospacedDigit())
                }.foregroundStyle(.secondary).frame(maxWidth: .infinity).frame(height: 105)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
        }.disabled(battle.localReady || building)
    }
    @ViewBuilder private var teamPicker: some View {
        if battle.registeredTeam.isEmpty { registrationPicker }
        else { lineupPicker }
    }
    private var registrationPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(l.battleRegisteredTeam).font(.headline); Spacer(); Text("\(selectedIDs.count)/6").monospacedDigit() }
            Text(l.battleRegisterHint).font(.caption).foregroundStyle(.secondary)
            selectedRoster
            Text(l.battleFinalOnly).font(.caption).foregroundStyle(.secondary)
            Text(l.battleDuplicateSpecies).font(.caption).foregroundStyle(.secondary)
            Text(l.battleItemTypeExcluded).font(.caption).foregroundStyle(.secondary)
            ForEach(entries) { entry in
                let duplicate = BattleTeamBuilder.hasSelectedSpecies(entry, selectedIDs: selectedIDs, entries: entries)
                Button {
                    if selectedIDs.contains(entry.id) { selectedIDs.removeAll { $0 == entry.id } }
                    else if !duplicate && selectedIDs.count < 6 { selectedIDs.append(entry.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedIDs.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                        SpriteView(speciesID: entry.finalID, size: 26, shiny: entry.isShiny, form: entry.form)
                        Text(BattleTextCatalog.shared.speciesName(entry.finalID, language: store.language)).lineLimit(1)
                        Spacer(); Text("\(l.level) \(entry.profile?.level ?? 0)").font(.caption.monospacedDigit())
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(building || duplicate || !BattleTeamBuilder.isSpeciesEligible(entry.finalID))
            }
            Button(l.battleRegisterTeam) { prepareRegistration() }.buttonStyle(.borderedProminent)
                .disabled(selectedIDs.count != 6 || building)
            if building { ProgressView(l.battlePreparing).font(.caption) }
        }
    }
    private var lineupPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(l.battleTeam).font(.headline); Spacer(); Text("\(lineupIDs.count)/\(battle.mode.battleSize)").monospacedDigit() }
            BattleTeamPreview(own: battle.registeredTeam.map(BattleRosterMember.init), opponent: battle.opponentRoster,
                selected: lineupIDs, mode: battle.mode, language: store.language,
                enabled: battle.canSelectLineup && !battle.localReady, onSelect: { id in
                    if lineupIDs.contains(id) { lineupIDs.removeAll { $0 == id } }
                    else if lineupIDs.count < battle.mode.battleSize { lineupIDs.append(id) }
                })
            if battle.canSelectLineup {
                Text(l.battleLineupHint(battle.mode)).font(.caption).foregroundStyle(.secondary)
                Text(l.battleSelectionOrder).font(.caption).foregroundStyle(.secondary)
                if battle.localReady {
                    Text(l.battleWaiting).font(.caption).foregroundStyle(.secondary)
                    Button(l.battleUnready) { battle.unready() }
                } else {
                    Button(l.battleReady) { prepareLineup() }.buttonStyle(.borderedProminent)
                        .disabled(lineupIDs.count != battle.mode.battleSize)
                }
            } else {
                Text(l.battleWaitingForRoster).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func reorder(_ from: Int, _ to: Int) {
        selectedIDs.swapAt(from, to)
    }
    private func resetSelection() { selectedIDs = []; lineupIDs = []; selectingLineup = false }
    private var history: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(l.battleHistory).font(.headline)
                if let peer = battle.selectedPeer { Text(peer.nickname).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            let records = battle.history.forOpponent(battle.selectedPeer?.code)
            if records.isEmpty { Text(l.battleNoHistory).font(.caption).foregroundStyle(.secondary) }
            ForEach(records) { record in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.opponentName).font(.callout)
                        Text(record.endedAt, format: .dateTime.year().month().day().hour().minute()).font(.caption2).foregroundStyle(.secondary)
                        Text(record.mode == .singles ? l.battleSingles : l.battleDoubles).font(.caption2)
                    }
                    Spacer()
                    Text(l.battleResult(record.result)).font(.callout.bold()).foregroundStyle(record.result == "win" ? .green : .secondary)
                }.padding(8).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
            }
            if battle.history.error != nil { Text(l.battleHistoryProblem).font(.caption).foregroundStyle(.red) }
        }
    }
    private func prepareRegistration() {
        building = true; buildError = nil
        let ids = selectedIDs, mode = battle.mode
        Task { @MainActor in
            defer { building = false }
            do {
                let team = try await BattleTeamBuilder.build(ids: ids, entries: entries, mode: mode, language: store.language)
                guard battle.mode == mode, battle.phase == .connected,
                      ids.allSatisfy({ id in entries.contains { $0.id == id } }) else { return }
                battle.register(team: team)
            } catch { buildError = error.localizedDescription }
        }
    }
    private func prepareLineup() {
        do {
            let team = battle.registeredTeam
            let ids = try BattleTeamBuilder.orderedRoster(team.map(\.id), lineup: lineupIDs, mode: battle.mode)
            battle.ready(team: ids.compactMap { id in team.first { $0.id == id } })
        } catch { buildError = error.localizedDescription }
    }
}
