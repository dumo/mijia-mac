#!/usr/bin/env python3
"""
生成 MijiaCore 加密层的黄金测试向量。

⚠️ 本脚本是**协议级独立复现**（依据公开 HTTP 协议事实手写），
   不 import mijiaAPI，避免把 GPL-3.0 代码带进本项目。
   仅用于给 Swift 实现提供对拍基准。

输出: Tests/MijiaCoreTests/Golden.swift
"""
import base64
import gzip
import hashlib
import json
import os


def rc4(key: bytes, data: bytes, drop: int = 0) -> bytes:
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 0xFF
        s[i], s[j] = s[j], s[i]
    i = j = 0

    def nxt() -> int:
        nonlocal i, j
        i = (i + 1) & 0xFF
        j = (j + s[i]) & 0xFF
        s[i], s[j] = s[j], s[i]
        return s[(s[i] + s[j]) & 0xFF]

    for _ in range(drop):
        nxt()
    return bytes(b ^ nxt() for b in data)


def gen_nonce(millis: int, rand: int) -> str:
    b = (rand - 2 ** 63).to_bytes(8, "big", signed=True)
    part2 = int(millis / 60000)
    b += part2.to_bytes(((part2.bit_length() + 7) // 8), "big")
    return base64.b64encode(b).decode()


def signed_nonce(ssecurity: str, nonce: str) -> str:
    return base64.b64encode(
        hashlib.sha256(base64.b64decode(ssecurity) + base64.b64decode(nonce)).digest()
    ).decode()


def signature(uri: str, method: str, params, sn: str) -> str:
    parts = [method.upper(), uri] + [f"{k}={v}" for k, v in params] + [sn]
    return base64.b64encode(hashlib.sha1("&".join(parts).encode()).digest()).decode()


def urlencode(params) -> str:
    safe = "-_.~ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    out = []
    for k, v in params:

        def enc(s: str) -> str:
            r = ""
            for ch in s:
                if ch in safe:
                    r += ch
                else:
                    for b in ch.encode("utf-8"):
                        r += "%%%02X" % b
            return r
        out.append(f"{enc(k)}={enc(v)}")
    return "&".join(out)


def main() -> None:
    ssecurity = base64.b64encode(bytes(range(32))).decode()
    millis = 1_760_000_000_000
    rand = 0x0123456789ABCDEF  # 传入时会被减去 2**63

    nonce = gen_nonce(millis, rand)
    sn = signed_nonce(ssecurity, nonce)

    uri = "/miotspec/prop/get"
    data_payload = '{"params":[{"did":"123456789","siid":2,"piid":1}],"datasource":1}'
    plain_params = [("data", data_payload)]

    sn_key = base64.b64decode(sn)
    rc4_hash = signature(uri, "POST", plain_params, sn)
    enc_params = [(k, base64.b64encode(rc4(sn_key, v.encode(), 1024)).decode())
                  for k, v in plain_params]
    enc_params.append(("rc4_hash__",
                       base64.b64encode(rc4(sn_key, rc4_hash.encode(), 1024)).decode()))
    sig = signature(uri, "POST", enc_params, sn)

    # RC4 往返
    plaintext = "hello 米家 🌈"
    ct = base64.b64encode(rc4(base64.b64decode(sn), plaintext.encode(), 1024)).decode()

    # Gzip（无文件名/注释，最简头）
    gz_plain = '{"code":0,"result":{"device_info":[]}}'
    gz = gzip.compress(gz_plain.encode(), compresslevel=9, mtime=0)

    vec = {
        "ssecurity": ssecurity,
        "millis": millis,
        "randMinus2_63": rand - 2 ** 63,
        "nonce": nonce,
        "signedNonce": sn,
        "uri": uri,
        "dataPayload": data_payload,
        "rc4Hash": rc4_hash,
        "encData": enc_params[0][1],
        "encRc4Hash": enc_params[1][1],
        "signature": sig,
        "rc4Plaintext": plaintext,
        "rc4Ciphertext": ct,
        "gzipBase64": base64.b64encode(gz).decode(),
        "gzipPlain": gz_plain,
        "formExpected": urlencode(enc_params),
    }

    out_dir = os.path.join(os.path.dirname(__file__), "..", "Tests", "MijiaCoreTests")
    out_dir = os.path.abspath(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    def swift_str(s: str) -> str:
        # ensure_ascii=False：Swift 不支持 JSON 的 \uXXXX 代理对转义写法
        # （Swift 只认 \u{...}），非 ASCII 必须原样落盘。
        return json.dumps(s, ensure_ascii=False)

    lines = [
        "// 由 Tools/gen_golden.py 自动生成，请勿手改。",
        "// 基准来自 Python 参考实现的协议级独立复现。",
        "",
        "enum Golden {",
        f"    static let ssecurity = {swift_str(vec['ssecurity'])}",
        f"    static let millis: Int64 = {vec['millis']}",
        f"    static let randMinus2_63: Int64 = {vec['randMinus2_63']}",
        f"    static let nonce = {swift_str(vec['nonce'])}",
        f"    static let signedNonce = {swift_str(vec['signedNonce'])}",
        f"    static let uri = {swift_str(vec['uri'])}",
        f"    static let dataPayload = {swift_str(vec['dataPayload'])}",
        f"    static let rc4Hash = {swift_str(vec['rc4Hash'])}",
        f"    static let encData = {swift_str(vec['encData'])}",
        f"    static let encRc4Hash = {swift_str(vec['encRc4Hash'])}",
        f"    static let signature = {swift_str(vec['signature'])}",
        f"    static let rc4Plaintext = {swift_str(vec['rc4Plaintext'])}",
        f"    static let rc4Ciphertext = {swift_str(vec['rc4Ciphertext'])}",
        f"    static let gzipBase64 = {swift_str(vec['gzipBase64'])}",
        f"    static let gzipPlain = {swift_str(vec['gzipPlain'])}",
        f"    static let formExpected = {swift_str(vec['formExpected'])}",
        "}",
        "",
    ]
    with open(os.path.join(out_dir, "Golden.swift"), "w") as f:
        f.write("\n".join(lines))

    print(json.dumps(vec, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
