import Foundation

/// 写后乐观值 + 静默期守卫（纯逻辑，时间可注入，便于单测）。
///
/// 米家的云端回读有延迟：刚下发 `on=true`，紧接着的一次 `getProps` 往往还返回
/// `false`，UI 上表现为开关「弹回去」。Windows 版的做法是给刚写过的属性加一段
/// 静默期，期间一律忽略云端旧值；静默期之后的一段时间里，只有「与已写值相等」
/// 才接受回读（说明云端确实已经同步），否则继续忽略，直到超时才彻底信任云端。
public struct WriteGuard: Sendable {

    /// 静默期：这段时间内无条件忽略云端回读（秒）
    public static let silenceWindow: TimeInterval = 3
    /// 宽容期：静默期之后这段时间内，只接受与已写值相等的回读（秒，从写入时刻起算）
    public static let toleranceWindow: TimeInterval = 10

    private struct Entry: Sendable {
        var value: JSONValue
        var writtenAt: TimeInterval
    }

    private var entries: [String: Entry] = [:]

    public init() {}

    /// 记录一次下发。`now` 为当前时间戳（秒，单调时钟或 epoch 均可，只要与
    /// `shouldIgnore` 用的是同一套基准）。
    public mutating func markWritten(_ key: String, value: JSONValue, now: TimeInterval) {
        entries[key] = Entry(value: value, writtenAt: now)
    }

    /// 放弃对某个 key 的守卫（例如用户手动刷新、或下发失败回弹）。
    public mutating func clear(_ key: String) {
        entries.removeValue(forKey: key)
    }

    /// 上次下发的值（用于乐观渲染）。没有记录时返回 nil。
    public func lastWritten(_ key: String) -> JSONValue? {
        entries[key]?.value
    }

    /// 该 key 当前是否处于守卫期（静默期或宽容期内）。
    public func isGuarding(_ key: String, now: TimeInterval) -> Bool {
        guard let entry = entries[key] else { return false }
        return now - entry.writtenAt < Self.toleranceWindow
    }

    /// 云端回读值是否应当被丢弃。
    ///
    /// - 静默期内（`now - writtenAt < 3`）：无条件丢弃。
    /// - 宽容期内（`now - writtenAt < 10`）且回读值 != 已写值：丢弃。
    /// - 其余情况：接受（守卫已到期，之后完全信任云端，记录由 `prune` 清理）。
    public func shouldIgnore(_ key: String, incoming: JSONValue, now: TimeInterval) -> Bool {
        guard let entry = entries[key] else { return false }
        let elapsed = now - entry.writtenAt
        if elapsed < 0 { return false }          // 时钟回拨：不拦
        if elapsed >= Self.toleranceWindow { return false }
        if elapsed < Self.silenceWindow { return true }
        return !Self.looseEqual(entry.value, incoming)
    }

    /// 丢掉所有已过期的记录，避免长时间运行后字典无限增长。
    public mutating func prune(now: TimeInterval) {
        entries = entries.filter { now - $0.value.writtenAt < Self.toleranceWindow }
    }

    /// 数值比较要宽松：`1`、`1.0`、`"1"` 都算相等——云端回读的类型经常变。
    public static func looseEqual(_ lhs: JSONValue, _ rhs: JSONValue) -> Bool {
        if lhs == rhs { return true }
        if let a = lhs.doubleValue, let b = rhs.doubleValue { return abs(a - b) < 1e-6 }
        if let a = lhs.boolValue, let b = rhs.boolValue { return a == b }
        if let a = lhs.stringValue, let b = rhs.stringValue { return a == b }
        return false
    }
}
