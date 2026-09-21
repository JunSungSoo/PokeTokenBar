import Foundation

/// 교환 상대에게 보여줄 내 신원 — 진행 데이터가 아니라 기기 고유 값이라 CompanionState(세이브) 밖에 둔다.
enum TradeIdentity {
    private static let nicknameKey = "tradeNickname"
    private static let codeKey = "tradeCode"

    static func nickname(defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: nicknameKey) ?? (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
    }

    static func setNickname(_ nickname: String, defaults: UserDefaults = .standard) {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: nicknameKey)
        } else {
            defaults.set(trimmed, forKey: nicknameKey)
        }
    }

    /// 8자리 대문자+숫자 — 사람이 손으로 옮겨 적기 쉬운 길이. 혼동되는 0/O, 1/I 는 알파벳에서 제외.
    static func code(defaults: UserDefaults = .standard) -> String {
        if let existing = defaults.string(forKey: codeKey) { return existing }
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let generated = String((0..<8).map { _ in alphabet.randomElement()! })
        defaults.set(generated, forKey: codeKey)
        return generated
    }
}
