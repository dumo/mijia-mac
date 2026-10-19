import Foundation

// MARK: - 认证数据

/// 与 Python 版 `auth.json` **键名完全兼容**，可以直接复用已有的
/// `~/.config/mijia-api/auth.json` 做对拍，不用重复扫码。
public struct AuthData: Codable, Sendable, Equatable {
    /// 全部原始键值（含服务端下发的 cookie），未知键也不会丢。
    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    public subscript(_ key: String) -> String? {
        get { values[key] }
        set { values[key] = newValue }
    }

    public var userAgent: String? { self["ua"] }
    public var deviceId: String? { self["deviceId"] }
    public var passO: String? { self["pass_o"] }
    public var ssecurity: String? { self["ssecurity"] }
    public var userId: String? { self["userId"] }
    public var cUserId: String? { self["cUserId"] }
    public var serviceToken: String? { self["serviceToken"] }
    public var passToken: String? { self["passToken"] }
    public var expireTime: Int64? { self["expireTime"].flatMap { Int64($0) } }

    /// 关键字段是否齐备（对应 Python `available` 的前置判断）
    public var isComplete: Bool {
        ["ua", "ssecurity", "userId", "cUserId", "serviceToken"].allSatisfy {
            !(values[$0] ?? "").isEmpty
        }
    }
}

// MARK: - 家庭 / 房间

public struct MiRoom: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    /// 房间内的设备 did 列表。设备列表接口不返回 room_id，
    /// 房间归属只能从 gethome_rooms_merged 的 roomlist[].dids 里拿。
    public var deviceIds: [String] = []
}

public struct MiHome: Identifiable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var uid: Int
    public var rooms: [MiRoom]

    public init(id: String, name: String, uid: Int, rooms: [MiRoom] = []) {
        self.id = id
        self.name = name
        self.uid = uid
        self.rooms = rooms
    }
}

// MARK: - 设备

public struct MiDevice: Identifiable, Sendable, Hashable {
    public var id: String { did }
    public var did: String
    public var name: String
    public var model: String
    /// v5.0 起设备规格靠这个 URN 拉取；老设备可能没有，需要 model 兜底。
    public var specType: String?
    public var homeId: String?
    public var roomId: String?
    public var roomName: String?
    public var isOnline: Bool
    public var raw: [String: JSONValue]

    public init(did: String,
                name: String,
                model: String,
                specType: String? = nil,
                homeId: String? = nil,
                roomId: String? = nil,
                roomName: String? = nil,
                isOnline: Bool = false,
                raw: [String: JSONValue] = [:]) {
        self.did = did
        self.name = name
        self.model = model
        self.specType = specType
        self.homeId = homeId
        self.roomId = roomId
        self.roomName = roomName
        self.isOnline = isOnline
        self.raw = raw
    }
}

// MARK: - 场景

public struct MiScene: Identifiable, Sendable, Hashable {
    public var id: String { sceneId }
    public var sceneId: String
    public var name: String
    public var homeId: String
}

// MARK: - 耗材

public struct MiConsumable: Identifiable, Sendable, Hashable {
    public var id: String
    public var deviceId: String
    public var deviceName: String
    public var homeId: String
    public var desc: String
    public var value: String
    public var type: String
}

// MARK: - 设备规格（miot-spec.org）

public struct ValueOption: Codable, Sendable, Hashable {
    public var value: JSONValue
    public var desc: String

    public init(value: JSONValue, desc: String) {
        self.value = value
        self.desc = desc
    }
}

public struct DevProp: Identifiable, Sendable, Hashable, Codable {
    public var id: String { "\(siid).\(piid)" }
    public var name: String
    public var desc: String
    public var type: String          // bool / int / uint / float / string
    public var rw: String            // r / w / rw
    public var range: [Double]?      // [min, max, step]
    public var valueList: [ValueOption]?
    public var siid: Int
    public var piid: Int

    public init(name: String,
                desc: String,
                type: String,
                rw: String,
                range: [Double]? = nil,
                valueList: [ValueOption]? = nil,
                siid: Int,
                piid: Int) {
        self.name = name
        self.desc = desc
        self.type = type
        self.rw = rw
        self.range = range
        self.valueList = valueList
        self.siid = siid
        self.piid = piid
    }

    public var isReadable: Bool { rw.contains("r") }
    public var isWritable: Bool { rw.contains("w") }
}

public struct DevAction: Identifiable, Sendable, Hashable, Codable {
    public var id: String { "\(siid).\(aiid)" }
    public var name: String
    public var desc: String
    public var siid: Int
    public var aiid: Int

    public init(name: String, desc: String, siid: Int, aiid: Int) {
        self.name = name
        self.desc = desc
        self.siid = siid
        self.aiid = aiid
    }
}

public struct DeviceSpec: Sendable, Hashable, Codable {
    public var name: String
    public var specType: String
    public var properties: [DevProp]
    public var actions: [DevAction]

    public init(name: String, specType: String, properties: [DevProp], actions: [DevAction]) {
        self.name = name
        self.specType = specType
        self.properties = properties
        self.actions = actions
    }

    public static var empty: DeviceSpec {
        DeviceSpec(name: "", specType: "", properties: [], actions: [])
    }
}
