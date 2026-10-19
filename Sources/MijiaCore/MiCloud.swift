import Foundation

/// 米家云客户端。负责：认证态持久化、RC4 请求签名、业务接口调用。
///
/// 设计上是 `actor`，所有网络操作天然串行化，避免并发刷新 token 打打架。
public actor MiCloud {

    // MARK: - 端点常量

    public static let apiBaseURL = "https://api.mijia.tech/app"
    public static let serviceLoginURL = "https://account.xiaomi.com/pass/serviceLogin"
    public static let longPollingURL = "https://account.xiaomi.com/longPolling/loginUrl"

    // MARK: - 状态

    public var auth: AuthData
    /// 不可变且 Sendable，显式 nonisolated 以便外部同步读取路径
    public nonisolated let authFile: URL
    public var locale: String

    /// 跨文件 extension（MiPassport）也要用，故不标 private
    let session: URLSession
    private var availableCache: Bool?
    private var availableAt: TimeInterval = 0
    /// home_id → owner uid 缓存（_device_list 每次都要带 owner_uid）
    /// 注意：extension 在另一个文件里也要访问，不能标 private
    var ownerCache: [String: Int] = [:]

    // MARK: - 初始化

    public init(authFile: URL? = nil, locale: String = "zh_CN") {
        let file = authFile ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mijia-mac/auth.json")
        self.authFile = file
        self.locale = locale

        if let data = try? Data(contentsOf: file),
           let decoded = try? JSONDecoder().decode(AuthData.self, from: data) {
            self.auth = decoded
        } else {
            self.auth = AuthData()
        }

        // ⚠️ 关键点：登录回调下发的 serviceToken，其 Set-Cookie 的
        // Domain 是 sts.api.mijia.tech，与请求域 account.xiaomi.com 不匹配。
        // URLSession 会按 RFC 6265 直接丢弃它，导致永远拿不到 serviceToken
        // （Python 的 requests 不校验域、照单全收，这就是两边的差异）。
        // 所以我们关掉 URLSession 的 cookie 管理，全程手工解析 Set-Cookie。
        let cfg = URLSessionConfiguration.default
        cfg.httpCookieStorage = nil
        cfg.httpCookieAcceptPolicy = .never
        cfg.httpShouldSetCookies = false
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        cfg.timeoutIntervalForRequest = 130

        self.session = URLSession(configuration: cfg)
    }

    // MARK: - 身份标识（ua / deviceId / pass_o）

    private static let deviceIdChars =
        "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-"
    private static let hexChars = "0123456789ABCDEF"

    private static func randomString(from chars: String, count: Int) -> String {
        var g = SystemRandomNumberGenerator()
        return String((0..<count).compactMap { _ in chars.randomElement(using: &g) })
    }

    /// 首次使用时生成，之后**必须持久化**——每次重新生成会被判为新设备。
    public func ensureIdentifiers() {
        if auth["deviceId"] == nil {
            auth["deviceId"] = Self.randomString(from: Self.deviceIdChars, count: 16)
        }
        if auth["pass_o"] == nil {
            auth["pass_o"] = Self.randomString(from: "0123456789abcdef", count: 16)
        }
        if auth["ua"] == nil {
            let id1 = Self.randomString(from: Self.hexChars, count: 40)
            let id2 = Self.randomString(from: Self.hexChars, count: 32)
            let id3 = Self.randomString(from: Self.hexChars, count: 32)
            let id4 = Self.randomString(from: Self.hexChars, count: 40)
            let country = locale.split(separator: "_").last.map(String.init) ?? "CN"
            let passO = auth["pass_o"] ?? ""
            auth["ua"] = "Android-15-11.0.701-Xiaomi-23046RP50C-OS2.0.212.0.VMYCNXM-"
                + "\(id1)-\(country)-\(id3)-\(id2)-SmartHome-MI_APP_STORE-"
                + "\(id1)|\(id4)|\(passO)-64"
        }
    }

    // MARK: - 持久化

    public func save() throws {
        auth["saveTime"] = String(Int64(Date().timeIntervalSince1970 * 1000))
        let dir = authFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(auth)
        try data.write(to: authFile, options: .atomic)
    }

    public var isLoggedIn: Bool { auth.isComplete }

    /// 给 UI 展示用的账号标识（优先 userId，其次 cUserId）。没有登录态时返回 nil。
    public func accountIdentity() -> String? {
        if let u = auth["userId"], !u.isEmpty { return u }
        if let u = auth["cUserId"], !u.isEmpty { return u }
        return nil
    }

    /// 米家没有提供云端「注销」接口（Python 版 mijia-api 也没有）。
    /// 本机清掉登录凭据即等价于退出：下次启动会重新要求扫码。
    /// 注意：米家 App 端并不会因此被挤下线，只是本机这份 token 失效。
    public func logout() throws {
        auth = AuthData()
        try save()
    }

    // MARK: - Cookie

    /// 业务请求的固定 Cookie 串（与 Python 版逐字段对齐）
    private func businessCookieString() -> String {
        let tz = TimeZone.current
        let seconds = tz.secondsFromGMT()
        let sign = seconds >= 0 ? "+" : "-"
        let absSeconds = Swift.abs(seconds)
        let tzString = String(format: "GMT%@%02d:%02d",
                              sign, absSeconds / 3600, (absSeconds % 3600) / 60)
        let isDaylight = tz.daylightSavingTimeOffset() != 0 ? 1 : 0
        let dstOffset = Int(tz.daylightSavingTimeOffset()) * 1000
        let token = auth["serviceToken"] ?? ""
        let country = locale.split(separator: "_").last.map(String.init) ?? "CN"

        return [
            "cUserId=\(auth["cUserId"] ?? "")",
            "yetAnotherServiceToken=\(token)",
            "serviceToken=\(token)",
            "timezone_id=\(tz.identifier)",
            "timezone=\(tzString)",
            "is_daylight=\(isDaylight)",
            "dst_offset=\(dstOffset)",
            "channel=MI_APP_STORE",
            "countryCode=\(country)",
            "PassportDeviceId=\(auth["deviceId"] ?? "")",
            "locale=\(locale)",
        ].joined(separator: ";")
    }

    // MARK: - 业务请求

    /// 一次加密的 miot-spec 调用。
    /// - Parameter refresh: 是否先确保 token 有效（递归调用时传 false）
    public func call(_ uri: String,
                     _ payload: MiPayload = [:],
                     refresh: Bool = true) async throws -> JSONValue {
        if refresh { try await refreshToken() }
        ensureIdentifiers()

        guard let ssecurity = auth.ssecurity, !ssecurity.isEmpty else {
            throw MiError.notLoggedIn
        }

        let url = try makeURL(Self.apiBaseURL + uri)
        let bodyJSON = try JSONValue.object(payload).compactJSON()
        let nonce = MiCrypto.genNonce()
        let signedNonce = try MiCrypto.signedNonce(ssecurity: ssecurity, nonce: nonce)
        let encParams = try MiCrypto.generateEncParams(
            uri: uri, method: "POST", signedNonce: signedNonce, nonce: nonce,
            params: [("data", bodyJSON)], ssecurity: ssecurity)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = Data(MiCrypto.formEncode(encParams).utf8)
        req.setValue(auth["ua"], forHTTPHeaderField: "User-Agent")
        req.setValue("identity", forHTTPHeaderField: "accept-encoding")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("GZIP", forHTTPHeaderField: "miot-accept-encoding")
        req.setValue("ENCRYPT-RC4", forHTTPHeaderField: "miot-encrypt-algorithm")
        req.setValue("PROTOCAL-HTTP2", forHTTPHeaderField: "x-xiaomi-protocal-flag-cli")
        req.setValue(businessCookieString(), forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw MiError.invalidResponse("非 HTTP 响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MiError.http(status: http.statusCode,
                               body: String(data: data, encoding: .utf8) ?? "")
        }

        let envelope = try decryptEnvelope(data, ssecurity: ssecurity, nonce: nonce)
        guard let obj = envelope.objectValue else {
            throw MiError.invalidResponse("响应不是 JSON 对象")
        }
        let code = obj["code"]?.intValue ?? 0
        guard code == 0 else {
            throw MiError.api(code: code,
                              message: obj["message"]?.stringValue
                                    ?? obj["desc"]?.stringValue ?? "未知错误")
        }
        guard let result = obj["result"] else {
            throw MiError.invalidResponse("响应缺少 result 字段")
        }
        return result
    }

    /// 响应可能是明文 JSON，也可能是 RC4(+gzip) 密文
    private func decryptEnvelope(_ data: Data,
                                 ssecurity: String,
                                 nonce: String) throws -> JSONValue {
        if let v = try? JSONDecoder().decode(JSONValue.self, from: data) { return v }
        let text = String(data: data, encoding: .utf8) ?? ""
        let plain = try MiCrypto.decrypt(ssecurity: ssecurity, nonce: nonce, payload: text)
        return try JSONDecoder().decode(JSONValue.self, from: Data(plain.utf8))
    }

    // MARK: - Token 刷新 / 探活

    /// 对应 Python `_refresh_token()`：先用 check_new_msg 探活（结果缓存 60s），
    /// 探活失败再走 passport location 刷新。
    public func refreshToken() async throws {
        guard auth.isComplete else { throw MiError.notLoggedIn }
        let now = Date().timeIntervalSince1970
        if let cached = availableCache, now - availableAt < 60 {
            if cached { return }
        }

        do {
            _ = try await call("/v2/message/v2/check_new_msg",
                               ["begin_at": .int(Int(now) - 3600)],
                               refresh: false)
            availableCache = true
            availableAt = now
            return
        } catch {
            // 探活失败 → 尝试用 passport 刷新 serviceToken
        }

        switch try await fetchLoginLocation() {
        case .refreshed:
            availableCache = true
            availableAt = now
        case .qrParams:
            availableCache = false
            availableAt = now
            throw MiError.notLoggedIn
        }
    }

    // MARK: - 工具

    func makeURL(_ string: String) throws -> URL {
        guard let url = URL(string: string) else {
            throw MiError.invalidResponse("非法 URL: \(string)")
        }
        return url
    }

    /// 手工解析 Set-Cookie 并合并进 auth（对应 Python `auth_data.update(cookies)`）。
    ///
    /// Foundation 会把多个 Set-Cookie 用 `", "` 合并成一个字符串，而 cookie 属性
    /// 本身用 `"; "` 分隔，且 `Expires=Wed, 09 Jun...` 里还带逗号——所以不能简单
    /// 按逗号切。这里按「看起来像属性开头」的片段归并回上一个 cookie 来还原。
    func absorbCookies(from response: HTTPURLResponse) {
        guard let header = response.value(forHTTPHeaderField: "Set-Cookie") else { return }
        for (name, value) in Self.parseSetCookie(header) {
            // 空值不覆盖已有有效值：ssecurity 一旦被清空就再也刷不回来了
            if value.isEmpty, let existing = auth[name], !existing.isEmpty { continue }
            auth[name] = value
        }
    }

    static func parseSetCookie(_ header: String) -> [String: String] {
        let attributePrefixes = ["path=", "domain=", "expires=", "max-age=", "secure",
                                 "httponly", "samesite=", "version=", "comment=", "priority="]
        var segments: [String] = []
        for rawPiece in header.split(separator: ",", omittingEmptySubsequences: true) {
            let piece = rawPiece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            let lower = piece.lowercased()
            let looksLikeAttribute = attributePrefixes.contains { lower.hasPrefix($0) }
            if looksLikeAttribute, let last = segments.last {
                segments[segments.count - 1] = last + "; " + piece
            } else {
                segments.append(piece)
            }
        }

        var out: [String: String] = [:]
        for segment in segments {
            guard let pair = segment.split(separator: ";", maxSplits: 1).first else { continue }
            let kv = pair.split(separator: "=", maxSplits: 1)
            guard kv.count == 2 else { continue }
            let name = kv[0].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            out[name] = String(kv[1])
        }
        return out
    }
}
