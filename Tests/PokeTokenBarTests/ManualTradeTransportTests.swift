import XCTest
@testable import PokeTokenBar

final class ManualTradeTransportTests: XCTestCase {
    func testConnectManuallyRejectsMalformedCode() {
        let transport = ManualTradeTransport()
        XCTAssertThrowsError(try transport.connectManually(code: "not-a-valid-code"))
    }

    func testSendBeforeConnectionThrowsSendFailed() {
        let transport = ManualTradeTransport()
        XCTAssertThrowsError(try transport.send(.accept)) { error in
            XCTAssertEqual(error as? TradeTransportError, .sendFailed)
        }
    }

    func testLoopbackConnectionExchangesOneMessage() throws {
        let listenerSide = ManualTradeTransport()
        let listeningStarted = expectation(description: "listener started")
        nonisolated(unsafe) var listenerCode: String?
        listenerSide.startListening { code in
            listenerCode = code
            listeningStarted.fulfill()
        }
        wait(for: [listeningStarted], timeout: 5)
        guard let code = listenerCode else {
            throw XCTSkip("이 환경에 로컬 IPv4 주소가 없음 — 로컬 개발 Mac 에서 실행")
        }
        let connectorSide = ManualTradeTransport()

        let listenerConnected = expectation(description: "listener connected")
        let connectorConnected = expectation(description: "connector connected")
        let messageReceived = expectation(description: "message received")
        listenerSide.onConnected = { listenerConnected.fulfill() }
        connectorSide.onConnected = { connectorConnected.fulfill() }
        listenerSide.onMessageReceived = { message in
            guard case .accept = message else { return }
            messageReceived.fulfill()
        }

        try connectorSide.connectManually(code: code)
        wait(for: [listenerConnected, connectorConnected], timeout: 5)
        try connectorSide.send(.accept)
        wait(for: [messageReceived], timeout: 5)
    }

    /// startListening 의 completion 은 실패해도 정확히 한 번 호출돼야 한다 — 잘못된 포트 범위를 강제로 만들 수는
    /// 없으므로, 로컬 IPv4 주소가 없는 환경을 흉내낼 수 없는 대신 정상 경로에서 completion 이 정확히 1회만 불리는지 확인한다.
    func testStartListeningCompletionFiresExactlyOnce() throws {
        let transport = ManualTradeTransport()
        let completionCalled = expectation(description: "completion called once")
        completionCalled.assertForOverFulfill = true
        transport.startListening { _ in
            completionCalled.fulfill()
        }
        wait(for: [completionCalled], timeout: 5)
    }
}
