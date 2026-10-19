import AppKit
import MijiaCore

enum DeviceIcon {
    /// 按 model / spec_type 关键字猜 SF Symbol。
    ///
    /// ⚠️ `Image(systemName:)` 遇到不存在的符号名会**静默画成空白**，
    /// 所以这里必须逐个校验候选符号是否存在，再落到通用图标。
    static func systemName(for device: MiDevice) -> String {
        let model = device.model.lowercased()
        let specType = device.specType?.lowercased() ?? ""

        func has(_ keys: [String]) -> Bool {
            keys.contains { model.contains($0) || specType.contains($0) }
        }

        if has(["light", "lamp", "bhf_light", "ceiling"]) {
            return pick(["lightbulb.fill", "lightbulb"]) 
        }
        if has(["camera", "ipc", "chuangmi"]) {
            return pick(["video.fill", "video"])
        }
        if has(["router", "miwifi", "ra81"]) {
            return pick(["wifi", "wifi.router"])
        }
        if has(["waterheater", "water-heater"]) {
            return pick(["drop.fill", "drop"])
        }
        if has(["airc", "air-conditioner", "aircondition"]) {
            return pick(["wind", "air.conditioner.horizontal", "fan"])
        }
        if has(["dishwasher"]) {
            return pick(["dishwasher.fill", "dishwasher", "square.grid.3x3.fill"])
        }
        if has(["microwave"]) {
            return pick(["oven.fill", "oven", "square.grid.3x3.fill"])
        }
        if has(["curtain"]) {
            return pick(["rectangle.and.hand.point.up.left.fill", "rectangle.split.3x1"])
        }
        if has(["lock"]) {
            return pick(["lock.fill", "lock"])
        }
        if has(["sensor", "magnet", "ht"]) {
            return pick(["sensor.fill", "thermometer.medium", "gauge.with.dots.needle.bottom.50percent"])
        }
        if has(["remote", "switch", "akswr"]) {
            return pick(["switch.2", "square.grid.2x2"])
        }
        if has(["speaker", "xiaoai"]) {
            return pick(["hifispeaker.fill", "hifispeaker"])
        }
        if has(["tv", "television"]) {
            return pick(["tv.fill", "tv"])
        }
        if has(["fan"]) {
            return pick(["fan.floor", "fanblades.fill", "fan"])
        }
        if has(["humidifier"]) {
            return pick(["humidity.fill", "humidity"])
        }
        if has(["purifier"]) {
            return pick(["air.purifier.fill", "air.purifier"])
        }
        if has(["socket", "plug", "outlet"]) {
            return pick(["poweroutlet.type.b.fill", "powerplug.fill", "bolt.fill"])
        }
        if has(["bracelet", "watch"]) {
            return pick(["watch.fill", "applewatch"])
        }
        if has(["vacuum", "cleaner"]) {
            return pick(["arrow.counterclockwise.circle.fill", "circle.dashed"])
        }
        if has(["bath-heater", "bathroom"]) {
            return pick(["shower.fill", "shower", "humidity.fill"])
        }
        return generic
    }

    private static let generic = pick(["square.grid.2x2.fill", "square.grid.2x2"])

    /// 返回第一个系统里真实存在的符号
    private static func pick(_ candidates: [String]) -> String {
        for name in candidates where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return "questionmark.square.dashed"
    }
}
