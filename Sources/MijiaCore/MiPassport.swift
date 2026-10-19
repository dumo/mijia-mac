import Foundation

/// 扫码登录流程（对应 Python `QRlogin` / `_get_qr_login_data` / `_complete_qr_login`）
extension MiCloud {

    public enum LoginLocation {
        /// serviceToken 仍然有效，已静默刷新
        case refreshed
        /// 需要扫码，携带 location 里的查询参数
        case qrParams([String: String])
    }

    public struct QRTicket: Sendable {
        /// 二维码原始内容（用于本地生成二维码图像）
        public let loginURL: String
        /// 服务端渲染好的二维码图片地址（终端不好扫时用浏览器打开）
        public let imageURL: String
        /// 长轮询地址：扫完码后 GET 它拿 token
        public let longPollingURL: String
    }

    // MARK: - Step 1: serviceLogin

    /// GET `account.xiaomi.com/pass/serviceLogin`，判断是「已登录」还是「需要扫码」。
    public func fetchLoginLocation() async throws -> LoginLocation {
        ensureIdentifiers()
        var comps = URLComponents(string: Self.serviceLoginURL)!
        comps.queryItems = [
            URLQueryItem(name: "_json", value: "true"),
            URLQueryItem(name: "sid", value: "mijia"),
            URLQueryItem(name: "_locale", value: locale),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue(auth["ua"], forHTTPHeaderField: "User-Agent")
        req.setValue("keep-alive", forHTTPHeaderField: "Connection")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(passportCookieString(), forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MiError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                               body: String(data: data, encoding: .utf8) ?? "")
        }

        let obj = try parseServiceResponse(data)
        let code = obj["code"]?.intValue ?? -1
        if let ssecurity = obj["ssecurity"]?.stringValue, !ssecurity.isEmpty {
            auth["ssecurity"] = ssecurity
        }
        guard let location = obj["location"]?.stringValue else {
            throw MiError.login(code: code, desc: obj["desc"]?.stringValue ?? "响应缺少 location")
        }

        // code == 0 说明还有有效登录态，跟着 location 走就能刷新出 serviceToken
        if code == 0 {
            var follow = URLRequest(url: try makeURL(location))
            follow.setValue(auth["ua"], forHTTPHeaderField: "User-Agent")
            let (body, followResp) = try await session.data(for: follow)
            if let h = followResp as? HTTPURLResponse, h.statusCode == 200,
               (String(data: body, encoding: .utf8) ?? "") == "ok" {
                absorbCookies(from: h)
                try save()
                return .refreshed
            }
        }

        return .qrParams(queryParams(of: location))
    }

    // MARK: - Step 2: 取二维码

    /// 返回 nil 表示 token 已刷新成功，无需扫码。
    public func fetchQRTicket() async throws -> QRTicket? {
        guard case .qrParams(var params) = try await fetchLoginLocation() else {
            return nil
        }
        params["theme"] = ""
        params["bizDeviceType"] = ""
        params["_hasLogo"] = "false"
        params["_qrsize"] = "240"
        params["_dc"] = String(Int64(Date().timeIntervalSince1970 * 1000))

        var comps = URLComponents(string: Self.longPollingURL)!
        // ⚠️ 必须自己编码：URLQueryItem 会保留 `+`，与 Python urlencode 不一致
        comps.percentEncodedQueryItems = params
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key.mijiaFormEncoded, value: $0.value.mijiaFormEncoded) }

        var req = URLRequest(url: comps.url!)
        req.setValue(auth["ua"], forHTTPHeaderField: "User-Agent")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("keep-alive", forHTTPHeaderField: "Connection")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MiError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                               body: String(data: data, encoding: .utf8) ?? "")
        }
        let obj = try parseServiceResponse(data)
        guard let loginURL = obj["loginUrl"]?.stringValue,
              let lp = obj["lp"]?.stringValue else {
            throw MiError.login(code: obj["code"]?.intValue ?? -1,
                                desc: obj["desc"]?.stringValue ?? "响应缺少 loginUrl/lp")
        }
        return QRTicket(loginURL: loginURL,
                        imageURL: obj["qr"]?.stringValue ?? "",
                        longPollingURL: lp)
    }

    // MARK: - Step 3: 长轮询等扫码

    /// GET `lp` 阻塞等待用户扫码（最长 120 秒，与 Python 版一致）。
    public func completeLogin(lp longPollingURL: String) async throws {
        var req = URLRequest(url: try makeURL(longPollingURL))
        req.timeoutInterval = 120
        req.setValue(auth["ua"], forHTTPHeaderField: "User-Agent")
        req.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("keep-alive", forHTTPHeaderField: "Connection")

        let data: Data
        do {
            let result = try await session.data(for: req)
            data = result.0
        } catch let e as URLError where e.code == .timedOut {
            throw MiError.timeout
        }

        let obj = try parseServiceResponse(data)
        let code = obj["code"]?.intValue ?? -1
        guard code == 0 else {
            throw MiError.login(code: code, desc: obj["desc"]?.stringValue ?? "扫码未完成")
        }

        for key in ["psecurity", "nonce", "ssecurity", "passToken", "userId", "cUserId"] {
            if let v = obj[key]?.stringValue { auth[key] = v }
        }
        guard let callback = obj["location"]?.stringValue else {
            throw MiError.login(code: code, desc: "响应缺少回调 location")
        }

        var cb = URLRequest(url: try makeURL(callback))
        cb.setValue(auth["ua"], forHTTPHeaderField: "User-Agent")
        let cbResult = try await session.data(for: cb)
        if let h = cbResult.1 as? HTTPURLResponse {
            absorbCookies(from: h)
        }

        auth["expireTime"] =
            String(Int64(Date().addingTimeInterval(30 * 86_400).timeIntervalSince1970 * 1000))
        try save()
    }

    // MARK: - 私有工具

    /// passport 接口返回体带 `&&&START&&&` 前缀，需要先剥掉再 JSON 解析。
    func parseServiceResponse(_ data: Data) throws -> [String: JSONValue] {
        let text = (String(data: data, encoding: .utf8) ?? "")
            .replacingOccurrences(of: "&&&START&&&", with: "")
        guard let d = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: d),
              let obj = value.objectValue else {
            throw MiError.invalidResponse(String(text.prefix(120)))
        }
        return obj
    }

    func queryParams(of urlString: String) -> [String: String] {
        guard let comps = URLComponents(string: urlString),
              let items = comps.queryItems else { return [:] }
        var out: [String: String] = [:]
        for item in items { out[item.name] = item.value ?? "" }
        return out
    }

    private func passportCookieString() -> String {
        [
            "deviceId=\(auth["deviceId"] ?? "")",
            "pass_o=\(auth["pass_o"] ?? "")",
            "passToken=\(auth["passToken"] ?? "")",
            "userId=\(auth["userId"] ?? "")",
            "cUserId=\(auth["cUserId"] ?? "")",
            "uLocale=\(locale)",
        ].joined(separator: ";")
    }
}
