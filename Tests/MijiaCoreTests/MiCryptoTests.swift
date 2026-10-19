import Testing
import Foundation
@testable import MijiaCore

/// 加密层对拍：每一个断言都对应 Python 参考实现的一个行为，
/// 黄金值由 Tools/gen_golden.py（协议级独立复现）生成。
@Suite("MiCrypto 加密层")
struct MiCryptoTests {

    // MARK: - nonce

    @Test("genNonce 与参考实现逐字节一致")
    func genNonceMatchesReference() {
        let n = MiCrypto.genNonce(millis: Golden.millis, random: Golden.randMinus2_63)
        #expect(n == Golden.nonce)
    }

    @Test("genNonce 第二段是 millis/60000 的最小大端表示")
    func genNonceSecondSegment() throws {
        let millis: Int64 = 1_760_000_000_000
        let n = MiCrypto.genNonce(millis: millis, random: 0)
        let raw = try #require(Data(base64Encoded: n))
        #expect(raw.count == 8 + 4)                 // 8 字节随机 + 4 字节 part2
        let part2 = raw.dropFirst(8).reduce(Int64(0)) { ($0 << 8) | Int64($1) }
        #expect(part2 == millis / 60_000)
    }

    @Test("genNonce 随机会产生不同结果")
    func genNonceRandomized() {
        let a = MiCrypto.genNonce()
        let b = MiCrypto.genNonce()
        #expect(a != b)
    }

    // MARK: - 摘要

    @Test("signedNonce = SHA256(ssecurity || nonce)")
    func signedNonceMatches() throws {
        let sn = try MiCrypto.signedNonce(ssecurity: Golden.ssecurity, nonce: Golden.nonce)
        #expect(sn == Golden.signedNonce)
    }

    @Test("signature 拼接顺序为 METHOD&uri&k=v...&signedNonce")
    func signatureMatches() {
        let s = MiCrypto.signature(method: "POST",
                                   uri: Golden.uri,
                                   params: [("data", Golden.dataPayload)],
                                   signedNonce: Golden.signedNonce)
        #expect(s == Golden.rc4Hash)
    }

    // MARK: - RC4（drop-1024 变体）

    @Test("RC4 加密与参考实现一致")
    func rc4EncryptMatches() throws {
        let out = try MiCrypto.encryptRC4(passwordB64: Golden.signedNonce,
                                          payload: Golden.rc4Plaintext)
        #expect(out == Golden.rc4Ciphertext)
    }

    @Test("RC4 解密往返（含多字节 UTF-8）")
    func rc4RoundTrip() throws {
        let ct = try MiCrypto.encryptRC4(passwordB64: Golden.signedNonce,
                                         payload: Golden.rc4Plaintext)
        let pt = try MiCrypto.decryptRC4(passwordB64: Golden.signedNonce, payloadB64: ct)
        #expect(String(data: pt, encoding: .utf8) == Golden.rc4Plaintext)
    }

    @Test("RC4 必须丢弃前 1024 字节密钥流")
    func rc4Drop1024() throws {
        // 不 drop 的结果必须与 drop-1024 不同，否则说明 drop 被漏掉了
        guard let key = Data(base64Encoded: Golden.signedNonce) else {
            Issue.record("bad base64"); return
        }
        var noDrop = RC4(key: key, drop: 0)
        var withDrop = RC4(key: key, drop: 1024)
        let input = Data("same-plaintext".utf8)
        #expect(noDrop.crypt(input) != withDrop.crypt(input))
    }

    // MARK: - 请求参数封装

    @Test("generateEncParams 全字段与参考实现一致")
    func generateEncParamsMatches() throws {
        let enc = try MiCrypto.generateEncParams(
            uri: Golden.uri,
            signedNonce: Golden.signedNonce,
            nonce: Golden.nonce,
            params: [("data", Golden.dataPayload)],
            ssecurity: Golden.ssecurity)

        let dict = Dictionary(uniqueKeysWithValues: enc)
        #expect(enc.map(\.0) == ["data", "rc4_hash__", "signature", "ssecurity", "_nonce"])
        #expect(dict["data"] == Golden.encData)
        #expect(dict["rc4_hash__"] == Golden.encRc4Hash)
        #expect(dict["signature"] == Golden.signature)
        #expect(dict["ssecurity"] == Golden.ssecurity)
        #expect(dict["_nonce"] == Golden.nonce)
    }

    @Test("generateEncParams 中签名是对密文算的，rc4_hash__ 是对明文算的")
    func signatureOverCiphertext() throws {
        let enc = try MiCrypto.generateEncParams(
            uri: Golden.uri,
            signedNonce: Golden.signedNonce,
            nonce: Golden.nonce,
            params: [("data", Golden.dataPayload)],
            ssecurity: Golden.ssecurity)
        // rc4_hash__ 解密回来必须等于明文签名
        let decryptedHash = try MiCrypto.decryptRC4(passwordB64: Golden.signedNonce,
                                                    payloadB64: enc[1].1)
        #expect(String(data: decryptedHash, encoding: .utf8) == Golden.rc4Hash)
    }

    // MARK: - form 编码

    @Test("formEncode 会把 base64 的 + / = 正确转义")
    func formEncodeMatches() {
        let params: MiParams = [("data", Golden.encData), ("rc4_hash__", Golden.encRc4Hash)]
        #expect(MiCrypto.formEncode(params) == Golden.formExpected)
    }

    @Test("formEncode 不得保留裸 + 号")
    func formEncodeEscapesPlus() {
        let out = MiCrypto.formEncode([("k", "a+b/c=d")])
        #expect(out == "k=a%2Bb%2Fc%3Dd")
    }

    // MARK: - Gzip

    @Test("gunzip 解压与参考实现一致")
    func gunzipMatches() throws {
        let gz = try #require(Data(base64Encoded: Golden.gzipBase64))
        let out = try MiCrypto.gunzip(gz)
        #expect(String(data: out, encoding: .utf8) == Golden.gzipPlain)
    }

    @Test("decrypt 走明文分支")
    func decryptPlainBranch() throws {
        let payload = try MiCrypto.encryptRC4(passwordB64: Golden.signedNonce,
                                              payload: Golden.gzipPlain)
        let out = try MiCrypto.decrypt(ssecurity: Golden.ssecurity,
                                       nonce: Golden.nonce,
                                       payload: payload)
        #expect(out == Golden.gzipPlain)
    }

    @Test("decrypt 走 gzip 分支")
    func decryptGzipBranch() throws {
        let gz = try #require(Data(base64Encoded: Golden.gzipBase64))
        // 用 signedNonce 加密 gzip 二进制，模拟服务端压缩响应
        guard let key = Data(base64Encoded: Golden.signedNonce) else {
            Issue.record("bad base64"); return
        }
        var cipher = RC4(key: key, drop: 1024)
        let payload = cipher.crypt(gz).base64EncodedString()

        let out = try MiCrypto.decrypt(ssecurity: Golden.ssecurity,
                                       nonce: Golden.nonce,
                                       payload: payload)
        #expect(out == Golden.gzipPlain)
    }
}
