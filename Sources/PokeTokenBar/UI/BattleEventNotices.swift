import SwiftUI

struct BattleAbilityNotice: Identifiable {
    let id: Int
    let text: String
}

@MainActor
struct BattlePresentationEvents {
    let events: [BattleVisualEvent]
    let messages: [Int: String]
    init(frame: BattleFrame, language: AppLanguage, ownPlayer: Int) {
        let offset = frame.logOffset ?? 0
        let notices = BattleLogText.abilityNotices(frame.log, language: language, ownPlayer: ownPlayer)
            .filter { !frame.log[$0.id].hasPrefix("|move|") }
        let fieldEffects = Dictionary(uniqueKeysWithValues: (frame.scenes ?? []).compactMap { scene -> (Int, BattleFieldEffects.Effect)? in
            let index = scene.id - offset
            guard frame.log.indices.contains(index), let effect = BattleFieldEffects.effect(scene: scene, line: frame.log[index], frame: frame) else { return nil }
            return (scene.id, effect)
        })
        let replacedMoves = Set(fieldEffects.values.compactMap(\.replacesMove))
        let moves = (frame.effects ?? []).filter { !replacedMoves.contains($0.id) }
        var messages: [Int: String] = [:]
        for (index, line) in frame.log.enumerated() where line.hasPrefix("|move|") {
            messages[offset + index] = BattleLogText.describe(line, language: language, ownPlayer: ownPlayer)
        }
        let abilityEvents = notices.filter { fieldEffects[$0.id + offset] == nil }.map { notice in
            let id = offset + notice.id
            messages[id] = notice.text
            return BattleVisualEvent(id: id, move: notice.text, type: "", category: "Status",
                source: BattleEffectPosition(own: true, slot: 0), targets: [], phase: "ability")
        }
        let existing = Set((moves + abilityEvents).map(\.id))
        let stateEvents = (frame.scenes ?? []).filter { !existing.contains($0.id) }.map { scene in
            let index = scene.id - offset
            let line = frame.log.indices.contains(index) ? frame.log[index] : ""
            if let event=BattleEntryEffects.event(scene:scene,line:line,ownPlayer:ownPlayer) {
                messages[scene.id]=BattleLogText.describe(line,language:language,ownPlayer:ownPlayer)
                return event
            }
            if let effect = fieldEffects[scene.id] {
                messages[scene.id] = BattleLogText.describe(line, language: language, ownPlayer: ownPlayer)
                return effect.event
            }
            let kind = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first ?? ""
            let visible = ["switch", "drag", "replace", "faint", "cant", "-damage", "-heal", "-status", "-curestatus", "-activate", "-weather", "-fieldstart", "-fieldend", "-sidestart", "-sideend", "-start", "-end"].contains(String(kind))
            if visible { messages[scene.id] = BattleLogText.describe(line, language: language, ownPlayer: ownPlayer) }
            return BattleVisualEvent(id: scene.id, move: "", type: "", category: "Status",
                source: BattleEffectPosition(own: true, slot: 0), targets: [], phase: visible ? "transition" : "state")
        }
        self.events = (moves + abilityEvents + stateEvents).sorted { $0.id < $1.id }
        self.messages = messages
    }
}

@MainActor
struct BattleEventNotice: View {
    let text: String
    var lines = 3
    var body: some View {
        Text(text).font(.callout.weight(.semibold)).foregroundStyle(.white)
            .multilineTextAlignment(.center).lineLimit(lines).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2)))
            .padding(.horizontal, 24)
            .accessibilityIdentifier("battle-event-notice")
            .allowsHitTesting(false)
    }
}

/// Newer messages sit below older messages; only recent messages are retained.
struct BattleTransientNotice: Identifiable, Equatable {
    let id: Int
    let text: String
    let began: Date
    var expires: Date?
}

struct BattleNoticeQueue {
    private(set) var entries: [BattleTransientNotice] = []
    var nextExpiry: Date? { entries.compactMap(\.expires).min() }
    mutating func append(id: Int, text: String, at now: Date = Date()) {
        entries.removeAll { $0.id == id }
        entries.append(BattleTransientNotice(id: id, text: text, began: now))
        if entries.count > 3 { entries.removeFirst(entries.count - 3) }
    }
    mutating func finish(id: Int, at now: Date = Date()) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].expires = max(entries[index].began.addingTimeInterval(3), now.addingTimeInterval(0.7))
    }
    mutating func expire(at now: Date = Date()) {
        entries.removeAll { $0.expires.map { $0 <= now } ?? false }
    }
}

@MainActor
struct BattleNoticeStack: View {
    let notices: [BattleTransientNotice]
    var body: some View {
        GeometryReader { geometry in
            ViewThatFits(in: .vertical) {
                stack(3, lines: 2)
                stack(2, lines: 2)
                stack(1, lines: 2)
                stack(1, lines: 1)
            }
            .frame(width: max(0, geometry.size.width - 16), height: max(0, geometry.size.height - 20))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 5)
        }.clipped().allowsHitTesting(false)
    }
    private func stack(_ count: Int, lines: Int) -> some View {
        VStack(spacing: 5) {
            ForEach(notices.suffix(count)) { notice in
                BattleEventNotice(text: notice.text, lines: lines)
            }
        }
    }
}
