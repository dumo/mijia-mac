import Testing
import Foundation
@testable import MijiaCore

@Suite("数值属性的区间与步长")
struct NumericRangeTests {

    private func prop(_ type: String, range: [Double]?) -> DevProp {
        DevProp(name: "level", desc: "Level / 档位", type: type, rw: "rw",
                range: range, valueList: nil, siid: 2, piid: 1)
    }

    @Test("按 step 对齐后再下发")
    func snapping() {
        let r = NumericRange(prop: prop("int", range: [1, 100, 1]))
        #expect(r.snapped(37.4) == 37)
        #expect(r.snapped(37.6) == 38)
        #expect(r.snapped(1) == 1)
        #expect(r.snapped(100) == 100)
    }

    @Test("越界会被夹回区间")
    func clamping() {
        let r = NumericRange(prop: prop("int", range: [10, 50, 5]))
        #expect(r.snapped(-20) == 10)
        #expect(r.snapped(999) == 50)
        #expect(r.snapped(23) == 25)
    }

    @Test("小数步长")
    func fractionalStep() {
        let r = NumericRange(prop: prop("float", range: [0.5, 30.5, 0.5]))
        let snapped = r.snapped(22.3)
        #expect(abs(snapped - 22.5) < 1e-9)
        #expect(r.text(22.3) == "22.5")
    }

    @Test("整数属性下发 .int，小数属性下发 .double")
    func jsonValue() {
        let intRange = NumericRange(prop: prop("int", range: [0, 100, 1]))
        #expect(intRange.jsonValue(42.7) == .int(43))

        let uintRange = NumericRange(prop: prop("uint", range: [0, 255, 1]))
        #expect(uintRange.jsonValue(3.2) == .int(3))

        let floatRange = NumericRange(prop: prop("float", range: [16, 30, 0.5]))
        #expect(floatRange.jsonValue(26.5) == .double(26.5))
    }

    @Test("没有 value-range 时用保守默认值")
    func missingRange() {
        let r = NumericRange(prop: prop("int", range: nil))
        #expect(r.min == 0)
        #expect(r.max == 100)
        #expect(r.step == 1)
        #expect(r.snapped(500) == 100)
    }

    @Test("step 缺失或为 0 时按跨度兜底")
    func zeroStep() {
        #expect(NumericRange(prop: prop("float", range: [0, 1, 0])).step == 0.1)
        #expect(NumericRange(prop: prop("float", range: [16, 30, 0])).step == 0.5)
        #expect(NumericRange(prop: prop("int", range: [0, 100, 0])).step == 1)
        #expect(NumericRange(prop: prop("int", range: [0, 200, 0])).step == 1)
    }

    @Test("展示文案：整数不带小数点")
    func displayText() {
        #expect(NumericRange(prop: prop("int", range: [0, 100, 1])).text(7) == "7")
        let half = NumericRange(prop: prop("float", range: [0, 10, 0.5]))
        #expect(half.text(7.26) == "7.5")
    }

    @Test("只有数值类型才生成滑块")
    func numericDetection() {
        #expect(prop("int", range: [0, 1, 1]).isNumeric)
        #expect(prop("uint", range: [0, 1, 1]).isNumeric)
        #expect(prop("float", range: [0, 1, 1]).isNumeric)
        #expect(!prop("bool", range: nil).isNumeric)
        #expect(!prop("string", range: nil).isNumeric)
    }
}
