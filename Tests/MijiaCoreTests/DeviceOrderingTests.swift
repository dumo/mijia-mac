import Testing
import Foundation
@testable import MijiaCore

@Suite("设备顺序与刷新节流")
struct DeviceOrderingTests {

    // MARK: - 顺序合并

    @Test("首次拉取：没有历史顺序时按云端顺序播种")
    func mergeSeedsFromCurrent() {
        #expect(DeviceOrdering.merge(existing: [], current: ["a", "b", "c"]) == ["a", "b", "c"])
    }

    @Test("刷新时保持既有顺序，不跟随云端返回顺序")
    func mergeKeepsExistingOrder() {
        #expect(DeviceOrdering.merge(existing: ["c", "a", "b"],
                                     current: ["a", "b", "c"]) == ["c", "a", "b"])
    }

    @Test("新设备追加到末尾，消失的设备被剔除")
    func mergeAppendsNewAndDropsMissing() {
        #expect(DeviceOrdering.merge(existing: ["a", "b", "c"],
                                     current: ["b", "d", "a"]) == ["a", "b", "d"])
    }

    @Test("重复 did 只保留第一次出现")
    func mergeDeduplicates() {
        #expect(DeviceOrdering.merge(existing: ["a", "a", "b"],
                                     current: ["a", "b", "b"]) == ["a", "b"])
    }

    // MARK: - 排序稳定性

    @Test("按顺序重排，未在顺序表里的元素排在最后且保持相对顺序")
    func sortedKeepsUnknownAtEnd() {
        let items = ["x", "a", "y", "b"]
        let out = DeviceOrdering.sorted(items, by: ["b", "a"]) { $0 }
        #expect(out == ["b", "a", "x", "y"])
    }

    @Test("顺序表里的重复项不会打乱排序")
    func sortedToleratesDuplicateOrder() {
        let out = DeviceOrdering.sorted(["a", "b"], by: ["b", "b", "a"]) { $0 }
        #expect(out == ["b", "a"])
    }

    // MARK: - 应用重排结果

    @Test("重排：把单个元素移到目标之前")
    func applyingMoveBefore() {
        #expect(DeviceOrdering.applying(sources: ["c"], before: "a",
                                        to: ["a", "b", "c", "d"]) == ["c", "a", "b", "d"])
    }

    @Test("重排：向下移动时插在目标之前")
    func applyingMoveDown() {
        #expect(DeviceOrdering.applying(sources: ["a"], before: "c",
                                        to: ["a", "b", "c", "d"]) == ["b", "a", "c", "d"])
    }

    @Test("重排：before 为 nil 或目标不存在时追加到末尾")
    func applyingMoveToEnd() {
        #expect(DeviceOrdering.applying(sources: ["a"], before: nil,
                                        to: ["a", "b", "c"]) == ["b", "c", "a"])
        #expect(DeviceOrdering.applying(sources: ["a"], before: "zzz",
                                        to: ["a", "b", "c"]) == ["b", "c", "a"])
    }

    @Test("重排：多个元素保持给定的相对顺序")
    func applyingMultipleSources() {
        #expect(DeviceOrdering.applying(sources: ["d", "a"], before: "b",
                                        to: ["a", "b", "c", "d"]) == ["d", "a", "b", "c"])
    }

    // MARK: - 刷新节流

    @Test("从未刷新过视为过期")
    func staleWhenNeverRefreshed() {
        #expect(RefreshPolicy.shouldRefresh(last: nil))
    }

    @Test("阈值内复用缓存，超过阈值才刷新")
    func staleByInterval() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(!RefreshPolicy.shouldRefresh(last: now.addingTimeInterval(-10), now: now, interval: 30))
        #expect(!RefreshPolicy.shouldRefresh(last: now.addingTimeInterval(-30), now: now, interval: 30))
        #expect(RefreshPolicy.shouldRefresh(last: now.addingTimeInterval(-31), now: now, interval: 30))
    }
}
