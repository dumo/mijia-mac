import Foundation

/// 业务端点（URI 与 Python 版一一对应）
extension MiCloud {

    // MARK: - 家庭

    public func homes() async throws -> [MiHome] {
        let result = try await call("/v2/homeroom/gethome_merged", [
            "fg": true,
            "fetch_share": true,
            "fetch_share_dev": true,
            "fetch_cariot": true,
            "limit": 300,
            "app_ver": 7,
            "plat_form": 0,
        ])
        let list = result.objectValue?["homelist"]?.arrayValue ?? []
        return list.compactMap { item -> MiHome? in
            guard let obj = item.objectValue,
                  let id = obj["id"]?.stringValue ?? obj["id"]?.intValue.map(String.init) else {
                return nil
            }
            let rooms = (obj["roomlist"]?.arrayValue ?? []).compactMap { r -> MiRoom? in
                guard let ro = r.objectValue,
                      let rid = ro["id"]?.stringValue ?? ro["id"]?.intValue.map(String.init) else {
                    return nil
                }
                let dids = (ro["dids"]?.arrayValue ?? []).compactMap(\.stringValue)
                return MiRoom(id: rid, name: ro["name"]?.stringValue ?? "", deviceIds: dids)
            }
            return MiHome(id: id,
                          name: obj["name"]?.stringValue ?? "未命名家庭",
                          uid: obj["uid"]?.intValue ?? 0,
                          rooms: rooms)
        }
    }

    /// 家庭 owner uid。带缓存，避免逐设备重复拉家庭列表。
    private func homeOwner(_ homeId: String) async throws -> Int {
        if let cached = ownerCache[homeId] { return cached }
        let list = try await homes()
        guard let home = list.first(where: { $0.id == homeId }) else {
            throw MiError.api(code: -1, message: "未找到 home_id=\(homeId) 的家庭")
        }
        ownerCache[homeId] = home.uid
        return home.uid
    }

    // MARK: - 设备

    /// `homeId` 为 nil 时拉取所有家庭的设备。
    public func devices(homeId: String? = nil) async throws -> [MiDevice] {
        ownerCache.removeAll()
        if let homeId {
            return try await devicesInHome(homeId)
        }
        var all: [MiDevice] = []
        for home in try await homes() {
            all.append(contentsOf: try await devicesInHome(home.id))
        }
        return all
    }

    private func devicesInHome(_ homeId: String) async throws -> [MiDevice] {
        let owner = try await homeOwner(homeId)
        guard let homeIdInt = Int(homeId) else {
            throw MiError.api(code: -1, message: "home_id 不是数字: \(homeId)")
        }
        // room_id → room_name；did → 所属房间（设备接口不带 room_id，只能靠 roomlist.dids 反查）
        var roomNames: [String: String] = [:]
        var didToRoom: [String: (id: String, name: String)] = [:]
        let homes = (try? await homes()) ?? []
        for home in homes where home.id == homeId {
            for room in home.rooms {
                roomNames[room.id] = room.name
                for did in room.deviceIds { didToRoom[did] = (room.id, room.name) }
            }
        }

        var result: [MiDevice] = []
        var startDid = ""
        var hasMore = true
        while hasMore {
            let ret = try await call("/home/home_device_list", [
                "home_owner": .int(owner),
                "home_id": .int(homeIdInt),
                "limit": 200,
                "start_did": .string(startDid),
                "get_split_device": true,
                "support_smart_home": true,
                "get_cariot_device": true,
                "get_third_device": true,
            ])
            let obj = ret.objectValue ?? [:]
            let infos = obj["device_info"]?.arrayValue ?? []
            result.append(contentsOf: infos.compactMap {
                Self.parseDevice($0, homeId: homeId, roomNames: roomNames)
            })
            startDid = obj["max_did"]?.stringValue ?? ""
            hasMore = (obj["has_more"]?.boolValue ?? false) && !startDid.isEmpty
        }
        // 用 roomlist 的 did 归属补齐设备的房间信息
        for i in result.indices {
            if let room = didToRoom[result[i].did] {
                result[i].roomId = room.id
                result[i].roomName = room.name
            }
        }
        return result
    }

    static func parseDevice(_ value: JSONValue,
                            homeId: String,
                            roomNames: [String: String]) -> MiDevice? {
        guard let obj = value.objectValue,
              let did = obj["did"]?.stringValue else { return nil }
        let roomId = obj["room_id"]?.stringValue ?? obj["room_id"]?.intValue.map(String.init)
        return MiDevice(
            did: did,
            name: obj["name"]?.stringValue ?? did,
            model: obj["model"]?.stringValue ?? "",
            specType: obj["spec_type"]?.stringValue,
            homeId: homeId,
            roomId: roomId,
            roomName: roomId.flatMap { roomNames[$0] } ?? obj["room_name"]?.stringValue,
            isOnline: obj["is_online"]?.boolValue
                   ?? obj["online"]?.boolValue
                   ?? obj["isOnline"]?.boolValue
                   ?? false,
            raw: obj)
    }

    // MARK: - 属性读写 / 动作

    /// `params` 每项形如 `["did": "...", "siid": 2, "piid": 1]`
    public func getProps(_ params: [MiPayload]) async throws -> [JSONValue] {
        let result = try await call("/miotspec/prop/get", [
            "params": .array(params.map { .object($0) }),
            "datasource": 1,
        ])
        return result.arrayValue ?? []
    }

    public func getProp(_ param: MiPayload) async throws -> JSONValue? {
        try await getProps([param]).first
    }

    /// `params` 每项形如 `["did": "...", "siid": 2, "piid": 1, "value": 60]`
    public func setProps(_ params: [MiPayload]) async throws -> [JSONValue] {
        let result = try await call("/miotspec/prop/set", [
            "params": .array(params.map { .object($0) }),
        ])
        return result.arrayValue ?? []
    }

    /// `param` 形如 `["did": "...", "siid": 2, "aiid": 1, "value": [2]]`
    public func runAction(_ param: MiPayload) async throws -> JSONValue {
        try await call("/miotspec/action", ["params": .object(param)])
    }

    // MARK: - 场景

    public func scenes(homeId: String? = nil) async throws -> [MiScene] {
        if let homeId {
            return try await scenesInHome(homeId)
        }
        var all: [MiScene] = []
        for home in try await homes() {
            all.append(contentsOf: try await scenesInHome(home.id))
        }
        return all
    }

    private func scenesInHome(_ homeId: String) async throws -> [MiScene] {
        let owner = try await homeOwner(homeId)
        let ret = try await call(
            "/appgateway/miot/appsceneservice/AppSceneService/GetSimpleSceneList", [
                "app_version": 12,
                "get_type": 2,
                "home_id": .string(homeId),
                "owner_uid": .int(owner),
            ])
        let list = ret.objectValue?["manual_scene_info_list"]?.arrayValue ?? []
        return list.compactMap { item in
            guard let obj = item.objectValue,
                  let sid = obj["scene_id"]?.stringValue else { return nil }
            return MiScene(sceneId: sid,
                           name: obj["name"]?.stringValue ?? "",
                           homeId: homeId)
        }
    }

    public func runScene(sceneId: String, homeId: String) async throws -> Bool {
        let owner = try await homeOwner(homeId)
        let ret = try await call(
            "/appgateway/miot/appsceneservice/AppSceneService/NewRunScene", [
                "scene_id": .string(sceneId),
                "scene_type": 2,
                "phone_id": "null",
                "home_id": .string(homeId),
                "owner_uid": .int(owner),
            ])
        return ret.objectValue?["result"]?.boolValue ?? true
    }

    // MARK: - 耗材

    public func consumables(homeId: String? = nil) async throws -> [MiConsumable] {
        if let homeId { return try await consumablesInHome(homeId) }
        var all: [MiConsumable] = []
        for home in try await homes() {
            all.append(contentsOf: try await consumablesInHome(home.id))
        }
        return all
    }

    private func consumablesInHome(_ homeId: String) async throws -> [MiConsumable] {
        let owner = try await homeOwner(homeId)
        guard let hid = Int(homeId) else { return [] }
        let ret = try await call("/v2/home/standard_consumable_items", [
            "home_id": .int(hid),
            "owner_id": .int(owner),
            "filter_ignore": true,
        ])
        let items = ret.objectValue?["items"]?.arrayValue?.first?.objectValue?["consumes_data"]?.arrayValue ?? []
        return items.compactMap { item -> MiConsumable? in
            guard let obj = item.objectValue,
                  let id = obj["id"]?.stringValue ?? obj["id"]?.intValue.map(String.init) else {
                return nil
            }
            let detail = obj["details"]?.objectValue
                      ?? obj["details"]?.arrayValue?.first?.objectValue
            return MiConsumable(id: id,
                                deviceId: obj["did"]?.stringValue ?? "",
                                deviceName: obj["name"]?.stringValue ?? "",
                                homeId: homeId,
                                desc: detail?["description"]?.stringValue ?? "",
                                value: detail?["value"]?.stringValue ?? "",
                                type: detail?["consumable_type"]?.stringValue ?? "")
        }
    }

    // MARK: - 统计

    /// 例：`["did": "...", "key": "7.1", "data_type": "stat_month_v3", "limit": 6, ...]`
    /// 注意：支持统计的设备有限，失败属正常，调用方应降级处理。
    public func statistics(_ param: MiPayload) async throws -> JSONValue {
        try await call("/v2/user/statistics", param)
    }
}
