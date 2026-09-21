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

    // MARK: C2 — 1:1 보장. MCSession 은 다자 연결이 가능해 초대를 무조건 수락하면 send 가 브로드캐스트된다.

    func testInvitationFromAThirdPartyIsRefusedWhileTradingWithSomeone() {
        let accepted = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Carol", partner: "Bob", invited: nil,
            myKey: "Alice\u{0}AAAA", theirKey: "Carol\u{0}CCCC")
        XCTAssertFalse(accepted, "a third party must not join an established 1:1 trade")
    }

    func testInvitationFromTheCurrentPartnerIsAcceptedAgain() {
        // 같은 상대가 재연결을 시도하는 경우 — 파트너 고정 때문에 막히면 안 된다.
        let accepted = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: "Bob", invited: nil,
            myKey: "Alice\u{0}AAAA", theirKey: "Bob\u{0}BBBB")
        XCTAssertTrue(accepted)
    }

    func testInvitationFromAnUninvitedPeerIsAcceptedWhenFree() {
        let accepted = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: nil,
            myKey: "Alice\u{0}AAAA", theirKey: "Bob\u{0}BBBB")
        XCTAssertTrue(accepted, "the side that did not click must still be reachable")
    }

    func testCrossedInvitationsAreResolvedSoExactlyOneSideAccepts() {
        // 둘 다 상대 행을 눌러 초대가 교차한 상황 — 양쪽 다 수락하면 같은 쌍에 연결이 두 개 생기고
        // 하나가 곧 끊겨 교환이 조용히 처음으로 되돌아간다.
        let aliceKey = "Alice\u{0}AAAA"
        let bobKey = "Bob\u{0}BBBB"
        let aliceAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: "Bob", myKey: aliceKey, theirKey: bobKey)
        let bobAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Alice", partner: nil, invited: "Alice", myKey: bobKey, theirKey: aliceKey)
        XCTAssertNotEqual(aliceAccepts, bobAccepts, "exactly one side of a crossed invitation may accept")
    }

    func testCrossedInvitationTieBreakUsesTheCodeWhenNicknamesMatch() {
        // 닉네임 기본값이 컴퓨터 이름이라 두 기기가 같은 이름을 쓸 수 있다 — 닉네임만으론 순서가 없다.
        let firstKey = MultipeerTradeTransport.tiebreakKey(displayName: "MacBook Pro", code: "AAAA1111")
        let secondKey = MultipeerTradeTransport.tiebreakKey(displayName: "MacBook Pro", code: "BBBB2222")
        XCTAssertNotEqual(firstKey, secondKey)
        let firstAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "MacBook Pro", partner: nil, invited: "MacBook Pro",
            myKey: firstKey, theirKey: secondKey)
        let secondAccepts = MultipeerTradeTransport.shouldAccept(
            invitationFrom: "MacBook Pro", partner: nil, invited: "MacBook Pro",
            myKey: secondKey, theirKey: firstKey)
        XCTAssertNotEqual(firstAccepts, secondAccepts)
    }

    func testTiebreakKeySeparatesNameFromCode() {
        // 구분자 없이 이어 붙이면 ("ab","c") 와 ("a","bc") 가 같은 키가 된다.
        XCTAssertNotEqual(MultipeerTradeTransport.tiebreakKey(displayName: "ab", code: "c"),
                          MultipeerTradeTransport.tiebreakKey(displayName: "a", code: "bc"))
    }

    // MARK: NB2 — 응답 없이 만료된 초대가 남아 그 상대의 이후 초대를 계속 거절하면 안 된다.

    func testExpiredInvitationIsClearedWhenNoNewerInvitationWentOut() {
        XCTAssertTrue(MultipeerTradeTransport.shouldClearExpiredInvitation(
            currentGeneration: 1, expiringGeneration: 1, hasPartner: false))
    }

    func testExpiryOfAnOlderInvitationLeavesTheNewerOneAlone() {
        // 먼저 건 타이머가 뒤늦게 깨어나 방금 나간 초대를 지우면, 그 초대가 교차했을 때 양쪽이 수락해
        // 연결이 둘 생긴다 — 정확히 C2 가 막으려던 상태로 돌아간다.
        XCTAssertFalse(MultipeerTradeTransport.shouldClearExpiredInvitation(
            currentGeneration: 2, expiringGeneration: 1, hasPartner: false))
    }

    func testExpiryDoesNothingOnceAPartnerIsFixed() {
        XCTAssertFalse(MultipeerTradeTransport.shouldClearExpiredInvitation(
            currentGeneration: 1, expiringGeneration: 1, hasPartner: true))
    }

    func testClearedInvitationLetsThatPeerBeAcceptedAgain() {
        // 만료 정리의 목적 — 지운 뒤에는 그 상대의 초대가 tiebreak 에 걸리지 않고 통과해야 한다.
        let myKey = MultipeerTradeTransport.tiebreakKey(displayName: "Alice", code: "AAAA")
        let theirKey = MultipeerTradeTransport.tiebreakKey(displayName: "Bob", code: "BBBB")
        XCTAssertFalse(MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: "Bob", myKey: myKey, theirKey: theirKey),
            "while our invitation is live the lower-keyed side must refuse")
        XCTAssertTrue(MultipeerTradeTransport.shouldAccept(
            invitationFrom: "Bob", partner: nil, invited: nil, myKey: myKey, theirKey: theirKey),
            "once the expired invitation is cleared their invitation must be accepted")
    }
}
