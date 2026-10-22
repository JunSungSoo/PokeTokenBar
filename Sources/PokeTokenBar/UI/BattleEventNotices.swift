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
        let moves = frame.effects ?? []
        var messages: [Int: String] = [:]
        for (index, line) in frame.log.enumerated() where line.hasPrefix("|move|") {
            messages[offset + index] = BattleLogText.describe(line, language: language, ownPlayer: ownPlayer)
        }
        let abilityEvents = notices.map { notice in
            let id = offset + notice.id
            messages[id] = notice.text
            return BattleVisualEvent(id: id, move: notice.text, type: "", category: "Status",
                source: BattleEffectPosition(own: true, slot: 0), targets: [], phase: "ability")
        }
        let existing = Set((moves + abilityEvents).map(\.id))
        let stateEvents = (frame.scenes ?? []).filter { !existing.contains($0.id) }.map { scene in
            let index = scene.id - offset
            let line = frame.log.indices.contains(index) ? frame.log[index] : ""
            let kind = line.split(separator: "|", omittingEmptySubsequences: false).dropFirst().first ?? ""
            let visible = ["switch", "drag", "replace", "faint", "cant"].contains(String(kind))
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
    var body: some View {
        Text(text).font(.callout.weight(.semibold)).foregroundStyle(.white)
            .multilineTextAlignment(.center).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.2)))
            .padding(.horizontal, 24)
            .accessibilityIdentifier("battle-event-notice")
            .allowsHitTesting(false)
    }
}
