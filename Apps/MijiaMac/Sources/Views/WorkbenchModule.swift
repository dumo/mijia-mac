import Foundation
import MijiaCore

/// 工作台上的一块功能：一组同服务属性（组合卡）、单个属性，或一个动作。
enum WorkbenchModule: Identifiable, Hashable {
    case group(PropGroup)
    case prop(DevProp)
    case action(DevAction)

    var key: String {
        switch self {
        case .group(let group): return group.key
        case .prop(let prop): return prop.name
        case .action(let action): return DeviceNaming.actionKey(action)
        }
    }

    /// 重名时用来消歧的后缀素材
    var disambiguatingName: String {
        switch self {
        case .group(let group): return group.master?.name ?? group.key
        case .prop(let prop): return prop.name
        case .action(let action): return "\(action.name) \(action.siid).\(action.aiid)"
        }
    }

    var id: String { key }

    var isComposite: Bool {
        if case .group = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .group(let group):
            if let master = group.master { return PropText.title(master) }
            return group.members.first.map { PropText.title($0) } ?? "功能"
        case .prop(let prop): return PropText.title(prop)
        case .action(let action): return PropText.title(action)
        }
    }

    var subtitle: String {
        switch self {
        case .group(let group): return "组合 · \(group.members.count) 项"
        case .prop(let prop):
            var parts = [DeviceNaming.metaText(prop)]
            let technical = PropText.technical(prop)
            if technical != PropText.title(prop) { parts.insert(technical, at: 0) }
            return parts.joined(separator: " · ")
        case .action(let action):
            let technical = DeviceNaming.englishTitle(desc: action.desc, fallbackName: action.name)
            return technical == title ? "动作" : "\(technical) · 动作"
        }
    }

    /// 组合卡里除 master 之外的成员
    var subMembers: [DevProp] {
        guard case .group(let group) = self, let master = group.master else { return [] }
        return group.members.filter { $0.id != master.id }
    }

    var master: DevProp? {
        switch self {
        case .group(let group): return group.master
        case .prop(let prop): return prop
        case .action: return nil
        }
    }

    /// 卡内全部属性（组合卡展开时才全画）
    var allProperties: [DevProp] {
        switch self {
        case .group(let group): return group.members
        case .prop(let prop): return [prop]
        case .action: return []
        }
    }
}

/// 把持久化的 key 还原成模块；同时提供「可添加的全量清单」给抽屉用。
struct WorkbenchResolver {
    private let byKey: [String: WorkbenchModule]
    private let titles: [String: String]
    private let propTitles: [String: String]
    let spec: DeviceSpec

    init(spec: DeviceSpec) {
        self.spec = spec
        var list: [WorkbenchModule] = []
        for group in DeviceNaming.groups(spec.properties) {
            // 只有多成员的服务才是组合卡；单成员一律拆成单属性卡
            if group.isComposite {
                list.append(.group(group))
            } else if let member = group.members.first {
                list.append(.prop(member))
            }
        }
        for action in spec.actions { list.append(.action(action)) }

        self.byKey = Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
        self.titles = Self.disambiguatedTitles(list)
        // 组合卡展开后的成员行也要消歧（成员不单独成卡，所以另算一份）
        self.propTitles = Dictionary(uniqueKeysWithValues: DeviceNaming.disambiguate(
            spec.properties.map {
                (key: $0.name,
                 title: DeviceNaming.chineseTitle(desc: $0.desc, fallbackName: $0.name),
                 name: $0.name)
            }))
    }

    func module(for key: String) -> WorkbenchModule? { byKey[key] }

    func modules(for keys: [String]) -> [WorkbenchModule] {
        keys.compactMap { byKey[$0] }
    }

    /// 展示标题（重名时带后缀消歧）
    func title(for key: String) -> String {
        titles[key] ?? byKey[key]?.title ?? key
    }

    /// 只在「当前可见的模块」范围内消歧：只有同屏重名才追加 `(属性名)`。
    /// 避免空调「开关」因其它服务也有同名属性而被无谓加上 `(air-conditioner-2-1)`。
    func visibleTitles(for keys: [String]) -> [String: String] {
        let modules = keys.compactMap { byKey[$0] }
        var counts: [String: Int] = [:]
        for module in modules { counts[module.title, default: 0] += 1 }
        var result: [String: String] = [:]
        for module in modules {
            if (counts[module.title] ?? 0) > 1 {
                result[module.key] = "\(module.title) (\(module.disambiguatingName))"
            } else {
                result[module.key] = module.title
            }
        }
        return result
    }

    /// 单个属性的展示标题（含组合卡成员）
    func title(forProp prop: DevProp) -> String {
        propTitles[prop.name]
            ?? DeviceNaming.chineseTitle(desc: prop.desc, fallbackName: prop.name)
    }

    /// 抽屉里的全量清单：属性（组合卡在前）与动作，顺序稳定
    var addable: [WorkbenchModule] {
        var result: [WorkbenchModule] = []
        for group in DeviceNaming.groups(spec.properties) {
            if group.isComposite {
                result.append(.group(group))
            } else if let member = group.members.first {
                result.append(.prop(member))
            }
        }
        for action in spec.actions { result.append(.action(action)) }
        return result
    }

    /// 同名标题追加 `(属性名)`；名称也撞了（同一动作在多个服务下重复）再补 key
    private static func disambiguatedTitles(_ modules: [WorkbenchModule]) -> [String: String] {
        var counts: [String: Int] = [:]
        for module in modules { counts[module.title, default: 0] += 1 }

        var result: [String: String] = [:]
        var used: Set<String> = []
        for module in modules {
            var title = module.title
            if (counts[title] ?? 0) > 1 {
                title += " (\(module.disambiguatingName))"
                if used.contains(title) { title += " \(module.key)" }
            }
            used.insert(title)
            result[module.key] = title
        }
        return result
    }
}
