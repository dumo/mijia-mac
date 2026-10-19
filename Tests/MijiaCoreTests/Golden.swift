// 由 Tools/gen_golden.py 自动生成，请勿手改。
// 基准来自 Python 参考实现的协议级独立复现。

enum Golden {
    static let ssecurity = "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8="
    static let millis: Int64 = 1760000000000
    static let randMinus2_63: Int64 = -9141386507638288913
    static let nonce = "gSNFZ4mrze8Bv5dV"
    static let signedNonce = "FX5SHBhquF6s5ZuCpImxECzAjN+QxhwmlZU3eRjt2Sg="
    static let uri = "/miotspec/prop/get"
    static let dataPayload = "{\"params\":[{\"did\":\"123456789\",\"siid\":2,\"piid\":1}],\"datasource\":1}"
    static let rc4Hash = "KlTZOg24ptp/CTTiFFiwmkA/JNY="
    static let encData = "3rmX3ysU2q4SLFm/Pt1sXjpMjQ/wyu9aUzKrDqfVttTbcsQ9NEHghE44jP2oA8eIAe//DJEBIXADRIE1hOhOXHU="
    static let encRc4Hash = "7vez5BYShelAYnLrX+1RU14wxkmvkppAL0vKCg=="
    static let signature = "tFU4WSQyHtH9gXOduduD10TNx+c="
    static let rc4Plaintext = "hello 米家 🌈"
    static let rc4Ciphertext = "zf6L0jZVUGyD86xyPEmatpA="
    static let gzipBase64 = "H4sIAAAAAAAC/6tWSs5PSVWyMtBRKkotLs0pUbKqVkpJLctMTo3PzEvLV7KKjq2tBQC4sYHrJgAAAA=="
    static let gzipPlain = "{\"code\":0,\"result\":{\"device_info\":[]}}"
    static let formExpected = "data=3rmX3ysU2q4SLFm%2FPt1sXjpMjQ%2Fwyu9aUzKrDqfVttTbcsQ9NEHghE44jP2oA8eIAe%2F%2FDJEBIXADRIE1hOhOXHU%3D&rc4_hash__=7vez5BYShelAYnLrX%2B1RU14wxkmvkppAL0vKCg%3D%3D"
}
