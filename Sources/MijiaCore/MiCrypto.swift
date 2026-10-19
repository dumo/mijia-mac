import Foundation
import CryptoKit
import Compression

/// 有序键值对。签名计算对顺序敏感（等价于 Python dict 的插入顺序），
/// 因此不能用无序 Dictionary。
public typealias MiParams = [(String, String)]

public enum MiCrypto {

    // MARK: - Nonce

    /// 等价于 Python `miutils.gen_nonce()`。
    /// 结构：`base64( int64随机数大端8字节 ++ (millis/60000)的最小大端字节表示 )`
    ///
    /// - 第 2 段长度是**动态的**（Python `part2.to_bytes((bit_length+7)//8)`），
    ///   当前约 4 字节，写成固定长度会在某天与服务端对不上。
    public static func genNonce(millis: Int64, random: Int64) -> String {
        var data = Data()
        var be = random.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) }

        let part2 = millis / 60_000
        if part2 > 0 {
            let bits = 64 - part2.leadingZeroBitCount
            let count = (bits + 7) / 8
            var v = UInt64(part2)
            var bytes = [UInt8](repeating: 0, count: count)
            for i in stride(from: count - 1, through: 0, by: -1) {
                bytes[i] = UInt8(v & 0xFF)
                v >>= 8
            }
            data.append(contentsOf: bytes)
        }
        return data.base64EncodedString()
    }

    public static func genNonce() -> String {
        let millis = Int64(Date().timeIntervalSince1970 * 1000)
        return genNonce(millis: millis, random: Int64.random(in: Int64.min...Int64.max))
    }

    // MARK: - 摘要

    /// `signedNonce = base64( SHA256( b64dec(ssecurity) ++ b64dec(nonce) ) )`
    public static func signedNonce(ssecurity: String, nonce: String) throws -> String {
        guard let s = Data(base64Encoded: ssecurity),
              let n = Data(base64Encoded: nonce) else {
            throw MiError.invalidBase64("ssecurity/nonce")
        }
        var h = SHA256()
        h.update(data: s)
        h.update(data: n)
        return Data(h.finalize()).base64EncodedString()
    }

    /// 等价于 Python `gen_enc_signature`：
    /// `base64( SHA1( METHOD & uri & k1=v1 & k2=v2 & ... & signedNonce ) )`
    public static func signature(method: String, uri: String, params: MiParams, signedNonce: String) -> String {
        var parts: [String] = [method.uppercased(), uri]
        for (k, v) in params { parts.append("\(k)=\(v)") }
        parts.append(signedNonce)
        let raw = parts.joined(separator: "&")
        return Data(Insecure.SHA1.hash(data: Data(raw.utf8))).base64EncodedString()
    }

    // MARK: - RC4

    /// RC4 加密，密文 base64。
    public static func encryptRC4(passwordB64: String, payload: String) throws -> String {
        guard let key = Data(base64Encoded: passwordB64) else {
            throw MiError.invalidBase64("rc4 key")
        }
        var cipher = RC4(key: key, drop: 1024)
        return cipher.crypt(Data(payload.utf8)).base64EncodedString()
    }

    /// RC4 解密，输入密文 base64。
    public static func decryptRC4(passwordB64: String, payloadB64: String) throws -> Data {
        guard let key = Data(base64Encoded: passwordB64),
              let data = Data(base64Encoded: payloadB64) else {
            throw MiError.invalidBase64("rc4 payload")
        }
        var cipher = RC4(key: key, drop: 1024)
        return cipher.crypt(data)
    }

    /// 等价于 Python `miutils.decrypt`：RC4 解密后先按 UTF-8 解，失败再按 gzip 解。
    public static func decrypt(ssecurity: String, nonce: String, payload: String) throws -> String {
        let sn = try signedNonce(ssecurity: ssecurity, nonce: nonce)
        let raw = try decryptRC4(passwordB64: sn, payloadB64: payload)
        if let text = String(data: raw, encoding: .utf8) { return text }
        return String(data: try gunzip(raw), encoding: .utf8) ?? ""
    }

    // MARK: - 请求参数封装

    /// 等价于 Python `generate_enc_params`：
    /// 1. 先对**明文** params 算 `rc4_hash__`
    /// 2. 再把所有 value（含 rc4_hash__）用 RC4 加密
    /// 3. 再对**密文** params 算 `signature`
    /// 4. 追加 `ssecurity` / `_nonce`（这两个不加密）
    public static func generateEncParams(uri: String,
                                         method: String = "POST",
                                         signedNonce: String,
                                         nonce: String,
                                         params: MiParams,
                                         ssecurity: String) throws -> MiParams {
        var plain = params
        plain.append(("rc4_hash__",
                      signature(method: method, uri: uri, params: params, signedNonce: signedNonce)))

        var enc: MiParams = []
        for (k, v) in plain {
            enc.append((k, try encryptRC4(passwordB64: signedNonce, payload: v)))
        }

        enc.append(("signature",
                    signature(method: method, uri: uri, params: enc, signedNonce: signedNonce)))
        enc.append(("ssecurity", ssecurity))
        enc.append(("_nonce", nonce))
        return enc
    }

    // MARK: - application/x-www-form-urlencoded

    public static func formEncode(_ params: MiParams) -> String {
        params.map { "\($0.0.mijiaFormEncoded)=\($0.1.mijiaFormEncoded)" }
              .joined(separator: "&")
    }

    // MARK: - Gzip

    /// 纯 Swift 的 gzip 解压（跳过 gzip 头后用 libcompression 做 raw deflate）。
    /// 响应体在 `miot-accept-encoding: GZIP` 时可能是 gzip 流。
    public static func gunzip(_ data: Data) throws -> Data {
        guard data.count >= 18, data[0] == 0x1f, data[1] == 0x8b, data[2] == 0x08 else {
            throw MiError.gzipInvalid
        }
        let flg = data[3]
        var p = 10
        if flg & 0x04 != 0 {                       // FEXTRA
            guard p + 2 <= data.count else { throw MiError.gzipInvalid }
            let xlen = Int(data[p]) | (Int(data[p + 1]) << 8)
            p += 2 + xlen
        }
        if flg & 0x08 != 0 {                       // FNAME
            while p < data.count, data[p] != 0 { p += 1 }
            p += 1
        }
        if flg & 0x10 != 0 {                       // FCOMMENT
            while p < data.count, data[p] != 0 { p += 1 }
            p += 1
        }
        if flg & 0x02 != 0 { p += 2 }              // FHCRC

        let end = max(p, data.count - 8)           // 尾部 8 字节: CRC32 + ISIZE
        guard end > p else { throw MiError.gzipInvalid }
        let deflated = data[p..<end]

        var capacity = max(1024, deflated.count * 6)
        for _ in 0..<10 {
            var dst = [UInt8](repeating: 0, count: capacity)
            let n = deflated.withUnsafeBytes { src -> Int in
                guard let base = src.baseAddress else { return 0 }
                return compression_decode_buffer(
                    &dst, capacity,
                    base.assumingMemoryBound(to: UInt8.self), deflated.count,
                    nil, COMPRESSION_ZLIB)
            }
            if n > 0 && n < capacity { return Data(dst[0..<n]) }
            capacity *= 4
        }
        throw MiError.gzipInvalid
    }
}

// MARK: - RC4

/// 标准 RC4，支持 KSA 后丢弃前 N 字节密钥流（米家用的是 drop-1024 变体）。
public struct RC4 {
    private var s: [UInt8]
    private var i: UInt8 = 0
    private var j: UInt8 = 0

    public init(key: Data, drop: Int = 0) {
        precondition(!key.isEmpty, "RC4 key 不能为空")
        s = (0...255).map { UInt8($0) }
        var j: UInt8 = 0
        for i in 0..<256 {
            j = j &+ s[i] &+ key[i % key.count]
            s.swapAt(i, Int(j))
        }
        if drop > 0 { _ = crypt(Data(count: drop)) }
    }

    public mutating func crypt(_ input: Data) -> Data {
        var output = Data(count: input.count)
        for n in 0..<input.count {
            i = i &+ 1
            j = j &+ s[Int(i)]
            s.swapAt(Int(i), Int(j))
            let k = s[Int(s[Int(i)] &+ s[Int(j)])]
            output[n] = input[n] ^ k
        }
        return output
    }
}

extension String {
    /// 与 Python `urllib.parse.urlencode`（`quote_plus(safe='')`）对齐。
    /// ⚠️ 不能用 `.urlQueryAllowed`——它保留 `+`，而 base64 密文里的 `+`
    ///    会被服务端当成空格，导致签名必错。
    public var mijiaFormEncoded: String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        return addingPercentEncoding(withAllowedCharacters: allowed) ?? self
    }
}
