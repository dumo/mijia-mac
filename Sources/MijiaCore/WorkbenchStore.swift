import Foundation

/// 工作台布局持久化：记录每个设备「已添加哪些功能模块、以什么顺序展示」。
///
/// Windows 版对应 `workbench.json`。这里同样按 `did` 存一份 key 数组，
/// key 的形态由 `DeviceNaming` 定义（`group:{siid}` / 属性名 / `action:xxx`）。
///
/// 目录可注入，便于单测用临时目录；写入走「临时文件 + 原子替换」，
/// 避免写到一半崩溃把 `workbench.json` 写坏。
public struct WorkbenchStore: Sendable {

    public let fileURL: URL
    private var data: [String: [String]]

    public init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("workbench.json")
        self.data = (try? Self.load(fileURL)) ?? [:]
    }

    public static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mijia-mac")
    }

    // MARK: - 读取

    /// 该设备已保存的模块 key。返回 nil 表示「从未配置过」（区别于「配置为空」）。
    public func keys(for did: String) -> [String]? {
        data[did]
    }

    /// 取已保存的 key；没有则写入 `fallback` 并返回它（首次进入自动铺默认值）。
    public mutating func keys(for did: String, defaultingTo fallback: [String] = []) -> [String] {
        if let existing = data[did] { return existing }
        if fallback.isEmpty { return [] }
        data[did] = fallback
        save()
        return fallback
    }

    public func contains(_ key: String, in did: String) -> Bool {
        data[did]?.contains(key) ?? false
    }

    // MARK: - 修改

    public mutating func setKeys(_ keys: [String], for did: String) {
        data[did] = keys
        save()
    }

    /// 追加一个模块（已存在则不动），返回是否真的新增了。
    @discardableResult
    public mutating func add(_ key: String, to did: String) -> Bool {
        var keys = data[did] ?? []
        if keys.contains(key) { return false }
        keys.append(key)
        data[did] = keys
        save()
        return true
    }

    @discardableResult
    public mutating func remove(_ key: String, from did: String) -> Bool {
        guard var keys = data[did], let index = keys.firstIndex(of: key) else { return false }
        keys.remove(at: index)
        data[did] = keys
        save()
        return true
    }

    /// 列表内移动（编辑模式拖拽排序）。越界索引直接忽略，不崩。
    public mutating func move(did: String, fromOffsets source: IndexSet, toOffset destination: Int) {
        guard var keys = data[did] else { return }
        let valid = source.filter { keys.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let clamped = min(max(destination, 0), keys.count)
        let picked = valid.sorted().map { keys[$0] }
        for idx in valid.sorted(by: >) { keys.remove(at: idx) }
        var insertAt = clamped
        for idx in valid where idx < clamped { insertAt -= 1 }
        insertAt = min(max(insertAt, 0), keys.count)
        keys.insert(contentsOf: picked, at: insertAt)
        data[did] = keys
        save()
    }

    public mutating func removeAll(for did: String) {
        data.removeValue(forKey: did)
        save()
    }

    // MARK: - 持久化

    private mutating func save() {
        guard let payload = try? JSONEncoder().encode(data) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let tmp = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try payload.write(to: tmp, options: .atomic)
            // 目标不存在时 replaceItemAt 会失败，先落一次
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.moveItem(at: tmp, to: fileURL)
            } else {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    private static func load(_ url: URL) throws -> [String: [String]] {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([String: [String]].self, from: data)
    }
}
