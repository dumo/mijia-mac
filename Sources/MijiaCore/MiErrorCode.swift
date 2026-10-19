import Foundation

/// 米家返回码 → 人话。
/// 数值与文案取自小米官方 ha_xiaomi_home 的 i18n 表（公开事实数据）。
public enum MiErrorCode {

    private static let messages: [Int: String] = [
        -704042011: "设备离线",
        -704042001: "设备不存在",
        -704090001: "设备不存在",
        -704053036: "设备操作超时",
        -10007: "设备离线或不存在",
        -704010000: "设备控制失败",
        -704030013: "设备不支持该操作",
        -704220043: "操作过于频繁，请稍后再试",
        -1: "未知错误",
    ]

    public static func message(for code: Int) -> String? {
        messages[code]
    }

    /// 形如 `设备离线（-704042011）`
    public static func describe(_ code: Int) -> String {
        if let text = messages[code] { return "\(text)（\(code)）" }
        return "错误码 \(code)"
    }
}
