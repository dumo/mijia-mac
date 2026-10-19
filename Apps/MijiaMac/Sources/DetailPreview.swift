import Foundation
import MijiaCore

/// 调试预览数据：`MIJIA_SHOW_DETAIL=1` 时用它把详情页渲染出来，
/// 全程不触网、不下发任何指令，只用来检查布局与文案。
enum DetailPreview {

    static let specType = "urn:miot-spec-v2:device:light:0000A001:preview:1"

    static func makeDevice(online: Bool = true) -> MiDevice {
        MiDevice(did: "preview-did",
                 name: "书房吸顶灯",
                 model: "yeelink.light.ceiling10",
                 specType: specType,
                 homeId: nil,
                 roomId: nil,
                 roomName: "书房",
                 isOnline: online)
    }

    static func makeSpec() -> DeviceSpec {
        DeviceSpec(
            name: "吸顶灯",
            specType: specType,
            properties: [
                DevProp(name: "on", desc: "Switch Status / 开关状态", type: "bool", rw: "rw",
                        range: nil, valueList: nil, siid: 2, piid: 1),
                DevProp(name: "brightness", desc: "Brightness / 亮度", type: "int", rw: "rw",
                        range: [1, 100, 1], valueList: nil, siid: 2, piid: 2),
                DevProp(name: "color-temperature", desc: "Color Temperature / 色温", type: "int", rw: "rw",
                        range: [2700, 6500, 100], valueList: nil, siid: 2, piid: 3),

                DevProp(name: "mode", desc: "Mode / 场景模式", type: "uint", rw: "rw",
                        range: nil,
                        valueList: [
                            ValueOption(value: 0, desc: "Auto / 自动"),
                            ValueOption(value: 1, desc: "Reading / 阅读"),
                            ValueOption(value: 2, desc: "Night / 夜灯"),
                        ],
                        siid: 3, piid: 1),

                DevProp(name: "temperature", desc: "Temperature / 室内温度", type: "float", rw: "r",
                        range: [-30, 100, 0.1], valueList: nil, siid: 4, piid: 1),
                DevProp(name: "humidity", desc: "Humidity / 室内湿度", type: "float", rw: "r",
                        range: [0, 100, 0.1], valueList: nil, siid: 4, piid: 2),

                DevProp(name: "target-humidity", desc: "Target Humidity / 目标湿度", type: "uint", rw: "rw",
                        range: [40, 70, 5], valueList: nil, siid: 6, piid: 1),
            ],
            actions: [
                DevAction(name: "execute-text-directive", desc: "Execute Text Directive / 执行文本指令",
                          siid: 7, aiid: 1),
                DevAction(name: "toggle", desc: "Toggle / 翻转开关", siid: 7, aiid: 2),
            ])
    }

    static func makeValues() -> [String: JSONValue] {
        ["2.1": .bool(true),
         "2.2": .int(68),
         "2.3": .int(4000),
         "3.1": .int(1),
         "4.1": .double(24.6),
         "4.2": .double(52),
         "6.1": .int(55)]
    }

    /// 预置的工作台模块：组合卡 + 枚举 + 滑块 + 只读 + 文本动作
    static let moduleKeys = [
        "group:2",         // 开关 + 亮度 + 色温
        "mode",            // 枚举菜单
        "target-humidity", // 数值滑块
        "temperature",     // 只读数值
        "action:7.1",      // 带文本输入的动作
    ]
}
