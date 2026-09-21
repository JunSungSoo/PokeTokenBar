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
    /// `lazy` 였을 때 첫 접근이 호출자 스레드(connect/send/disconnect)와 프레임워크 큐(광고자 델리게이트)
    /// 사이에서 경쟁했다 — 이 클래스의 다른 공유 필드와 달리 락 밖이었다. init 에서 만들어 경쟁 자체를 없앤다.
    private let session: MCSession
    private let lock = NSLock()
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var discoveredPeers: [String: MCPeerID] = [:]
    /// 지금 교환 중인 단 한 명 — MCSession 은 다자 연결이 가능하므로 1:1 제약은 이 계층이 강제한다.
    private var partnerPeerID: MCPeerID?
    /// 내가 방금 초대한 상대 — 초대가 교차했는지 판정하는 데만 쓴다.
    private var invitedPeerID: MCPeerID?

    /// nickname 은 Settings 에서 자유롭게 입력한 텍스트라 비어있거나 63바이트를 넘을 수 있다 —
    /// MCPeerID(displayName:) 는 그런 값에 트랩하므로 생성 전에 반드시 클램프한다(Ruling R5).
    init(nickname: String, code: String) {
        let peerID = MCPeerID(displayName: Self.clampNickname(nickname, fallback: Host.current().localizedName ?? "PokeTokenBar"))
        myPeerID = peerID
        self.code = code
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        super.init()
        session.delegate = self
    }

    /// 초대가 교차했을 때 누가 수락할지 정하는 전역 순서. 닉네임 기본값이 컴퓨터 이름이라 두 기기가
    /// 같은 이름을 쓸 수 있어 닉네임만으론 순서가 없다 — 기기마다 고유한 교환 코드를 함께 넣는다.
    static func tiebreakKey(displayName: String, code: String?) -> String {
        "\(displayName)\u{0}\(code ?? "")"
    }

    /// 초대 수락 여부 — 프레임워크 콜백 없이 검증할 수 있게 순수 판정으로 분리한다.
    /// 상대가 이미 정해졌으면 그 상대만 받는다(제3자가 끼면 send 가 두 명에게 브로드캐스트된다).
    /// 내가 먼저 초대한 상대에게서 초대가 되돌아오면 교차다 — 키가 큰 쪽만 수락해 연결을 하나로 만든다.
    /// 코드가 기기마다 달라 키가 같을 수는 없고, 그래도 같다면 `>=` 가 교착 대신 현행 동작으로 떨어진다.
    static func shouldAccept(invitationFrom peer: String, partner: String?, invited: String?,
                             myKey: String, theirKey: String) -> Bool {
        if let partner { return partner == peer }
        guard invited == peer else { return true }
        return myKey >= theirKey
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
        let alreadyPaired = partnerPeerID != nil
        if let mcPeer, currentBrowser != nil, !alreadyPaired { invitedPeerID = mcPeer }
        lock.unlock()

        // 상대가 더 이상 discoveredPeers 에 없는 경우를 나타내는 전용 케이스가 없어 notConnected 를 재사용한다.
        guard let mcPeer, let currentBrowser, !alreadyPaired else { throw TradeTransportError.notConnected }
        // 교차 초대 판정에 쓸 내 코드를 실어 보낸다 — 받는 쪽은 discoveryInfo 없이 이 값만으로 순서를 정한다.
        currentBrowser.invitePeer(mcPeer, to: session, withContext: Data(code.utf8), timeout: 15)
    }

    func send(_ message: TradeMessage) throws {
        lock.lock()
        let partner = partnerPeerID
        lock.unlock()
        // 목적지를 connectedPeers 가 아니라 확정된 상대 한 명으로 한정한다 — 제3자가 세션에 남아 있어도
        // 내 오퍼/승인이 그쪽으로 함께 나가지 않는다.
        guard let partner, session.connectedPeers.contains(partner) else { throw TradeTransportError.sendFailed }
        guard let data = try? JSONEncoder().encode(message) else { throw TradeTransportError.sendFailed }
        do {
            try session.send(data, toPeers: [partner], with: .reliable)
        } catch {
            throw TradeTransportError.sendFailed
        }
    }

    func disconnect() {
        lock.lock()
        partnerPeerID = nil
        invitedPeerID = nil
        lock.unlock()
        session.disconnect()
    }
}

extension MultipeerTradeTransport: MCSessionDelegate {
    /// 교환 상대가 아닌 피어의 상태 변화는 흘려보낸다 — 제3자가 떠나는 것이 진행 중인 교환을 끊거나
    /// 화면을 처음으로 되돌리면 안 된다.
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            lock.lock()
            if partnerPeerID == nil { partnerPeerID = peerID }
            if invitedPeerID == peerID { invitedPeerID = nil }
            let isPartner = partnerPeerID == peerID
            lock.unlock()
            guard isPartner else { return }
            onConnected?()
        case .notConnected:
            lock.lock()
            let isPartner = partnerPeerID == peerID
            if isPartner { partnerPeerID = nil }
            if invitedPeerID == peerID { invitedPeerID = nil }
            lock.unlock()
            guard isPartner else { return }
            onDisconnected?()
        case .connecting: break
        @unknown default: break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        lock.lock()
        let isPartner = partnerPeerID == peerID
        lock.unlock()
        guard isPartner else { return }
        guard let message = try? JSONDecoder().decode(TradeMessage.self, from: data) else {
            // 버전이 달라 해석 못 한 메시지와 "상대가 아예 제안을 안 했다" 를 로그에서 구분하기 위한 한 줄.
            AppLog.write("trade: undecodable multipeer message (\(data.count) bytes) from \(peerID.displayName)")
            return
        }
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
    /// 초대는 1:1 이 지켜지는 범위에서만 수락한다(`shouldAccept` 참조) — 신원 확인은 이후 Hello 메시지의
    /// 닉네임/코드 표시로 사람이 한다.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        lock.lock()
        let partner = partnerPeerID?.displayName
        let invited = invitedPeerID?.displayName
        lock.unlock()

        let theirCode = context.flatMap { String(data: $0, encoding: .utf8) }
        let accepted = Self.shouldAccept(invitationFrom: peerID.displayName, partner: partner, invited: invited,
                                         myKey: Self.tiebreakKey(displayName: myPeerID.displayName, code: code),
                                         theirKey: Self.tiebreakKey(displayName: peerID.displayName, code: theirCode))
        invitationHandler(accepted, accepted ? session : nil)
    }
}
