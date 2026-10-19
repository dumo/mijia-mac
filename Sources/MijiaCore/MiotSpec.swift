import Foundation

/// 设备规格（siid/piid/aiid 映射表）来源：miot-spec.org（小米官方数据源，v5.0 起）。
/// 规格体积不小且几乎不变，落盘缓存避免每次启动都拉网。
public struct MiotSpecStore: Sendable {

    public static let instanceURL = "https://miot-spec.org/miot-spec-v2/instance"

    /// 缓存格式版本，与 Python 版 `device_info_version` 对齐，改结构时 +1 即可整体失效
    private static let cacheVersion = 2

    public let cacheDir: URL

    public init(cacheDir: URL? = nil) {
        self.cacheDir = cacheDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mijia-mac/specs")
    }

    // MARK: - 拉取

    public func spec(forType specType: String) async throws -> DeviceSpec {
        if let cached = loadCache(specType) { return cached }

        var comps = URLComponents(string: Self.instanceURL)!
        comps.percentEncodedQueryItems = [
            URLQueryItem(name: "type", value: specType.mijiaFormEncoded)
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("mijia-mac", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw MiError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                               body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let obj = value.objectValue, obj["services"] != nil else {
            throw MiError.invalidResponse("miot-spec 返回结构异常: \(specType)")
        }

        let spec = Self.parse(obj, specType: specType)
        saveCache(spec, forType: specType)
        return spec
    }

    // MARK: - 解析

    static func parse(_ obj: [String: JSONValue], specType: String) -> DeviceSpec {
        var properties: [DevProp] = []
        var actions: [DevAction] = []

        for service in obj["services"]?.arrayValue ?? [] {
            guard let s = service.objectValue,
                  let type = s["type"]?.stringValue,
                  let siid = s["iid"]?.intValue else { continue }

            let parts = type.split(separator: ":").map(String.init)
            // device-information 服务只有固件版本之类的元信息，跳过
            if parts.count > 3, parts[3] == "device-information" { continue }

            for p in s["properties"]?.arrayValue ?? [] {
                guard let po = p.objectValue,
                      let pType = po["type"]?.stringValue,
                      let piid = po["iid"]?.intValue else { continue }

                let format = po["format"]?.stringValue ?? ""
                let mappedType: String
                if format.hasPrefix("int") {
                    mappedType = "int"
                } else if format.hasPrefix("uint") {
                    mappedType = "uint"
                } else {
                    mappedType = format
                }

                let access = (po["access"]?.arrayValue ?? []).compactMap { $0.stringValue }
                var rw = ""
                if access.contains("read") { rw += "r" }
                if access.contains("write") { rw += "w" }

                var options: [ValueOption]? = nil
                if let list = po["value-list"]?.arrayValue, !list.isEmpty {
                    options = list.compactMap { item in
                        guard let io = item.objectValue, let v = io["value"] else { return nil }
                        return ValueOption(value: v,
                                           desc: io["description"]?.stringValue ?? "")
                    }
                }

                properties.append(DevProp(
                    name: parts.count > 3 ? String(parts[3]) : pType,
                    desc: joinedDescription(po["description"]?.stringValue,
                                            comment: po["comment"]?.stringValue),
                    type: mappedType,
                    rw: rw,
                    range: po["value-range"]?.arrayValue?.compactMap { $0.doubleValue },
                    valueList: options,
                    siid: siid,
                    piid: piid))
            }

            for a in s["actions"]?.arrayValue ?? [] {
                guard let ao = a.objectValue,
                      let aType = ao["type"]?.stringValue,
                      let aiid = ao["iid"]?.intValue else { continue }
                let aParts = aType.split(separator: ":").map(String.init)
                actions.append(DevAction(
                    name: aParts.count > 3 ? String(aParts[3]) : aType,
                    desc: joinedDescription(ao["description"]?.stringValue,
                                            comment: ao["comment"]?.stringValue),
                    siid: siid,
                    aiid: aiid))
            }
        }

        deduplicate(&properties)

        return DeviceSpec(name: obj["description"]?.stringValue ?? specType,
                          specType: specType,
                          properties: properties,
                          actions: actions)
    }

    /// `"描述 / 备注"`，备注为空时收掉尾部的 ` / `（对齐 Python 的 `.rstrip(' / ')`）
    static func joinedDescription(_ description: String?, comment: String?) -> String {
        var s = "\(description ?? "") / \(comment ?? "")"
        while s.hasSuffix(" ") || s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 同名属性加 `-siid` 后缀，仍冲突再加 `-piid`（对齐 Python `_deduplicate_names`）
    static func deduplicate(_ props: inout [DevProp]) {
        var counts: [String: Int] = [:]
        for p in props { counts[p.name, default: 0] += 1 }
        for i in props.indices where counts[props[i].name] ?? 0 > 1 {
            props[i].name = "\(props[i].name)-\(props[i].siid)"
        }
        counts.removeAll()
        for p in props { counts[p.name, default: 0] += 1 }
        for i in props.indices where counts[props[i].name] ?? 0 > 1 {
            props[i].name = "\(props[i].name)-\(props[i].piid)"
        }
    }

    // MARK: - 缓存

    private func cacheFile(_ specType: String) -> URL {
        cacheDir.appendingPathComponent(specType.replacingOccurrences(of: ":", with: "_") + ".json")
    }

    private struct Envelope: Codable {
        var version: Int
        var spec: DeviceSpec
    }

    private func loadCache(_ specType: String) -> DeviceSpec? {
        guard let data = try? Data(contentsOf: cacheFile(specType)),
              let env = try? JSONDecoder().decode(Envelope.self, from: data),
              env.version == Self.cacheVersion else { return nil }
        return env.spec
    }

    private func saveCache(_ spec: DeviceSpec, forType specType: String) {
        let env = Envelope(version: Self.cacheVersion, spec: spec)
        guard let data = try? JSONEncoder().encode(env) else { return }
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        try? data.write(to: cacheFile(specType), options: .atomic)
    }
}
