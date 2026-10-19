import Foundation

/// 刷新节流策略：距上次刷新超过阈值才真正请求，否则复用缓存。
public enum RefreshPolicy {

    /// 默认阈值（秒）。手动刷新会绕过该判断。
    public static let defaultInterval: TimeInterval = 30

    public static func shouldRefresh(last: Date?,
                                     now: Date = Date(),
                                     interval: TimeInterval = defaultInterval) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) > interval
    }
}
