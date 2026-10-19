import Foundation

/// 数值属性（int / uint / float）的可取值范围与步长。
///
/// spec 里的 `value-range` 是 `[min, max, step]`；滑块必须严格按 step 取整后再下发，
/// 否则服务端会直接拒绝（米家对不合规的取值不四舍五入，只报错）。
public struct NumericRange: Sendable, Equatable {

    public let min: Double
    public let max: Double
    public let step: Double
    /// int / uint 只能下发整数
    public let isInteger: Bool

    public init(prop: DevProp) {
        if let range = prop.range, range.count >= 2 {
            self.min = range[0]
            self.max = range[1]
            self.step = range.count >= 3 && range[2] > 0 ? range[2] : Self.defaultStep(min: range[0], max: range[1])
        } else {
            // 没有 value-range 的数值属性给一个保守的默认值
            self.min = 0
            self.max = 100
            self.step = 1
        }
        self.isInteger = prop.type == "int" || prop.type == "uint"
    }

    /// spec 缺 step / step 为 0 时的兜底：整数属性取 1，小数按跨度取一个好看的值
    static func defaultStep(min: Double, max: Double) -> Double {
        guard max > min else { return 1 }
        let span = max - min
        if span <= 2 { return 0.1 }
        if span <= 20 { return 0.5 }
        return 1
    }

    /// 夹到区间内并按 step 对齐（滑块松手后真正下发的那个值）
    public func snapped(_ value: Double) -> Double {
        let s = step > 0 ? step : 1
        let clamped = Swift.min(Swift.max(value, min), max)
        guard s > 0 else { return clamped }
        let aligned = (round((clamped - min) / s) * s) + min
        return Swift.min(Swift.max(aligned, min), max)
    }

    /// 转成可以下发的值：整数属性发 `.int`，避免 `25.0` 这种让服务端困惑的浮点
    public func jsonValue(_ value: Double) -> JSONValue {
        let snapped = snapped(value)
        return isInteger ? .int(Int(snapped.rounded())) : .double(snapped)
    }

    /// 展示文案：整数不带小数点
    public func text(_ value: Double) -> String {
        if isInteger { return String(Int(snapped(value).rounded())) }
        let decimals = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2)
        return String(format: "%.\(decimals)f", snapped(value))
    }

    public static let numericTypes: Set<String> = ["int", "uint", "float"]
}

extension DevProp {
    /// 是否是可以拿滑块控制的数值属性
    public var isNumeric: Bool {
        NumericRange.numericTypes.contains(type)
    }
}
