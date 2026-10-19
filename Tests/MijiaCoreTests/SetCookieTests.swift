import Testing
import Foundation
@testable import MijiaCore

/// Set-Cookie 解析是登录链路里唯一「不能靠 URLSession」的环节：
/// 服务端下发的 serviceToken 其 Domain 与请求域不一致，会被 URLSession 丢弃。
@Suite("Set-Cookie 解析")
struct SetCookieTests {

    @Test("还原 Foundation 用 ', ' 合并后的多个 cookie")
    func parsesMergedCookies() {
        // 结构取自真实响应，token 值已脱敏
        let header = "userId=8664501; Path=/; Domain=sts.api.mijia.tech, "
            + "cUserId=FAKE_CUSERID_VALUE; Path=/; Domain=sts.api.mijia.tech, "
            + "serviceToken=FAKE_TOKEN_VALUE; Path=/; Domain=sts.api.mijia.tech"

        let parsed = MiCloud.parseSetCookie(header)
        #expect(parsed["userId"] == "8664501")
        #expect(parsed["cUserId"] == "FAKE_CUSERID_VALUE")
        #expect(parsed["serviceToken"] == "FAKE_TOKEN_VALUE")
        #expect(parsed.count == 3)
    }

    @Test("值里绝不能残留属性片段")
    func noAttributeLeakage() {
        let header = "serviceToken=abcDEF123; Path=/; Domain=sts.api.mijia.tech"
        let parsed = MiCloud.parseSetCookie(header)
        let value = try? #require(parsed["serviceToken"])
        #expect(value == "abcDEF123")
        #expect(value?.contains("Path") == false)
        #expect(value?.contains("Domain") == false)
    }

    @Test("Expires 里的逗号不会被误切成新 cookie")
    func handlesExpiresComma() {
        let header = "a=1; Expires=Wed, 09 Jun 2021 10:18:14 GMT; Path=/, "
            + "b=2; Path=/; HttpOnly"
        let parsed = MiCloud.parseSetCookie(header)
        #expect(parsed["a"] == "1")
        #expect(parsed["b"] == "2")
        #expect(parsed.count == 2)
    }

    @Test("Secure / HttpOnly 这类无值属性不影响解析")
    func handlesValuelessAttributes() {
        let header = "sid=xyz; Path=/; Secure; HttpOnly, other=1"
        let parsed = MiCloud.parseSetCookie(header)
        #expect(parsed["sid"] == "xyz")
        #expect(parsed["other"] == "1")
    }

    @Test("空头不产生任何条目")
    func emptyHeader() {
        #expect(MiCloud.parseSetCookie("").isEmpty)
    }
}
