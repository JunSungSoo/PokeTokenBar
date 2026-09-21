import Foundation
import MultipeerConnectivity

/// 같은 Wi-Fi/LAN 또는 블루투스 범위의 상대를 자동으로 찾아 연결하는 기본 트랜스포트.
/// Wi-Fi/블루투스 중 무엇을 쓸지는 프레임워크가 알아서 고른다 — 두 계층을 따로 구현하지 않는다.
/// MCSession 델리게이트는 프레임워크 자체 큐에서 호출되므로 이 클래스는 @MainActor 가 아니다 —
/// 소비자(TradeSession)가 Task { @MainActor in … } 로 직접 hop 한다(NetworkReachabilityMonitor 와 동일 관례).
/// `discoveredPeers`/`advertiser`/`browser` 는 델리게이트 큐(쓰기)와 호출자 스레드(읽기)에서 동시에
/// 접근되므로 NSLock 으로 보호한다(Ruling R19) — NetworkReachabilityMonitor 의 lock 관례와 동일하게,
/// 락은 항상 값을 복사/교체하는 짧은 구간만 잡고 onPeerFound/onPeerLost 등 콜백은 락을 놓은 뒤 호출한다.
final class MultipeerTradeTransport: NSObject, TradeTransport, @unchecked Sendable {
    /// Bonjour 서비스 타입 — 1~15자, 소문자/숫자/하이픈만(애플 규격).
    static let serviceType = "ptb-trade"
    /// discoveryInfo 딕셔너리의 코드 키 — startDiscovery 와 makeTradePeer 양쪽에서 공유해 값이 드리프트할 여지를 없앤다.
    static let discoveryInfoCodeKey = "code"

    var onPeerFound: (@Sendable (TradePeer) -> Void)?
    var onPeerLost: (@Sendable (String) -> Void)?
    var onConnected: (@Sendable () -> Void)?
    var onDisconnected: (@Sendable () -> Void)?
    var onMessageReceived: (@Sendable (TradeMessage) -> Void)?

    private let myPeerID: MCPeerID
    private let code: String
    private lazy var session: MCSession = {
        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }()
    private let lock = NSLock()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var discoveredPeers: [String: MCPeerID] = [:]

    /// nickname 은 Settings 에서 자유롭게 입력한 텍스트라 비어있거나 63바이트를 넘을 수 있다 —
    /// MCPeerID(displayName:) 는 그런 값에 트랩하므로 생성 전에 반드시 클램프한다(Ruling R5).
    init(nickname: String, code: String) {
        myPeerID = MCPeerID(displayName: Self.clampNickname(nickname, fallback: Host.current().localizedName ?? "PokeTokenBar"))
        self.code = code
        super.init()
    }

    /// discoveryInfo 파싱을 순수 함수로 분리 — 네트워크 스택 없이 단위 테스트 가능하게 한다.
    static func makeTradePeer(displayName: String, discoveryInfo: [String: String]?) -> TradePeer {
        TradePeer(id: displayName, nickname: displayName, code: discoveryInfo?[discoveryInfoCodeKey] ?? "????")
    }

    /// MCPeerID(displayName:) 는 비어있지 않고 UTF-8 로 63바이트 이하인 이름을 요구하며 위반 시 트랩한다.
    /// 빈 값은 fallback 으로 대체하고, 긴 값은 바이트 예산으로 자른다(한글/일본어는 문자당 여러 바이트라
    /// 문자 수 기준으로 자르면 예산을 넘길 수 있다).
    static func clampNickname(_ nickname: String, fallback: String) -> String {
        let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        guard trimmed.utf8.count > 63 else { return trimmed }
        var truncated = trimmed
        while truncated.utf8.count > 63 {
            truncated.removeLast()
        }
        return truncated.isEmpty ? fallback : truncated
    }

    func startDiscovery() {
        let newAdvertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: [Self.discoveryInfoCodeKey: code],
                                                       serviceType: Self.serviceType)
        newAdvertiser.delegate = self

        let newBrowser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        newBrowser.delegate = self

        lock.lock()
        advertiser = newAdvertiser
        browser = newBrowser
        lock.unlock()

        newAdvertiser.startAdvertisingPeer()
        newBrowser.startBrowsingForPeers()
    }

    func stopDiscovery() {
        lock.lock()
        let currentAdvertiser = advertiser
        let currentBrowser = browser
        advertiser = nil
        browser = nil
        lock.unlock()

        currentAdvertiser?.stopAdvertisingPeer()
        currentBrowser?.stopBrowsingForPeers()
    }

    func connect(to peer: TradePeer) throws {
        lock.lock()
        let mcPeer = discoveredPeers[peer.id]
        let currentBrowser = browser
        lock.unlock()

        // 상대가 더 이상 discoveredPeers 에 없는 경우를 나타내는 전용 케이스가 없어 notConnected 를 재사용한다.
        guard let mcPeer, let currentBrowser else { throw TradeTransportError.notConnected }
        currentBrowser.invitePeer(mcPeer, to: session, withContext: nil, timeout: 15)
    }

    func send(_ message: TradeMessage) throws {
        guard !session.connectedPeers.isEmpty else { throw TradeTransportError.sendFailed }
        guard let data = try? JSONEncoder().encode(message) else { throw TradeTransportError.sendFailed }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            throw TradeTransportError.sendFailed
        }
    }

    func disconnect() {
        session.disconnect()
    }
}

extension MultipeerTradeTransport: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected: onConnected?()
        case .notConnected: onDisconnected?()
        case .connecting: break
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(TradeMessage.self, from: data) else { return }
        onMessageReceived?(message)
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension MultipeerTradeTransport: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        lock.lock()
        discoveredPeers[peerID.displayName] = peerID
        lock.unlock()
        onPeerFound?(Self.makeTradePeer(displayName: peerID.displayName, discoveryInfo: info))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        lock.lock()
        discoveredPeers.removeValue(forKey: peerID.displayName)
        lock.unlock()
        onPeerLost?(peerID.displayName)
    }
}

extension MultipeerTradeTransport: MCNearbyServiceAdvertiserDelegate {
    /// 내부용 기능이라 초대는 항상 자동 수락 — 신원 확인은 이후 Hello 메시지의 닉네임/코드 표시로 사람이 한다.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}
