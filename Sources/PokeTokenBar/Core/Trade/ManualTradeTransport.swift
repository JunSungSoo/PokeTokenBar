import Foundation
import Network

/// completion 이 두 번 호출되는 경로(예: 연결 성공 직후 리스너 취소가 다시 실패 상태를 보고)를 막기 위한
/// 1회성 게이트. 별도 클래스로 분리한 이유는 Swift 6 가 캡처된 지역 var 를 여러 콜백 클로저에서
/// 동시에 접근하는 것을 금지하기 때문 — 참조 타입 안에 상태를 두고 NSLock 으로 보호한다.
private final class OneShotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fireOnce(_ body: () -> Void) {
        lock.lock()
        let alreadyFired = fired
        fired = true
        lock.unlock()
        guard !alreadyFired else { return }
        body()
    }
}

/// 자동 탐색(MultipeerTradeTransport)이 상대를 못 찾을 때의 폴백 — Bonjour 탐색 없이
/// 사람이 IP:포트 코드를 직접 교환해 TCP로 연결한다. 탐색 자체는 하지 않는다(startDiscovery/stopDiscovery 는
/// 의도된 no-op, connect(to:) 는 throw).
/// `listener`/`connection`/`frameBuffer` 는 Network 프레임워크 콜백 큐(쓰기)와 호출자 스레드(읽기,
/// send/disconnect)에서 동시에 접근되므로 NSLock 으로 보호한다 — NetworkReachabilityMonitor 의 lock
/// 관례와 동일하게, 락은 항상 값을 복사/교체하는 짧은 구간만 잡고 onConnected/onDisconnected/onMessageReceived
/// 등 콜백은 락을 놓은 뒤 호출한다(NSLock 은 재진입 불가라, 콜백이 락을 쥔 채로 이 트랜스포트를 재호출하면 데드락).
final class ManualTradeTransport: NSObject, TradeTransport, @unchecked Sendable {
    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)?

    private let lock = NSLock()
    private var listener: NWListener?
    private var connection: NWConnection?
    private var frameBuffer = TCPFrameBuffer()
    /// 현재 연결에 대해 onDisconnected 를 이미 알렸는지 — 종료는 stateUpdateHandler(.failed/.cancelled)
    /// 와 receiveLoop 의 EOF 판정 양쪽에서 감지될 수 있어, 콜백은 그중 먼저 도착한 하나에만 반응해야 한다.
    /// wire(_:) 가 새 연결을 걸 때마다 false 로 리셋된다.
    private var disconnectNotified = false
    private let queue = DispatchQueue(label: "com.poketokenbar.trade-manual")

    /// 상대에게 보여줄 내 연결 코드("ip:port")를 completion 으로 전달한다. 포트는 시스템이 배정하는 임시
    /// 포트(NWEndpoint.Port.any) — 하드코딩된 포트는 같은 Mac 에서 두 인스턴스를 동시에 띄우는 테스트/QA
    /// 시나리오에서 두 번째 바인드가 실패한다. NWListener 는 포트 충돌 등 실패를 생성자가 아니라
    /// stateUpdateHandler(.failed) 로 비동기 보고하므로, completion 은 동기 반환값이 아니라 콜백이어야 한다.
    /// 실패/성공 어느 경로든 completion 은 정확히 한 번만 호출되지만, 호출 시점은 경로마다 다르다 —
    /// 로컬 IPv4 를 못 찾거나 리스너 생성 자체가 실패하면 이 함수가 반환하기 전에(호출자 스레드에서)
    /// 동기 호출되고, 그 외의 성공/실패는 Network 프레임워크 콜백 큐에서 비동기 호출된다. 호출측은
    /// 두 타이밍 모두를 처리해야 한다.
    func startListening(completion: @escaping @Sendable (String?) -> Void) {
        guard let address = Self.currentIPv4Address(),
              let newListener = try? NWListener(using: .tcp, on: .any) else {
            completion(nil)
            return
        }

        let gate = OneShotGate()
        let callCompletionOnce: @Sendable (String?) -> Void = { result in
            gate.fireOnce { completion(result) }
        }

        newListener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.lock()
            // 1:1 교환이라 첫 연결만 받는다. 락을 쥔 채 cancel 하는 것은 이 파일의 "콜백은 락 밖에서" 규율의
            // 의도된 예외 — NWListener.cancel() 은 콜백을 재진입 호출하지 않고 큐로 디스패치한다.
            self.listener?.cancel()
            self.listener = nil
            self.lock.unlock()
            self.wire(connection)
            connection.start(queue: self.queue)
        }
        newListener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                guard let boundPort = newListener.port else {
                    callCompletionOnce(nil)
                    return
                }
                callCompletionOnce("\(address):\(boundPort.rawValue)")
            case .failed, .cancelled:
                callCompletionOnce(nil)
                self?.lock.lock()
                self?.listener = nil
                self?.lock.unlock()
            default:
                break
            }
        }

        lock.lock()
        listener = newListener
        lock.unlock()
        newListener.start(queue: queue)
    }

    /// 상대가 보여준 코드로 직접 연결한다.
    func connectManually(code: String) throws {
        let parts = code.split(separator: ":")
        guard parts.count == 2, let port = UInt16(parts[1]), let nwPort = NWEndpoint.Port(rawValue: port)
        else { throw TradeTransportError.notConnected }
        let connection = NWConnection(host: NWEndpoint.Host(String(parts[0])), port: nwPort, using: .tcp)
        wire(connection)
        connection.start(queue: queue)
    }

    /// 이전 연결이 남아있으면 취소하고(옛 stateUpdateHandler 가 계속 콜백을 쏘는 것을 막는다), 새 연결을 건다.
    /// connectManually 를 연달아 두 번 호출하는 경로(사용자가 코드를 잘못 입력해 다시 시도하는 등)에서 필요하다.
    private func wire(_ connection: NWConnection) {
        lock.lock()
        let previousConnection = self.connection
        self.connection = connection
        frameBuffer = TCPFrameBuffer()
        disconnectNotified = false
        lock.unlock()
        previousConnection?.cancel()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onConnected?()
                self?.receiveLoop(on: connection)
            case .failed, .cancelled:
                self?.handleConnectionTerminated(connection)
            default:
                break
            }
        }
    }

    /// 연결 종료를 딱 한 번만 알린다 — stateUpdateHandler(.failed/.cancelled)와 receiveLoop 의 EOF 판정이
    /// 동시에 도착할 수 있어, 나중에 도착한 신호는 무시한다(R20/R21 계열 — 죽은 연결에 send 가 성공한
    /// 것처럼 보이는 것을 막는다). 이 connection 이 이미 다른 연결로 교체됐다면(wire 가 다시 불렸다면)
    /// 아무 것도 하지 않는다 — 새 연결의 상태를 옛 연결의 종료로 덮어쓰면 안 된다.
    private func handleConnectionTerminated(_ terminatedConnection: NWConnection) {
        lock.lock()
        guard connection === terminatedConnection else {
            lock.unlock()
            return
        }
        connection = nil
        let alreadyNotified = disconnectNotified
        disconnectNotified = true
        lock.unlock()
        guard !alreadyNotified else { return }
        onDisconnected?()
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var decodedMessages: [TradeMessage] = []
            var frameTooLarge = false
            if let data, !data.isEmpty {
                self.lock.lock()
                let frames: [Data]
                do {
                    frames = try self.frameBuffer.append(data)
                } catch {
                    frames = []
                    frameTooLarge = true
                }
                self.lock.unlock()
                for frame in frames {
                    if let message = try? JSONDecoder().decode(TradeMessage.self, from: frame) {
                        decodedMessages.append(message)
                    } else {
                        // 버전이 달라 해석 못 한 프레임과 "상대가 아예 제안을 안 했다" 를 로그에서 구분한다.
                        AppLog.write("trade: undecodable manual frame (\(frame.count) bytes)")
                    }
                }
            }
            for message in decodedMessages {
                self.onMessageReceived?(message)
            }
            if frameTooLarge {
                connection.cancel()   // 조작된 길이 프리픽스 — 조용히 멈추는 대신 연결을 끊는다(R23).
                self.handleConnectionTerminated(connection)
            } else if isComplete || error != nil {
                self.handleConnectionTerminated(connection)
            } else {
                self.receiveLoop(on: connection)
            }
        }
    }

    // 자동 탐색은 지원하지 않는다(수동 연결 전용).
    func startDiscovery() {}
    func stopDiscovery() {}
    func connect(to peer: TradePeer) throws { throw TradeTransportError.notConnected }

    func send(_ message: TradeMessage) throws {
        lock.lock()
        let currentConnection = connection
        lock.unlock()
        guard let currentConnection else { throw TradeTransportError.sendFailed }
        guard let data = try? JSONEncoder().encode(message) else { throw TradeTransportError.sendFailed }
        currentConnection.send(content: TCPFrameBuffer.frame(data), completion: .contentProcessed { _ in })
    }

    func disconnect() {
        lock.lock()
        let currentConnection = connection
        let currentListener = listener
        connection = nil
        listener = nil
        frameBuffer = TCPFrameBuffer()   // 다음 연결의 프레이밍을 이전 연결의 잔여 바이트로 오염시키지 않는다.
        let alreadyNotified = disconnectNotified
        disconnectNotified = true
        lock.unlock()
        currentConnection?.cancel()
        currentListener?.cancel()
        // connection 이 있었을 때만 알린다 — 연결 전(리스너만 취소하는 경우)엔 아무 것도 끊어진 게 없다.
        // NWConnection.cancel() 의 나중 stateUpdateHandler(.cancelled) 콜백은 connection 이 이미 nil 이라
        // handleConnectionTerminated 에서 조용히 무시된다(중복 통지 방지).
        if currentConnection != nil, !alreadyNotified {
            onDisconnected?()
        }
    }

    /// en0/en1 IPv4 — Mac 의 일반적인 Wi-Fi/이더넷 인터페이스만 본다(가상/루프백 인터페이스 제외).
    static func currentIPv4Address() -> String? {
        var address: String?
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }
        for pointer in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                       &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: hostBuffer)
            break
        }
        return address
    }
}
