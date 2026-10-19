import Foundation

/// 设备卡片顺序的稳定合并规则。
///
/// 目标：首次拉取后顺序固定，后续刷新不因云端返回顺序或在线状态变化而重排；
/// 新设备追加到末尾，已消失的设备被剔除。
public enum DeviceOrdering {

    /// 把「已有顺序」和「本次拉取到的 did 列表」合并成新顺序。
    ///
    /// - 保留 `existing` 中仍然存在的设备，顺序不变；
    /// - `current` 里的新设备按出现顺序追加到末尾；
    /// - 已消失的设备自动剔除；重复 did 只保留第一次出现。
    public static func merge(existing: [String], current: [String]) -> [String] {
        let alive = Set(current)
        var result: [String] = []
        var seen = Set<String>()
        for did in existing where alive.contains(did) && !seen.contains(did) {
            result.append(did)
            seen.insert(did)
        }
        for did in current where !seen.contains(did) {
            result.append(did)
            seen.insert(did)
        }
        return result
    }

    /// 应用一次重排结果：把 `sources` 整体移动到 `before` 之前；`before == nil` 表示移到末尾。
    ///
    /// 对应 SwiftUI（macOS 27+）`.reorderable()` 回调里的
    /// `ReorderDifference.sources` 与 `destination.position`（`.before(id)` / `.end`）。
    /// `sources` 之间保持给定顺序；`before` 不在剩余列表里时退化为追加到末尾。
    public static func applying(sources: [String],
                                before: String?,
                                to order: [String]) -> [String] {
        let moving = sources.filter { order.contains($0) }
        guard !moving.isEmpty else { return order }
        var rest = order.filter { !moving.contains($0) }
        if let before, let index = rest.firstIndex(of: before) {
            rest.insert(contentsOf: moving, at: index)
        } else {
            rest.append(contentsOf: moving)
        }
        return rest
    }

    /// 按给定顺序重排元素。
    ///
    /// `order` 里没有的 id 排在最后，并保持它们原本的相对顺序
    /// （Swift 标准库排序不保证稳定，这里用原始下标兜底）。
    public static func sorted<T>(_ items: [T],
                                 by order: [String],
                                 id: (T) -> String) -> [T] {
        let rank = Dictionary(order.enumerated().map { ($0.element, $0.offset) },
                              uniquingKeysWith: { first, _ in first })
        return items.enumerated()
            .sorted { lhs, rhs in
                let left = rank[id(lhs.element)] ?? Int.max
                let right = rank[id(rhs.element)] ?? Int.max
                if left == right { return lhs.offset < rhs.offset }
                return left < right
            }
            .map(\.element)
    }
}
