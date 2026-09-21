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

/// 자동 탐색(MultipeerTradeTransport)이 상대를 못 찾을 때의 폴백 — Bonjour/블루투스 탐색 없이
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
    private let queue = DispatchQueue(label: "com.poketokenbar.trade-manual")

    /// 상대에게 보여줄 내 연결 코드("ip:port")를 completion 으로 전달한다. 포트는 시스템이 배정하는 임시
    /// 포트(NWEndpoint.Port.any) — 하드코딩된 포트는 같은 Mac 에서 두 인스턴스를 동시에 띄우는 테스트/QA
    /// 시나리오에서 두 번째 바인드가 실패한다. NWListener 는 포트 충돌 등 실패를 생성자가 아니라
    /// stateUpdateHandler(.failed) 로 비동기 보고하므로, completion 은 동기 반환값이 아니라 콜백이어야 한다.
    /// 실패/성공 어느 경로든 completion 은 정확히 한 번만 호출된다.
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
            self.listener?.cancel()   // 1:1 교환이라 첫 연결만 받는다
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

    private func wire(_ connection: NWConnection) {
        lock.lock()
        self.connection = connection
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onConnected?()
                self?.receiveLoop(on: connection)
            case .failed, .cancelled:
                self?.onDisconnected?()
            default:
                break
            }
        }
    }

    private func receiveLoop(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var decodedMessages: [TradeMessage] = []
            if let data, !data.isEmpty {
                self.lock.lock()
                let frames = self.frameBuffer.append(data)
                self.lock.unlock()
                for frame in frames {
                    if let message = try? JSONDecoder().decode(TradeMessage.self, from: frame) {
                        decodedMessages.append(message)
                    }
                }
            }
            for message in decodedMessages {
                self.onMessageReceived?(message)
            }
            if isComplete || error != nil {
                self.onDisconnected?()
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
        lock.unlock()
        currentConnection?.cancel()
        currentListener?.cancel()
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
