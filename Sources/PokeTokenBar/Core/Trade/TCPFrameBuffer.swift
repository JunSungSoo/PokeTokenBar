import Foundation

/// TCP 는 스트림이라 메시지 경계가 없다 — 4바이트 빅엔디안 길이 프리픽스로 프레이밍한다.
/// MultipeerConnectivity 는 메시지 단위 전송을 보장해 이 프레이밍이 필요 없다 — ManualTradeTransport(TCP) 전용.
struct TCPFrameBuffer {
    /// 프레임 페이로드 길이 상한 — 상대는 사용자가 직접 입력한 임의 IP:포트라 신뢰할 수 없고, 조작된
    /// 길이 프리픽스(예: 0xFFFFFFFF)를 보내면 상한 없이는 버퍼가 무한히 자란다. 실제 TradeMessage(JSON)
    /// 는 수백 바이트 안이라, SaveTransfer.maxFileBytes 와 같은 방식으로 넉넉히 잡는다.
    static let maxFrameLength = 1 * 1024 * 1024

    enum FrameError: Error, Equatable {
        case frameTooLarge(length: Int, limit: Int)
    }

    private var buffer = Data()

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    /// 새로 도착한 바이트를 누적하고, 완성된 프레임을 전부 꺼내 반환한다(부분 프레임은 버퍼에 남긴다).
    /// 길이 프리픽스가 상한을 넘으면 던진다 — 호출측은 이를 조용한 정지가 아니라 연결 종료로 다뤄야 한다.
    mutating func append(_ data: Data) throws -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let lengthPrefix = buffer.prefix(4)
            let length = Int(UInt32(bigEndian: lengthPrefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            guard length <= Self.maxFrameLength else {
                throw FrameError.frameTooLarge(length: length, limit: Self.maxFrameLength)
            }
            guard buffer.count >= 4 + length else { break }
            let frameStart = buffer.startIndex + 4
            let frameEnd = frameStart + length
            frames.append(buffer.subdata(in: frameStart..<frameEnd))
            buffer.removeSubrange(buffer.startIndex..<frameEnd)
        }
        return frames
    }
}
