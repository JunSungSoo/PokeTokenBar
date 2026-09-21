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
        addTeardownBlock { listenerSide.disconnect() }
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
        addTeardownBlock { connectorSide.disconnect() }

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

    /// R20 회귀 — 상대가 연결을 끊으면 이쪽의 `connection` 이 비워져야 한다. 그렇지 않으면 죽은
    /// NWConnection 에 대한 send 가 에러 없이 "성공"해 버려, TradeSession.confirmLocalCommit() 이
    /// 실제로는 전달되지 않은 메시지를 전달된 것처럼 취급하는 desync 로 이어진다.
    func testSendAfterPeerDisconnectionThrowsSendFailed() throws {
        let listenerSide = ManualTradeTransport()
        addTeardownBlock { listenerSide.disconnect() }
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
        addTeardownBlock { connectorSide.disconnect() }

        let listenerConnected = expectation(description: "listener connected")
        let connectorConnected = expectation(description: "connector connected")
        listenerSide.onConnected = { listenerConnected.fulfill() }
        connectorSide.onConnected = { connectorConnected.fulfill() }
        try connectorSide.connectManually(code: code)
        wait(for: [listenerConnected, connectorConnected], timeout: 5)

        let connectorNoticedDisconnect = expectation(description: "connector noticed peer disconnect")
        connectorNoticedDisconnect.assertForOverFulfill = true
        connectorSide.onDisconnected = { connectorNoticedDisconnect.fulfill() }
        listenerSide.disconnect()
        wait(for: [connectorNoticedDisconnect], timeout: 5)

        XCTAssertThrowsError(try connectorSide.send(.accept)) { error in
            XCTAssertEqual(error as? TradeTransportError, .sendFailed)
        }
    }

    /// R21 회귀 — 이전 버전은 "completion 이 한 번 불렸다"만 확인해 "최소 한 번"만 검증했다(두 번째 전이를
    /// 유발하지 않았으므로 assertForOverFulfill 이 잡을 게 없었다). 여기서는 성공 후 disconnect() 로
    /// 리스너를 취소해 stateUpdateHandler(.cancelled) 가 다시 callCompletionOnce 를 부르게 만들고,
    /// OneShotGate 가 그 두 번째 호출을 억제하는지 실제로 검증한다.
    func testStartListeningCompletionFiresExactlyOnce() throws {
        let transport = ManualTradeTransport()
        addTeardownBlock { transport.disconnect() }
        let completionCalled = expectation(description: "completion called once")
        completionCalled.assertForOverFulfill = true
        transport.startListening { _ in
            completionCalled.fulfill()
        }
        wait(for: [completionCalled], timeout: 5)

        transport.disconnect()   // 리스너를 취소 — .cancelled 재진입으로 두 번째 completion 호출을 유발한다.
        let settled = expectation(description: "allow time for a suppressed second call to surface")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
    }

    /// R22 회귀 — connectManually 를 다시 호출해 다른 상대로 갈아탈 때, 이전 연결을 취소하지 않으면
    /// 옛 상대는 연결이 살아있다고 계속 믿는다(소켓 누수 + 옛 stateUpdateHandler 가 계속 살아있는 문제).
    /// 이전 연결이 실제로 취소됐는지는 상대편(firstListener)이 연결 종료를 감지하는지로 관찰한다 —
    /// self.connection 포인터만 바꿔치기했다면 firstListener 는 영원히 이를 알 수 없다.
    func testReconnectingCancelsPreviousConnection() throws {
        let firstListener = ManualTradeTransport()
        addTeardownBlock { firstListener.disconnect() }
        let secondListener = ManualTradeTransport()
        addTeardownBlock { secondListener.disconnect() }
        let connectorSide = ManualTradeTransport()
        addTeardownBlock { connectorSide.disconnect() }

        let firstListenerCodeReady = expectation(description: "first listener started")
        nonisolated(unsafe) var firstCode: String?
        firstListener.startListening { code in
            firstCode = code
            firstListenerCodeReady.fulfill()
        }
        let secondListenerCodeReady = expectation(description: "second listener started")
        nonisolated(unsafe) var secondCode: String?
        secondListener.startListening { code in
            secondCode = code
            secondListenerCodeReady.fulfill()
        }
        wait(for: [firstListenerCodeReady, secondListenerCodeReady], timeout: 5)
        guard let codeA = firstCode, let codeB = secondCode else {
            throw XCTSkip("이 환경에 로컬 IPv4 주소가 없음 — 로컬 개발 Mac 에서 실행")
        }

        let firstConnected = expectation(description: "connected to first listener")
        firstListener.onConnected = { firstConnected.fulfill() }
        try connectorSide.connectManually(code: codeA)
        wait(for: [firstConnected], timeout: 5)

        let firstListenerNoticedDisconnect = expectation(description: "first listener noticed disconnect")
        firstListener.onDisconnected = { firstListenerNoticedDisconnect.fulfill() }
        let secondConnected = expectation(description: "connected to second listener")
        secondListener.onConnected = { secondConnected.fulfill() }

        try connectorSide.connectManually(code: codeB)   // 상대를 바꿔 재연결 — 이전 연결은 취소돼야 한다.
        wait(for: [firstListenerNoticedDisconnect, secondConnected], timeout: 5)
    }
}
