import Testing
import Foundation
@testable import MijiaCore

@Suite("写后乐观值与静默期")
struct WriteGuardTests {

    @Test("静默期内的云端旧值一律丢弃")
    func silenceWindow() {
        var g = WriteGuard()
        g.markWritten("on", value: .bool(true), now: 100)

        let early = g.shouldIgnore("on", incoming: .bool(false), now: 100.5)
        let nearEdge = g.shouldIgnore("on", incoming: .bool(false), now: 102.9)
        // 即便回读的是新值也照样丢弃（静默期无条件）
        let sameValue = g.shouldIgnore("on", incoming: .bool(true), now: 101)

        #expect(early)
        #expect(nearEdge)
        #expect(sameValue)
    }

    @Test("静默期之后、宽容期内：不等值丢弃，等值接受")
    func toleranceWindow() {
        var g = WriteGuard()
        g.markWritten("on", value: .bool(true), now: 100)

        let equal = g.shouldIgnore("on", incoming: .bool(true), now: 105)
        let different = g.shouldIgnore("on", incoming: .bool(false), now: 105)
        let nearExpiry = g.shouldIgnore("on", incoming: .bool(false), now: 109.9)

        #expect(!equal)
        #expect(different)
        #expect(nearExpiry)
    }

    @Test("超过宽容期后完全信任云端")
    func expired() {
        var g = WriteGuard()
        g.markWritten("on", value: .bool(true), now: 100)

        let afterExpiry = g.shouldIgnore("on", incoming: .bool(false), now: 110)
        let stillGuarding = g.isGuarding("on", now: 110)
        #expect(!afterExpiry)
        #expect(!stillGuarding)

        g.prune(now: 110)
        #expect(g.lastWritten("on") == nil)
    }

    @Test("未记录过的 key 直接放行")
    func unknownKey() {
        var g = WriteGuard()
        let ignored = g.shouldIgnore("on", incoming: .bool(false), now: 100)
        let guarding = g.isGuarding("on", now: 100)
        #expect(!ignored)
        #expect(!guarding)
        #expect(g.lastWritten("on") == nil)
    }

    @Test("数值比较宽松：50 / 50.0 视为相等")
    func looseEquality() {
        var g = WriteGuard()
        g.markWritten("brightness", value: .int(50), now: 0)
        let same = g.shouldIgnore("brightness", incoming: .double(50.0), now: 5)
        let different = g.shouldIgnore("brightness", incoming: .double(49.5), now: 5)
        #expect(!same)
        #expect(different)

        var g2 = WriteGuard()
        g2.markWritten("on", value: .bool(true), now: 0)
        let boolVsInt = g2.shouldIgnore("on", incoming: .int(1), now: 5)
        #expect(!boolVsInt)
    }

    @Test("下发失败回弹可用 clear 立刻放弃守卫")
    func clear() {
        var g = WriteGuard()
        g.markWritten("on", value: .bool(true), now: 100)
        #expect(g.lastWritten("on") == .bool(true))

        g.clear("on")
        let afterClear = g.shouldIgnore("on", incoming: .bool(false), now: 100.1)
        #expect(g.lastWritten("on") == nil)
        #expect(!afterClear)
    }

    @Test("时钟回拨不拦截")
    func clockRewind() {
        var g = WriteGuard()
        g.markWritten("on", value: .bool(true), now: 100)
        let rewound = g.shouldIgnore("on", incoming: .bool(false), now: 90)
        #expect(!rewound)
    }

    @Test("prune 只清掉过期记录")
    func prune() {
        var g = WriteGuard()
        g.markWritten("a", value: .int(1), now: 0)
        g.markWritten("b", value: .int(2), now: 90)
        g.prune(now: 95)
        #expect(g.lastWritten("a") == nil)
        #expect(g.lastWritten("b") == .int(2))
    }

    @Test("每个 key 独立计时，互不干扰")
    func perKey() {
        var g = WriteGuard()
        g.markWritten("on", value: .bool(true), now: 100)
        g.markWritten("brightness", value: .int(30), now: 108)

        let onExpired = g.shouldIgnore("on", incoming: .bool(false), now: 110)
        let brightSilenced = g.shouldIgnore("brightness", incoming: .int(80), now: 110)

        #expect(!onExpired)      // on 已过 10s，接受云端
        #expect(brightSilenced)  // 亮度才过 2s，仍在静默期
    }
}
