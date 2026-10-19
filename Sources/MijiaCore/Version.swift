import Foundation

/// 版本检测相关的纯函数（与 UI 解耦，便于单测）。
public enum VersionChecker {

    /// 从 GitHub Releases 的响应 JSON 里取出 `tag_name`。
    /// 解析失败（非 JSON / 缺字段）时返回 nil。
    public static func latestTag(from data: Data) -> String? {
        (try? JSONDecoder().decode([String: String].self, from: data))?["tag_name"]
    }

    /// 粗略的语义化版本比较：按 `.` 分段逐段比较，缺省段按 0 处理。
    /// `"v1.2"` 与 `"1.2.0"` 视为相等；`"1.10.0" > "1.9.0"`。
    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = lhs.trimmingCharacters(in: .init(charactersIn: "vV"))
            .split(separator: ".").compactMap { Int($0) }
        let b = rhs.trimmingCharacters(in: .init(charactersIn: "vV"))
            .split(separator: ".").compactMap { Int($0) }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
