import Foundation

// Shared between sender (laptop) and receiver (iMac).

let serviceType = "_imacdisplay._tcp"
let defaultPort: UInt16 = 7777

enum Codec: UInt8 {
    case h264 = 0
    case hevc = 1
}

/// One encoded video frame on the wire.
///
///   u32  body length (big endian)
///   u8   codec            (0 = H.264, 1 = HEVC)
///   u8   keyframe flag
///   u8   number of parameter sets (SPS/PPS[/VPS]); only sent with keyframes
///   [u16 length + bytes] * number of parameter sets
///   ...  frame data in AVCC form (4-byte length-prefixed NAL units)
struct FrameMessage {
    var codec: Codec
    var keyframe: Bool
    var params: [Data]
    var payload: Data

    func encode() -> Data {
        var body = Data([codec.rawValue, keyframe ? 1 : 0, UInt8(params.count)])
        for p in params {
            body.append(UInt8(p.count >> 8))
            body.append(UInt8(p.count & 0xff))
            body.append(p)
        }
        body.append(payload)
        var out = Data()
        var len = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    static func decode(body: Data) -> FrameMessage? {
        let b = Data(body) // normalise indices to 0...
        guard b.count >= 3, let codec = Codec(rawValue: b[0]) else { return nil }
        let key = b[1] == 1
        let n = Int(b[2])
        var i = 3
        var params: [Data] = []
        for _ in 0..<n {
            guard i + 2 <= b.count else { return nil }
            let l = Int(b[i]) << 8 | Int(b[i + 1])
            i += 2
            guard i + l <= b.count else { return nil }
            params.append(b.subdata(in: i..<i + l))
            i += l
        }
        return FrameMessage(codec: codec, keyframe: key, params: params, payload: b.subdata(in: i..<b.count))
    }
}

/// Splits a TCP byte stream into length-prefixed messages.
final class StreamParser {
    private var buf = Data()

    func feed(_ d: Data) -> [Data] {
        buf.append(d)
        var out: [Data] = []
        while buf.count >= 4 {
            let len = buf.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
            if len > 256 << 20 { buf.removeAll(); break } // garbage, resync on next connection
            guard buf.count >= 4 + len else { break }
            out.append(buf.subdata(in: 4..<4 + len))
            buf = Data(buf.dropFirst(4 + len))
        }
        return out
    }
}
