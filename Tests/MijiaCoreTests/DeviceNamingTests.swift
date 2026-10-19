import Testing
import Foundation
@testable import MijiaCore

@Suite("设备命名与分组")
struct DeviceNamingTests {

    // MARK: - 辅助

    private func prop(_ name: String,
                     desc: String = "",
                     type: String = "bool",
                     rw: String = "rw",
                     siid: Int = 1,
                     piid: Int = 1,
                     range: [Double]? = nil,
                     valueList: [ValueOption]? = nil) -> DevProp {
        DevProp(name: name, desc: desc, type: type, rw: rw,
                range: range, valueList: valueList, siid: siid, piid: piid)
    }

    // MARK: - 中文标题

    @Test("'Switch Status / 开关状态' 只取中文")
    func chineseTitleBasic() {
        #expect(DeviceNaming.chineseTitle(desc: "Switch Status / 开关状态", fallbackName: "switch-status") == "开关状态")
    }

    @Test("只有中文描述时正常返回")
    func chineseTitleOnlyChinese() {
        #expect(DeviceNaming.chineseTitle(desc: " / 室内管温", fallbackName: "temp") == "室内管温")
    }

    @Test("只有英文时退回英文，描述为空则退回属性名")
    func chineseTitleFallback() {
        #expect(DeviceNaming.chineseTitle(desc: "Countdown Time", fallbackName: "countdown") == "Countdown Time")
        #expect(DeviceNaming.chineseTitle(desc: "   ", fallbackName: "countdown") == "countdown")
        #expect(DeviceNaming.chineseTitle(desc: "/", fallbackName: "countdown") == "countdown")
    }

    @Test("英文标题用于副标题与去重后缀")
    func englishTitle() {
        #expect(DeviceNaming.englishTitle(desc: "Switch Status / 开关状态", fallbackName: "switch") == "Switch Status")
        #expect(DeviceNaming.englishTitle(desc: "", fallbackName: "switch") == "switch")
    }

    // MARK: - 消歧

    @Test("同名标题追加属性名消歧，不重复的不动")
    func disambiguate() {
        let items: [(key: String, title: String, name: String)] = [
            (key: "a", title: "静音", name: "mute-2-1"),
            (key: "b", title: "静音", name: "mute-3-1"),
            (key: "c", title: "开关", name: "on"),
        ]
        let out = DeviceNaming.disambiguate(items)
        #expect(out[0].1 == "静音 (mute-2-1)")
        #expect(out[1].1 == "静音 (mute-3-1)")
        #expect(out[2].1 == "开关")
    }

    // MARK: - 元信息

    @Test("副标题拼出 可写 · int · 范围 · 选项")
    func metaText() {
        let p = prop("brightness", type: "int", rw: "rw", range: [1, 100, 1],
                     valueList: nil)
        #expect(DeviceNaming.metaText(p) == "可写 · int · 范围 1-100")

        let ro = prop("temp", type: "float", rw: "r", range: [0.5, 30.5, 0.5])
        #expect(DeviceNaming.metaText(ro) == "只读 · float · 范围 0.50-30.50")

        let enumProp = prop("mode", type: "uint", rw: "rw",
                            valueList: [ValueOption(value: 0, desc: "自动"),
                                        ValueOption(value: 1, desc: "制冷"),
                                        ValueOption(value: 2, desc: "制热")])
        #expect(DeviceNaming.metaText(enumProp) == "可写 · uint · 3 选项")
    }

    @Test("大数值不要把整数写成 2 位小数（摄像机存储容量 2147483648）")
    func metaTextLargeRange() {
        let p = prop("storage", type: "uint", rw: "r", range: [0, 2147483648, 1])
        #expect(DeviceNaming.metaText(p) == "只读 · uint · 范围 0-2147483648")
    }

    @Test("成员行用紧凑元信息：开关留空、数值给区间、枚举给选项数")
    func compactMeta() {
        #expect(DeviceNaming.compactMeta(prop("on")) == "")
        #expect(DeviceNaming.compactMeta(prop("temp", type: "float", range: [16, 30, 1])) == "16-30")
        #expect(DeviceNaming.compactMeta(prop("mode", type: "uint",
                                             valueList: [ValueOption(value: 0, desc: "自动"),
                                                         ValueOption(value: 1, desc: "制冷")])) == "2 选项")
        #expect(DeviceNaming.compactMeta(prop("fault", type: "string", rw: "r")) == "string")
    }

    // MARK: - 分组

    @Test("同前缀的多属性聚合成组合卡，不同前缀各自独立")
    func groupComposite() {
        let props = [
            prop("on", desc: "Switch Status / 开关状态", siid: 2, piid: 1),
            prop("mode-one-bright", desc: "Brightness / 亮度", type: "int", siid: 2, piid: 2),
            prop("mode-one-color-temperature", desc: "Color Temperature / 色温", type: "int", siid: 2, piid: 3),
        ]
        let groups = DeviceNaming.groups(props)
        #expect(groups.count == 2)
        #expect(groups.map(\.key) == ["on", "group:mode_one"])
        #expect(groups[1].isComposite)
        #expect(groups[1].members.count == 2)
    }

    @Test("选不出 master 的服务拆成独立卡")
    func groupStandalone() {
        let props = [
            prop("temperature", desc: "Temperature / 温度", type: "float", rw: "r", siid: 3, piid: 1),
            prop("humidity", desc: "Humidity / 湿度", type: "float", rw: "r", siid: 3, piid: 2),
        ]
        let groups = DeviceNaming.groups(props)
        #expect(groups.count == 2)
        #expect(groups.allSatisfy { !$0.isComposite })
        #expect(groups.map(\.key) == ["temperature", "humidity"])
    }

    @Test("多服务按 siid 升序，单成员各自成卡")
    func groupOrdering() {
        let props = [
            prop("b", desc: "B / 乙", siid: 5, piid: 2),
            prop("a", desc: "A / 甲", siid: 5, piid: 1),
            prop("c", desc: "C / 丙", siid: 2, piid: 1),
        ]
        let groups = DeviceNaming.groups(props)
        #expect(groups.map(\.key) == ["c", "a", "b"])
        #expect(groups.allSatisfy { !$0.isComposite })
        #expect(groups.map { $0.members.map(\.piid) } == [[1], [1], [2]])
    }

    @Test("master 优先级：on → on/switch 前缀 → 首个可写 bool → 首个可写")
    func masterPriority() {
        let on = prop("on", siid: 1, piid: 7)
        let others = prop("fan-level", type: "int", siid: 1, piid: 8)
        #expect(DeviceNaming.pickMaster([others, on])?.name == "on")

        let switchProp = prop("switch-status", siid: 1, piid: 2)
        let intProp = prop("level", type: "int", siid: 1, piid: 1)
        #expect(DeviceNaming.pickMaster([intProp, switchProp])?.name == "switch-status")

        let boolOnly = prop("mute", siid: 1, piid: 4)
        #expect(DeviceNaming.pickMaster([intProp, boolOnly])?.name == "mute")

        #expect(DeviceNaming.pickMaster([prop("ro", rw: "r", siid: 1, piid: 1), intProp])?.name == "level")
        #expect(DeviceNaming.pickMaster([prop("ro", rw: "r", siid: 1, piid: 1)]) == nil)
    }

    // MARK: - 默认模块

    @Test("默认 = 主开关 + 核心控制（不再整服务合成一张卡）")
    func defaultKeyStandaloneOn() {
        let props = [
            prop("on", desc: "Switch / 开关", siid: 2, piid: 1),
            prop("brightness", desc: "Brightness / 亮度", type: "int", siid: 2, piid: 2),
            prop("mode", desc: "Mode / 模式", type: "uint", siid: 3, piid: 1),
        ]
        #expect(DeviceNaming.defaultKeys(props: props, actions: []) == ["on", "mode", "brightness"])
    }

    @Test("只有开关和模式时，两者都进默认布局")
    func defaultKeyIsolatedOn() {
        let props = [
            prop("on", desc: "Switch / 开关", siid: 2, piid: 1),
            prop("mode", desc: "Mode / 模式", type: "uint", siid: 3, piid: 1),
        ]
        #expect(DeviceNaming.defaultKeys(props: props, actions: []) == ["on", "mode"])
    }

    @Test("没有开关时按核心关键字挑选；带「电源」标题的 bool 仍能识别")
    func defaultKeyFallbacks() {
        let core = [
            prop("level", desc: "Level / 档位", type: "int", siid: 2, piid: 1),
            prop("speed", desc: "Speed / 风速", type: "int", siid: 2, piid: 2),
        ]
        // 关键字顺序 speed 在 level 之前
        #expect(DeviceNaming.defaultKeys(props: core, actions: []) == ["speed", "level"])

        let titled = [prop("power", desc: "Power / 电源开关", type: "bool", siid: 4, piid: 1)]
        #expect(DeviceNaming.defaultKeys(props: titled, actions: []) == ["power"])
    }

    @Test("完全没有属性时退到第一个动作；都没有则返回空")
    func defaultKeyEmpty() {
        let action = DevAction(name: "play-text", desc: "Play Text / 播放文本", siid: 2, aiid: 1)
        #expect(DeviceNaming.defaultKeys(props: [], actions: [action]) == ["action:2.1"])
        #expect(DeviceNaming.defaultKeys(props: [], actions: []) == [])
    }

    @Test("没有开关类属性时，摆 2 个可读状态 + 1 个动作（微波炉）")
    func defaultKeyReadableWithAction() {
        let props = [
            prop("left-time", desc: "Left Time / 剩余时间", type: "uint", rw: "r", siid: 2, piid: 1),
            prop("status", desc: "Status / 状态", type: "uint", rw: "r", siid: 2, piid: 2),
            prop("heat-level", desc: "Heat Level / 火力", type: "uint", rw: "r", siid: 2, piid: 3),
        ]
        let action = DevAction(name: "start-cook", desc: "Start Cook / 开始烹饪", siid: 2, aiid: 2)
        let keys = DeviceNaming.defaultKeys(props: props, actions: [action])
        #expect(keys == ["left-time", "status", "action:2.2"])
    }

    @Test("纯传感器没有动作时摆最多 3 个可读属性")
    func defaultKeyReadableOnly() {
        let props = (1...5).map {
            prop("p\($0)", type: "float", rw: "r", siid: $0, piid: 1)
        }
        #expect(DeviceNaming.defaultKeys(props: props, actions: [])
                == ["p1", "p2", "p3"])
    }

    @Test("on 系列命名识别与动作 key")
    func keys() {
        #expect(DeviceNaming.isOnName("on"))
        #expect(DeviceNaming.isOnName("on-2-1"))
        #expect(!DeviceNaming.isOnName("online"))
        #expect(!DeviceNaming.isOnName("button"))
        #expect(DeviceNaming.actionKey(DevAction(name: "toggle", desc: "Toggle / 翻转", siid: 2, aiid: 1)) == "action:2.1")
        #expect(DeviceNaming.needsText("execute-text-directive"))
        #expect(!DeviceNaming.needsText("toggle"))
    }

    // MARK: - 小爱音箱型号

    @Test("空调/净化器等 air* 型号不会被误判为音箱")
    func speakerModelRejectsAirDevices() {
        #expect(!DeviceNaming.isSpeakerModel("xiaomi.airc.r24r00"))
        #expect(!DeviceNaming.isSpeakerModel("xiaomi.airp.va4"))
        #expect(!DeviceNaming.isSpeakerModel("xiaomi.airfresh.va2"))
        #expect(!DeviceNaming.isSpeakerModel("xiaomi.airer.jns1"))
        #expect(!DeviceNaming.isSpeakerModel("xiaomi.tv.rmh1"))
    }

    @Test("常见小爱音箱型号能被识别（大小写不敏感）")
    func speakerModelAcceptsSpeakers() {
        #expect(DeviceNaming.isSpeakerModel("xiaomi.wifispeaker.s12"))
        #expect(DeviceNaming.isSpeakerModel("xiaomi.wifispeaker.lx04"))
        #expect(DeviceNaming.isSpeakerModel("xiaomi.speaker.lx01"))
        #expect(DeviceNaming.isSpeakerModel("xiaomi.ai.speaker.lx06"))
        #expect(DeviceNaming.isSpeakerModel("Xiaomi.WifiSpeaker.S12"))
    }
}
