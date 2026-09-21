import AppKit
import SwiftUI

/// 팝오버 "교환" 탭 — 내 신원 표시, 상대 탐색(자동→수동 폴백), 제안 구성, 승인, 커밋 결과 안내까지
/// 한 화면에서 진행한다.
@MainActor
struct TradeView: View {
    let store: CompanionStore

    /// 수동 폴백의 리스너 상태. "아직 준비 중"과 "만들지 못함"을 `String?` 하나로 합치면 준비 중인
    /// 몇 밀리초 동안 실패 안내가 뜬다.
    private enum ManualListener {
        case preparing
        case ready(code: String)
        case unavailable
    }

    /// `TradeItem` 이 Equatable 이 아니라 이 enum 도 Equatable 이 될 수 없다 — 단계 확인은 `==` 이 아니라
    /// `if case`/`switch` 패턴 매칭으로만 한다.
    private enum Phase {
        case idle
        case searching
        case manualFallback(listener: ManualListener, connecting: Bool)
        case pickingOffer
        case waitingForPeerOffer
        case reviewingProposal(mine: TradeItem, theirs: TradeItem)
        case waitingForPeerAccept
        /// 로컬 커밋(백업+상태 반영)이 끝나고 상대의 commitAck 를 기다리는 중 — 여기서 끊기면 이미
        /// 되돌릴 수 없는 변경이 일어난 뒤라 `.uncertain` 으로 간다.
        case committing
        case completed
        case rejected
        /// 백업 실패로 적용 자체가 취소된 경우 — 바뀐 게 없으므로 백업 안내가 목적인 `.uncertain` 과 구분한다.
        case commitFailed
        case uncertain
    }

    /// 자동 탐색을 포기하고 수동 코드 교환으로 넘어가기까지의 대기 시간.
    private static let discoveryTimeoutNanoseconds: UInt64 = 10_000_000_000

    @State private var phase: Phase = .idle
    @State private var multipeerTransport: MultipeerTradeTransport?
    @State private var manualTransport: ManualTradeTransport?
    @State private var session: TradeSession?
    @State private var discoveredPeers: [TradePeer] = []
    @State private var connectedPeer: TradePeer?
    @State private var manualCodeInput = ""
    @State private var manualCodeInvalid = false
    @State private var discoveryTimeout: Task<Void, Never>?
    @State private var lastBackupURL: URL?

    private var l: L { store.l }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            identityHeader
            Divider()
            phaseContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 신원 헤더

    private var identityHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(TradeIdentity.nickname()).font(.headline)
            Text("\(l.tradeMyCode): \(TradeIdentity.code())")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let connectedPeer {
                Text("\(l.tradeConnectedTo): \(connectedPeer.nickname) (\(connectedPeer.code))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 단계별 본문

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .idle:
            Button(l.tradeFindPeers) { startAutomaticDiscovery() }
        case .searching:
            searchingContent
        case .manualFallback(let listener, let connecting):
            manualFallbackContent(listener: listener, connecting: connecting)
        case .pickingOffer:
            offerPicker
        case .waitingForPeerOffer:
            waitingWithRepick(l.tradeWaitingForPeerOffer)
        case .reviewingProposal(let mine, let theirs):
            TradeProposalSheet(
                myOffer: mine,
                theirOffer: theirs,
                overwriteWarning: store.tradeOverwriteWarning(forReceiving: theirs),
                l: l,
                onAccept: { acceptProposal() },
                onReject: { rejectProposal() })
        case .waitingForPeerAccept:
            waitingWithRepick(l.tradeWaitingForPeerAccept)
        case .committing:
            VStack(alignment: .leading, spacing: 8) {
                waitingRow(l.tradeWaitingForPeerConfirm)
                backupHint
                Button(l.close) { resetToIdle() }
            }
        case .completed:
            outcomeContent(title: l.tradeCompleted, showsBackupHint: true)
        case .uncertain:
            outcomeContent(title: l.tradeUncertain, showsBackupHint: true)
        case .commitFailed:
            outcomeContent(title: l.tradeCommitFailed, showsBackupHint: false)
        case .rejected:
            outcomeContent(title: l.tradeRejectedByPeer, showsBackupHint: false)
        }
    }

    private var searchingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            waitingRow(l.tradeSearching)
            ForEach(discoveredPeers) { peer in
                Button("\(peer.nickname) (\(peer.code))") { connect(to: peer) }
            }
            Button(l.cancel) { resetToIdle() }
        }
    }

    private func manualFallbackContent(listener: ManualListener, connecting: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.tradeAutoDiscoveryFailed)
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            switch listener {
            case .preparing:
                Text(l.tradeManualCodePreparing).font(.caption).foregroundStyle(.secondary)
            case .ready(let code):
                Text("\(l.tradeManualMyCode): \(code)")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            case .unavailable:
                Text(l.tradeManualCodeUnavailable)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if connecting {
                // 상대 주소가 응답만 안 하는 경우엔 트랜스포트가 아무 신호도 주지 않는다 — 실패를 단정하지
                // 않고 진행 중으로만 두되, 코드를 다시 입력할 수 있게 되돌아갈 길을 항상 남긴다.
                waitingRow(l.tradeManualConnecting)
                Button(l.cancel) { cancelManualConnecting() }
            } else {
                TextField(l.tradeManualEnterCode, text: $manualCodeInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { connectManually() }
                if manualCodeInvalid {
                    Text(l.tradeManualCodeInvalid)
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Button(l.tradeManualConnect) { connectManually() }
                    Button(l.cancel) { resetToIdle() }
                }
            }
        }
    }

    private var offerPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l.tradeSelectOffer).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if let active = store.state.active {
                        offerRow(item: .activeMon(active), badge: l.dexRaising)
                    }
                    ForEach(store.state.dex) { entry in
                        offerRow(item: .dexEntry(entry), badge: nil)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
            Button(l.cancel) { resetToIdle() }
        }
    }

    private func offerRow(item: TradeItem, badge: String?) -> some View {
        Button {
            propose(item)
        } label: {
            HStack(spacing: 6) {
                Text(offerLabel(for: item))
                if let badge {
                    Text(badge).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(l.rarityLabel(item.rarity)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func waitingWithRepick(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            waitingRow(message)
            Button(l.tradeSelectOffer) { returnToOfferPicker() }
            Button(l.cancel) { resetToIdle() }
        }
    }

    private func outcomeContent(title: String, showsBackupHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if showsBackupHint { backupHint }
            Button(l.close) { resetToIdle() }
        }
    }

    private func waitingRow(_ message: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var backupHint: some View {
        if let lastBackupURL {
            VStack(alignment: .leading, spacing: 6) {
                Text(l.tradeBackupHint(fileName: lastBackupURL.lastPathComponent))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                // 폴더가 아니라 이번 백업 파일을 선택한 채로 연다 — 여러 백업 중 어떤 게 이번 것인지 헷갈리지 않게.
                Button(l.tradeOpenBackupFolder) {
                    NSWorkspace.shared.activateFileViewerSelecting([lastBackupURL])
                }
            }
        }
    }

    /// 내 육성 중 개체는 로드된 진화 라인에 이름이 있으면 그걸 쓴다 — `TradeItem.displayName` 은 교환
    /// 페이로드만 보므로 육성 중 개체에 대해서는 `#id` 로 떨어진다.
    private func offerLabel(for item: TradeItem) -> String {
        if case .activeMon(let mon) = item,
           let name = store.currentLine?.localizedName(mon.currentID, store.language) {
            return name
        }
        return item.displayName(language: store.language)
    }

    // MARK: 연결

    private func startAutomaticDiscovery() {
        let transport = MultipeerTradeTransport(nickname: TradeIdentity.nickname(), code: TradeIdentity.code())
        transport.onPeerFound = { peer in Task { @MainActor in addDiscoveredPeer(peer) } }
        transport.onPeerLost = { peerID in
            Task { @MainActor in discoveredPeers.removeAll { $0.id == peerID } }
        }
        multipeerTransport = transport
        // 세션은 연결 **전에** 만든다 — 초대를 받는 쪽도 트랜스포트의 onConnected 를 세션이 쥐고 있어야
        // Hello 를 주고받는다. 연결된 뒤에 만들면 그 쪽은 영영 상대를 식별하지 못한다.
        startSession(with: transport)
        transport.startDiscovery()
        phase = .searching
        discoveryTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.discoveryTimeoutNanoseconds)
            guard !Task.isCancelled, case .searching = phase, discoveredPeers.isEmpty else { return }
            transport.stopDiscovery()
            fallBackToManual()
        }
    }

    private func addDiscoveredPeer(_ peer: TradePeer) {
        guard !discoveredPeers.contains(where: { $0.id == peer.id }) else { return }
        discoveredPeers.append(peer)
    }

    /// 수동 폴백 진입. `startListening` 의 completion 은 로컬 IPv4 부재/리스너 생성 실패면 동기로,
    /// 그 외 경로는 Network 콜백 큐에서 비동기로 정확히 한 번 온다 — 어느 타이밍이든 도착한 결과로
    /// 단계를 갱신할 수 있게, 단계를 먼저 `.preparing` 으로 세운 뒤 듣기를 시작한다.
    private func fallBackToManual() {
        // 자동 탐색은 여기서 끝난다 — 광고/탐색을 켠 채로 두면 상대는 이미 지나간 후보 목록에 계속 잡힌다.
        multipeerTransport?.disconnect()
        multipeerTransport = nil
        discoveredPeers = []
        let transport = ManualTradeTransport()
        manualTransport = transport
        startSession(with: transport)
        phase = .manualFallback(listener: .preparing, connecting: false)
        transport.startListening { code in
            Task { @MainActor in applyManualListening(code: code) }
        }
    }

    private func applyManualListening(code: String?) {
        guard case .manualFallback(_, let connecting) = phase else { return }
        phase = .manualFallback(listener: code.map { .ready(code: $0) } ?? .unavailable, connecting: connecting)
    }

    private func connect(to peer: TradePeer) {
        guard let multipeerTransport else { return }
        discoveryTimeout?.cancel()
        try? multipeerTransport.connect(to: peer)
    }

    private func connectManually() {
        guard let manualTransport, case .manualFallback(let listener, false) = phase else { return }
        let code = manualCodeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        do {
            try manualTransport.connectManually(code: code)
            manualCodeInvalid = false
            phase = .manualFallback(listener: listener, connecting: true)
        } catch {
            manualCodeInvalid = true
        }
    }

    /// 취소해도 트랜스포트를 끊지 않는다 — 리스너를 공유하고 있어 끊으면 내 연결 코드까지 죽는다.
    /// 대기 중이던 연결은 다음 `connectManually` 가 `wire` 에서 교체한다.
    private func cancelManualConnecting() {
        guard case .manualFallback(let listener, true) = phase else { return }
        phase = .manualFallback(listener: listener, connecting: false)
    }

    // MARK: 세션

    private func startSession(with transport: any TradeTransport) {
        let newSession = TradeSession(transport: transport)
        newSession.onPeerIdentified = { identity in
            connectedPeer = TradePeer(id: identity.code, nickname: identity.nickname, code: identity.code)
            switch phase {
            case .searching, .manualFallback:
                discoveryTimeout?.cancel()
                multipeerTransport?.stopDiscovery()
                phase = .pickingOffer
            default:
                break
            }
        }
        newSession.onOffersReady = { mine, theirs in
            // 어느 쪽 오퍼가 바뀌든 세션이 양쪽 Accept 를 무효화하므로 심사 단계로 되돌아온다.
            // 커밋 이후 도착한 오퍼는 무시한다 — 이미 적용이 끝난 교환을 다시 승인시킬 수는 없다.
            switch phase {
            case .committing, .completed, .uncertain, .commitFailed, .rejected:
                break
            default:
                phase = .reviewingProposal(mine: mine, theirs: theirs)
            }
        }
        newSession.onReadyToCommit = { received in
            // `sending:` 은 반드시 로컬 제안이어야 한다 — 상대가 echo 한 값을 넣으면 정규화 없이 임의
            // 도감 항목을 지우는 통로가 된다(CompanionStore.applyTradeCommit 계약).
            guard let myOffer = newSession.myOffer else { return }
            do {
                lastBackupURL = try store.applyTradeCommit(sending: myOffer, receiving: received)
            } catch {
                // 백업을 못 남겨 적용이 취소됐다 — commitAck 를 보내지 않아 상대도 미확정으로 남는다
                // (양쪽 다 로컬 상태가 그대로인 안전한 방향의 실패).
                phase = .commitFailed
                newSession.disconnect()
                return
            }
            phase = .committing
            newSession.confirmLocalCommit()
        }
        newSession.onCompleted = { phase = .completed }
        newSession.onRejected = { _ in
            teardownConnection()
            phase = .rejected
        }
        newSession.onDisconnected = {
            switch phase {
            case .committing:
                phase = .uncertain   // 이미 되돌릴 수 없는 로컬 변경이 끝난 뒤다
            case .manualFallback(let listener, true):
                phase = .manualFallback(listener: listener, connecting: false)
            case .idle, .searching, .manualFallback, .completed, .uncertain, .commitFailed, .rejected:
                break
            default:
                resetToIdle()
            }
        }
        session = newSession
    }

    private func propose(_ item: TradeItem) {
        session?.proposeOffer(item)
        // 상대 오퍼가 이미 와 있으면 proposeOffer 안에서 심사 단계로 넘어간다 — 그 결과를 덮지 않는다.
        if case .pickingOffer = phase { phase = .waitingForPeerOffer }
    }

    private func returnToOfferPicker() {
        session?.withdrawOffer()
        phase = .pickingOffer
    }

    private func acceptProposal() {
        session?.accept()
        // 상대가 먼저 승인해 뒀다면 accept() 안에서 커밋까지 진행된다 — 그 결과를 덮지 않는다.
        if case .reviewingProposal = phase { phase = .waitingForPeerAccept }
    }

    private func rejectProposal() {
        session?.reject(reason: "user_declined")
        resetToIdle()
    }

    private func teardownConnection() {
        discoveryTimeout?.cancel()
        discoveryTimeout = nil
        session?.disconnect()
        multipeerTransport?.stopDiscovery()
        session = nil
        multipeerTransport = nil
        manualTransport = nil
    }

    private func resetToIdle() {
        teardownConnection()
        discoveredPeers = []
        connectedPeer = nil
        manualCodeInput = ""
        manualCodeInvalid = false
        lastBackupURL = nil
        phase = .idle
    }
}
