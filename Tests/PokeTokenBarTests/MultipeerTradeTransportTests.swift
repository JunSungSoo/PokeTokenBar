import MultipeerConnectivity
import XCTest
@testable import PokeTokenBar

final class MultipeerTradeTransportTests: XCTestCase {
    /// Bonjour 서비스 타입 규칙: 1~15자, 영숫자와 하이픈만, 하이픈으로 시작/끝나지 않음.
    func testServiceTypeIsValidBonjourServiceType() {
        let serviceType = MultipeerTradeTransport.serviceType
        XCTAssertTrue((1...15).contains(serviceType.count))
        XCTAssertTrue(serviceType.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" })
        XCTAssertFalse(serviceType.hasPrefix("-"))
        XCTAssertFalse(serviceType.hasSuffix("-"))
    }

    func testMakeTradePeerUsesDiscoveryInfoCode() {
        let peer = MultipeerTradeTransport.makeTradePeer(displayName: "민수의 Mac", discoveryInfo: ["code": "ABCD1234"])
        XCTAssertEqual(peer.id, "민수의 Mac")
        XCTAssertEqual(peer.nickname, "민수의 Mac")
        XCTAssertEqual(peer.code, "ABCD1234")
    }

    func testMakeTradePeerFallsBackWhenDiscoveryInfoMissing() {
        let peer = MultipeerTradeTransport.makeTradePeer(displayName: "민수의 Mac", discoveryInfo: nil)
        XCTAssertEqual(peer.code, "????")
    }

    // MARK: R5 — 닉네임을 MCPeerID 제약(1~63 UTF-8 바이트, 비어있지 않음)에 맞게 클램프.

    func testClampNicknameFallsBackToHostNameWhenEmpty() {
        let clamped = MultipeerTradeTransport.clampNickname("", fallback: "MacBook-Pro")
        XCTAssertEqual(clamped, "MacBook-Pro")
    }

    func testClampNicknameFallsBackWhenOnlyWhitespace() {
        let clamped = MultipeerTradeTransport.clampNickname("   ", fallback: "MacBook-Pro")
        XCTAssertEqual(clamped, "MacBook-Pro")
    }

    func testClampNicknameTruncatesToUTF8ByteBudgetNotCharacterCount() {
        // 한글 한 글자는 UTF-8 로 3바이트 — 63바이트 예산이면 21글자를 넘길 수 없다.
        let longKoreanName = String(repeating: "민", count: 30)
        let clamped = MultipeerTradeTransport.clampNickname(longKoreanName, fallback: "fallback")
        XCTAssertLessThanOrEqual(clamped.utf8.count, 63)
        XCTAssertFalse(clamped.isEmpty)
    }

    func testClampNicknameLeavesShortNameUnchanged() {
        let clamped = MultipeerTradeTransport.clampNickname("민수의 Mac", fallback: "fallback")
        XCTAssertEqual(clamped, "민수의 Mac")
    }

    func testClampNicknameProducesValidMCPeerID() {
        // 클램프된 결과로 실제 MCPeerID 생성이 트랩 없이 성공하는지 확인 — R5 의 존재 이유.
        let longKoreanName = String(repeating: "가", count: 100)
        let clamped = MultipeerTradeTransport.clampNickname(longKoreanName, fallback: "fallback")
        let peerID = MCPeerID(displayName: clamped)
        XCTAssertFalse(peerID.displayName.isEmpty)
    }
}
