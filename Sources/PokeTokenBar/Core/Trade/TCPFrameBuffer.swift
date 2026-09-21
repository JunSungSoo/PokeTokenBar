import Foundation

/// TCP 는 스트림이라 메시지 경계가 없다 — 4바이트 빅엔디안 길이 프리픽스로 프레이밍한다.
/// MultipeerConnectivity 는 메시지 단위 전송을 보장해 이 프레이밍이 필요 없다 — ManualTradeTransport(TCP) 전용.
struct TCPFrameBuffer {
    private var buffer = Data()

    static func frame(_ payload: Data) -> Data {
        var length = UInt32(payload.count).bigEndian
        var framed = Data(bytes: &length, count: 4)
        framed.append(payload)
        return framed
    }

    /// 새로 도착한 바이트를 누적하고, 완성된 프레임을 전부 꺼내 반환한다(부분 프레임은 버퍼에 남긴다).
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var frames: [Data] = []
        while buffer.count >= 4 {
            let lengthPrefix = buffer.prefix(4)
            let length = Int(UInt32(bigEndian: lengthPrefix.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))
            guard buffer.count >= 4 + length else { break }
            let frameStart = buffer.startIndex + 4
            let frameEnd = frameStart + length
            frames.append(buffer.subdata(in: frameStart..<frameEnd))
            buffer.removeSubrange(buffer.startIndex..<frameEnd)
        }
        return frames
    }
}
