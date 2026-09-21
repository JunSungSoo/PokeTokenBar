import Foundation

/// 교환 세션 중 오가는 메시지. 트랜스포트(Multipeer/수동 TCP)와 무관하게 JSON 으로 주고받는다.
/// 연관값이 전부 Codable 이라 컴파일러가 케이스별 인코딩을 합성한다(SE-0295).
enum TradeMessage: Codable, Sendable {
    case hello(nickname: String, code: String)
    case offer(TradeItem)
    case offerWithdrawn
    case accept
    case reject(reason: String)
    /// 정보성 신호 — Accept 교환 시점에 양쪽이 이미 독립적으로 커밋을 시작하므로 수신 측 동작을
    /// 트리거하지 않는다(TradeSession.handle 참고). nonce 는 로그 상관관계용.
    case commit(nonce: String)
    case commitAck(nonce: String)
}
