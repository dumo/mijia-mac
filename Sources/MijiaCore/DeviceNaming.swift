import Foundation

/// 一个「可添加到工作台」的模块：要么是一组同服务属性（组合卡），
/// 要么是单个属性。动作不在这里，由调用方单独用 `actionKey` 生成。
public struct PropGroup: Sendable, Hashable {
    /// `group:{siid}`（组合卡）或属性名（单属性卡）
    public var key: String
    public var members: [DevProp]
    /// 组合卡标题所用的主属性；单属性卡时就是它自己
    public var master: DevProp?

    public var isComposite: Bool { key.hasPrefix(PropGroup.compositePrefix) }
    public static let compositePrefix = "group:"
}

public enum DeviceNaming {

    // MARK: - 命名

    /// `"Switch Status / 开关状态"` → `"开关状态"`。
    ///
    /// miot-spec 的 description 形如 `"英文 / 中文"`，中文在斜杠后；
    /// 有些属性只有中文（`" / 室内管温"`），有些只有英文。都退化到能用为止。
    public static func chineseTitle(desc: String, fallbackName: String) -> String {
        let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackName }

        if trimmed.contains("/") {
            let parts = trimmed.components(separatedBy: "/")
            let last = parts.last?.trimmingCharacters(in: .whitespaces) ?? ""
            if !last.isEmpty { return last }
            let first = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
            return first.isEmpty ? fallbackName : first
        }
        return trimmed
    }

    /// `"Switch Status / 开关状态"` → `"Switch Status"`（技术名，用于副标题与去重后缀）
    public static func englishTitle(desc: String, fallbackName: String) -> String {
        let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackName }

        if trimmed.contains("/") {
            let first = trimmed.components(separatedBy: "/").first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            return first.isEmpty ? fallbackName : first
        }
        return trimmed
    }

    /// 标题重复时追加 `(属性名)` 消歧，例如两个「静音」→ `静音 (mute-2-1)`
    public static func disambiguate(
        _ items: [(key: String, title: String, name: String)]
    ) -> [(key: String, title: String)] {
        var counts: [String: Int] = [:]
        for item in items { counts[item.title, default: 0] += 1 }
        return items.map { item in
            (counts[item.title] ?? 0) > 1 ? (item.key, "\(item.title) (\(item.name))") : (item.key, item.title)
        }
    }

    /// 副标题元信息：`可写 · int · 范围 1-100 · 3 选项`
    public static func metaText(_ prop: DevProp) -> String {
        var parts: [String] = []
        if prop.isWritable {
            parts.append("可写")
        } else if prop.isReadable {
            parts.append("只读")
        } else {
            parts.append("不可读")
        }
        parts.append(prop.type)
        if let range = prop.range, range.count >= 2 {
            parts.append("范围 \(Self.number(range[0]))-\(Self.number(range[1]))")
        }
        if let list = prop.valueList, !list.isEmpty {
            parts.append("\(list.count) 选项")
        }
        return parts.joined(separator: " · ")
    }

    /// 紧凑元信息，给组合卡里窄的成员行用：`16-30` / `4 选项` / `string`，开关类返回空。
    /// 完整版（带「可写 / 范围」）在单属性卡的副标题里用。
    public static func compactMeta(_ prop: DevProp) -> String {
        if prop.type == "bool" { return "" }
        if let list = prop.valueList, !list.isEmpty { return "\(list.count) 选项" }
        if let range = prop.range, range.count >= 2 {
            return "\(Self.number(range[0]))-\(Self.number(range[1]))"
        }
        return prop.type
    }

    static func number(_ value: Double) -> String {
        if value == value.rounded() {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }

    // MARK: - 分组

    /// 合成名（如 `air-conditioner-2-1`、`fan-control-3-2`）：末尾两段都是数字，
    /// 说明 name 是「服务类型-siid-piid」拼出来的，本身没有语义，不能按前缀聚合，
    /// 否则会把整个服务的 80+ 个属性又聚成一张巨型组合卡。
    private static func isSynthesized(_ name: String) -> Bool {
        let parts = name.split(separator: "-")
        guard parts.count >= 3 else { return false }
        return Int(parts[parts.count - 1]) != nil && Int(parts[parts.count - 2]) != nil
    }

    /// 属性名前缀：按 `- _ .` 分段取前两段拼接，作为聚合 key。
    /// 例如 `mode-one-bright` / `mode-one-ct` → `mode_one`，`target-temperature` → `target_temperature`，
    /// 单段名（`on` / `mode`）→ 自身。用于把语义相关的属性聚成小组，而非整个 siid 服务。
    /// 合成名（`air-conditioner-2-1`）直接返回原名，保证它们各自独立成卡。
    public static func namePrefix(_ name: String) -> String {
        if isSynthesized(name) { return name }
        let segments = name
            .components(separatedBy: CharacterSet(charactersIn: "-_."))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return segments.prefix(2).joined(separator: "_")
    }

    /// 按属性名前缀分组（对齐 Windows 版：按名前缀聚合成语义小组）。
    /// 同前缀多成员且能选出 master → 组合卡；否则每个属性独立成卡，
    /// 避免把一整个服务的 12+ 个无关属性硬塞进一张「开关」组合卡。
    public static func groups(_ props: [DevProp]) -> [PropGroup] {
        let sorted = props.sorted { a, b in
            if a.siid != b.siid { return a.siid < b.siid }
            return a.piid < b.piid
        }
        var buckets: [String: [DevProp]] = [:]
        var order: [String] = []
        for prop in sorted {
            let prefix = namePrefix(prop.name)
            if buckets[prefix] == nil { order.append(prefix); buckets[prefix] = [] }
            buckets[prefix]!.append(prop)
        }

        var result: [PropGroup] = []
        for prefix in order {
            guard let members = buckets[prefix], !members.isEmpty else { continue }
            if members.count > 1, let master = pickMaster(members) {
                result.append(PropGroup(key: "\(PropGroup.compositePrefix)\(prefix)",
                                        members: members,
                                        master: master))
            } else {
                for member in members {
                    result.append(PropGroup(key: member.name, members: [member], master: member))
                }
            }
        }
        return result
    }

    /// master 选取优先级：名为 on 的可写 bool → 名字含 on/switch 的可写 bool
    /// → 组内第一个可写 bool → 组内第一个可写属性
    public static func pickMaster(_ members: [DevProp]) -> DevProp? {
        if let exact = members.first(where: { isSwitchLike($0) && $0.name == "on" }) { return exact }
        if let named = members.first(where: {
            isSwitchLike($0) && ($0.name.hasPrefix("on") || $0.name.hasPrefix("switch"))
        }) { return named }
        if let anyBool = members.first(where: { isSwitchLike($0) }) { return anyBool }
        return members.first(where: \.isWritable)
    }

    private static func isSwitchLike(_ prop: DevProp) -> Bool {
        prop.isWritable && prop.type == "bool"
    }

    // MARK: - 默认模块

    /// 首次进入设备详情页时默认展示的模块 key：只摆少数核心控制（开关 + 模式 + 温度 + 风速…），
    /// 上限约 6 个，其余从「添加功能」抽屉选取；不再默认整服务的大组合卡。
    public static func defaultKeys(props: [DevProp], actions: [DevAction]) -> [String] {
        let groups = groups(props)
        var result: [String] = []
        func addIfMissing(_ key: String) {
            if !result.contains(key) { result.append(key) }
        }
        // 归一化检索串：name + 描述（含中英文）+ 中文标题，把 - _ 换成空格，
        // 这样合成名（air-conditioner-2-2）也能靠描述里的「Mode / 模式」被识别。
        func haystack(_ m: DevProp) -> String {
            let title = chineseTitle(desc: m.desc, fallbackName: m.name)
            return "\(m.name) \(m.desc) \(title)"
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
        }

        /// 主开关：MIoT 惯例 2.1 为总开关；或名字就是 on；或标题/英文描述表明是电源开关。
        func isPowerLike(_ g: PropGroup) -> Bool {
            guard let m = g.master, m.isWritable, m.type == "bool" else { return false }
            if m.id == "2.1" { return true }
            if isOnName(m.name) { return true }
            let title = chineseTitle(desc: m.desc, fallbackName: m.name)
            let english = englishTitle(desc: m.desc, fallbackName: m.name).lowercased()
            return title == "开关" || title == "电源" || english.contains("switch status")
        }

        // 1. 主开关：优先总开关，其次 mute/power/switch 等布尔主控
        //    （避免把「是否为音箱模式」这类设置型 bool 误当成主控）
        if let g = groups.first(where: isPowerLike) {
            addIfMissing(g.key)
        } else {
            for name in ["mute", "power", "switch"] {
                if let g = groups.first(where: { g in
                    guard let m = g.master, m.isWritable, m.type == "bool" else { return false }
                    return haystack(m).contains(name) && !result.contains(g.key)
                }) {
                    addIfMissing(g.key)
                    break
                }
            }
        }

        // 2. 核心控制：按语义关键字挑选（模式 / 温度 / 风速 / 湿度 / 摆风 / 亮度 / 音量…）。
        //    合成名靠描述匹配；除「摆风」外不选 bool，避免设置型开关混进主控。
        let coreKeywords = [
            "mode", "target temperature", "fan level", "humidity",
            "swing", "speed", "brightness", "color temperature", "volume",
            "level", "temperature",
        ]
        for kw in coreKeywords {
            if result.count >= 6 { break }
            if let g = groups.first(where: { g in
                guard let m = g.master, m.isWritable else { return false }
                if m.type == "bool" && kw != "swing" { return false }
                return haystack(m).contains(kw) && !result.contains(g.key)
            }) { addIfMissing(g.key) }
        }

        // 3. 仍然一个都没选上：兜底选第一个可写属性
        if result.isEmpty {
            if let g = groups.first(where: { $0.master?.isWritable == true }) { addIfMissing(g.key) }
        }

        // 4. 没有任何可控属性（传感器等）：摆几个可读状态 + 一个动作，避免空白
        if result.isEmpty {
            let readable = groups.filter { $0.master?.isReadable == true }.map(\.key)
            if let action = actions.first {
                return Array(readable.prefix(2)) + [actionKey(action)]
            }
            return Array(readable.prefix(3))
        }
        return result
    }

    static func isOnName(_ name: String) -> Bool {
        name == "on" || name.hasPrefix("on-") || name.hasPrefix("on_")
    }

    /// 动作用 `siid.aiid` 做 key：同一个动作名（如 `stop-stream`）会在多个服务下重复出现，
    /// 只用名字会撞 key。
    public static func actionKey(_ action: DevAction) -> String {
        "action:\(action.siid).\(action.aiid)"
    }

    /// 需要文本参数的动作（小爱音箱的文本指令、播放文本等）
    public static let textActionNames: Set<String> = [
        "execute-text-directive", "play-text", "play-music", "play-radio",
    ]

    public static func needsText(_ actionName: String) -> Bool {
        textActionNames.contains(actionName)
    }

    /// 判断 model 是否属于小爱音箱系列。
    ///
    /// 不能用过短的子串（如 `xiaomi.ai`）：`xiaomi.airc.*`（空调）、`xiaomi.airp.*`（净化器）、
    /// `xiaomi.airfresh.*`（新风机）等所有 `xiaomi.air*` 型号都会误命中。
    public static func isSpeakerModel(_ model: String) -> Bool {
        let m = model.lowercased()
        return m.contains("wifispeaker")
            || m.contains("xiaomi.speaker")
            || m.contains("xiaomi.ai.speaker")
            || m.contains("aispeaker")
    }
}
