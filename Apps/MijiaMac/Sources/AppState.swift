import Foundation
import SwiftUI
import MijiaCore

/// App 的根状态机。MiCloud 是 actor，所有对它的调用都在这里 await 后落到主线程。
@MainActor
@Observable
final class AppState {

    /// 菜单栏与主窗口共享同一份状态
    static let shared = AppState()

    enum Phase: Equatable {
        case loading
        case needLogin
        case ready
    }

    let cloud: MiCloud

    /// 全局设置（主题 / 开机自启 / 隐藏场景 / 默认音箱 / 版本缓存）
    let settings = SettingsStore()

    var phase: Phase = .loading
    var homes: [MiHome] = []
    var devices: [MiDevice] = []
    /// 登录账号标识（userId / cUserId），仅在已登录时有值
    var accountId: String?
    var errorMessage: String?
    var statusMessage: String?
    /// 设备控制失败（比 statusMessage 更醒目的红色提示）
    var actionError: String?

    /// 登录二维码（登录成功后清空）
    var qrImage: NSImage?
    var qrImageURL: URL?
    var isWaitingForScan = false

    var isLoadingDevices = false

    /// 当前选中的家庭（侧边栏选中项），场景列表据此过滤
    var currentHomeId: String?
    /// 当前家庭的场景（手动场景，可一键执行）
    var scenes: [MiScene] = []
    var isLoadingScenes = false

    /// specType → 规格，进程内缓存（规格基本不变）
    private var specCache: [String: DeviceSpec] = [:]
    /// did → 开关属性（siid.piid），供菜单栏快速开关用
    private var switchCache: [String: DevProp] = [:]
    /// did → 当前开关状态
    var switchState: [String: Bool] = [:]
    /// 已拿到过真实开关值的 did：用于区分「未知/加载中」与「真的关」
    var switchLoaded: Set<String> = []
    /// 已确认没有可写开关属性的 did（传感器等）：直接显示状态点，不再转圈
    var switchUnavailable: Set<String> = []
    /// 正在请求中的 did：避免网格逐卡加载与批量加载并发发重复请求
    private var switchFetching: Set<String> = []
    /// 正在下发指令的设备
    var pendingDevices: Set<String> = []
    /// 刷新节流阈值（秒）：打开主窗口 / 菜单栏时，距上次刷新超过该值才真正发请求
    static let refreshInterval: TimeInterval = 30
    /// 只读传感器（温湿度计、门窗/人体/空气质量等）：有读数、无控制能力，
    /// 离线时不应当作「可控制设备离线」处理。
    var sensorDids: Set<String> = []
    /// did → 传感器最近一次温湿度读数（卡片上直接展示）
    var sensorReadings: [String: ClimateReading] = [:]
    private var sensorReadingFetchedAt: [String: Date] = [:]
    private var sensorClassificationInFlight = false

    // MARK: - 菜单栏温湿度

    struct ClimateReading: Equatable {
        var temperature: Double?
        var humidity: Double?
        var isEmpty: Bool { temperature == nil && humidity == nil }
    }

    /// 菜单栏当前展示的温湿度读数
    var menuBarClimate: ClimateReading?
    /// 可提供温湿度读数的设备（按 spec 里是否存在只读的 temperature / humidity 属性筛选）
    var climateCandidates: [MiDevice] = []
    var isLoadingClimateCandidates = false
    private var climateTask: Task<Void, Never>?

    // MARK: - 工作台（详情页）

    /// 每个设备已添加的模块 key 与顺序，落盘在 Application Support
    private var workbench = WorkbenchStore()
    /// 写后乐观值：刚下发过的属性在静默期内不接受云端旧值回填
    private var writeGuard = WriteGuard()
    /// did → (prop.id → 当前值)
    var propValues: [String: [String: JSONValue]] = [:]
    /// 正在下发的属性，key 形如 `did|siid.piid`
    var pendingProps: Set<String> = []

    init(authFile: URL? = nil) {
        self.cloud = MiCloud(authFile: authFile)
    }

    // MARK: - 启动

    func bootstrap() async {
        phase = .loading
        if await cloud.isLoggedIn {
            do {
                try await cloud.refreshToken()
                accountId = await cloud.accountIdentity()
                await loadDevices()
                phase = .ready
                restartMenuBarClimateUpdates()
                return
            } catch {
                statusMessage = "登录态已失效：\(error.localizedDescription)"
            }
        }
        await startLogin()
    }

    // MARK: - 登录

    func startLogin() async {
        phase = .needLogin
        isWaitingForScan = true
        errorMessage = nil
        do {
            guard let ticket = try await cloud.fetchQRTicket() else {
                // token 仍然有效，直接进主界面
                isWaitingForScan = false
                await loadDevices()
                markDevicesRefreshed()
                phase = .ready
                Task { await refreshIfNeeded() }
                return
            }

            if let data = QRCode.pngData(ticket.loginURL, modulePixels: 10) {
                qrImage = NSImage(data: data)
            }
            if let url = URL(string: ticket.imageURL), !ticket.imageURL.isEmpty {
                qrImageURL = url
            }

            try await cloud.completeLogin(lp: ticket.longPollingURL)
            qrImage = nil
            qrImageURL = nil
            isWaitingForScan = false
            accountId = await cloud.accountIdentity()
            await loadDevices()
            markDevicesRefreshed()
            phase = .ready
            Task { await refreshIfNeeded() }
            restartMenuBarClimateUpdates()
        } catch {
            isWaitingForScan = false
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 退出登录 / 切换账号

    /// 米家没有云端注销接口，本机清掉凭据即等价于退出，随后重新出二维码。
    func logout() async {
        do { try await cloud.logout() } catch {
            errorMessage = "清除凭据失败：\(error.localizedDescription)"
        }
        accountId = nil
        homes = []
        devices = []
        scenes = []
        switchState = [:]
        switchLoaded = []
        switchUnavailable = []
        switchFetching = []
        switchCache = [:]
        sensorDids = []
        sensorReadings = [:]
        sensorReadingFetchedAt = [:]
        specCache = [:]
        propValues = [:]
        actionError = nil
        statusMessage = nil
        qrImage = nil
        qrImageURL = nil
        climateTask?.cancel()
        climateTask = nil
        menuBarClimate = nil
        climateCandidates = []
        await startLogin()
    }

    // MARK: - 设备

    func loadDevices() async {
        isLoadingDevices = true
        defer { isLoadingDevices = false }
        do {
            homes = try await cloud.homes()
            devices = try await cloud.devices()
            applyStableOrder()
            errorMessage = nil
            // 只读传感器：先用 model 关键字即时判定（避免卡片闪烁），
            // 再按 spec 精修（覆盖无关键字、但确实没有写入属性/动作的纯只读设备）
            sensorDids = Set(devices.filter { Self.modelIsSensor($0.model) }.map(\.did))
            settings.lastDevicesRefreshAt = Date()
            settings.save()
            Task { await refineSensorClassification() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 场景

    /// 拉取指定家庭（默认当前选中家庭）的手动场景。
    func loadScenes(homeId: String? = nil) async {
        // 未选家庭时回落到第一个家庭（场景 Tab 初始状态也能出内容）
        let target = homeId ?? currentHomeId ?? homes.first?.id
        guard let target else {
            scenes = []
            return
        }
        isLoadingScenes = true
        defer { isLoadingScenes = false }
        do {
            scenes = try await cloud.scenes(homeId: target)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 一键执行场景；返回是否成功。
    @discardableResult
    func runScene(_ scene: MiScene) async -> Bool {
        let home = scene.homeId.isEmpty ? (currentHomeId ?? "") : scene.homeId
        guard !home.isEmpty else {
            actionError = "无法确认场景所属家庭"
            return false
        }
        do {
            let ok = try await cloud.runScene(sceneId: scene.sceneId, homeId: home)
            if ok {
                statusMessage = "已执行场景「\(scene.name)」"
                actionError = nil
            } else {
                actionError = "场景「\(scene.name)」执行失败"
            }
            return ok
        } catch {
            actionError = "场景「\(scene.name)」执行失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 只读传感器识别

    /// 设备名里常见的传感器关键字（与 `DeviceIcon` 的 sensor 分支对齐），
    /// 用于 `loadDevices` 里即时预判，避免界面闪烁。
    private static let sensorModelKeywords = [
        "sensor", "magnet", "thermometer", "humidity", "bracelet", "watch", "band", "scale",
    ]

    /// 按 model 关键字预判是否为传感器。
    /// 注意 `ht` 只能作为独立 token 匹配（如 `sensor_ht`、`abc.ht.def`），
    /// 否则会误伤 `light` 等包含 "ht" 子串的可控设备。
    private static func modelIsSensor(_ model: String) -> Bool {
        let lower = model.lowercased()
        if sensorModelKeywords.contains(where: { lower.contains($0) }) { return true }
        let tokens = lower.components(separatedBy: CharacterSet(charactersIn: "._-"))
            .filter { !$0.isEmpty }
        return tokens.contains("ht")
    }

    func isReadOnlySensor(_ device: MiDevice) -> Bool {
        sensorDids.contains(device.did)
    }

    /// 按规格精修只读传感器的判定：spec 里没有任何可写属性、也没有动作，
    /// 即为只读传感器。会覆盖 model 关键字误判的可控设备，也会补上无关键字的纯只读设备。
    func refineSensorClassification() async {
        guard !sensorClassificationInFlight else { return }
        sensorClassificationInFlight = true
        defer { sensorClassificationInFlight = false }

        var result = sensorDids
        for device in devices {
            guard let spec = await spec(for: device) else { continue }
            let hasControl = spec.properties.contains { $0.isWritable }
                || !spec.actions.isEmpty
            if hasControl {
                result.remove(device.did)
            } else {
                result.insert(device.did)
            }
        }
        sensorDids = result
    }

    /// 读取一次只读传感器的温湿度（60 秒内不重复请求），供卡片直接展示读数。
    func refreshSensorReading(for device: MiDevice) async {
        guard isReadOnlySensor(device) else { return }
        if let last = sensorReadingFetchedAt[device.did],
           sensorReadings[device.did] != nil,
           Date().timeIntervalSince(last) < 60 {
            return
        }
        guard let spec = await spec(for: device) else { return }

        let props = climateProps(in: spec)
        let targets = [props.temperature, props.humidity].compactMap { $0 }
        guard !targets.isEmpty else { return }

        let params: [MiPayload] = targets.map {
            ["did": .string(device.did), "siid": .int($0.siid), "piid": .int($0.piid)]
        }
        do {
            let results = try await cloud.getProps(params)
            var reading = ClimateReading()
            // 批量返回乱序，按 did+siid+piid 归位
            let values = PropResponses.values(from: results)
            for target in targets {
                guard let value = values[PropResponses.Key(did: device.did, prop: target)]?.doubleValue
                else { continue }
                if target.id == props.temperature?.id {
                    reading.temperature = value
                } else {
                    reading.humidity = value
                }
            }
            if !reading.isEmpty {
                sensorReadings[device.did] = reading
                sensorReadingFetchedAt[device.did] = Date()
            }
        } catch {
            // 只读传感器读数失败不打扰用户，保留上一次的值
        }
    }

    // MARK: - 规格

    func spec(for device: MiDevice) async -> DeviceSpec? {
        guard let specType = device.specType, !specType.isEmpty else { return nil }
        if let cached = specCache[specType] { return cached }
        do {
            let spec = try await MiotSpecStore().spec(forType: specType)
            specCache[specType] = spec
            return spec
        } catch {
            return nil
        }
    }

    /// 一个设备可能有多个 bool 可写属性，优先取语义明确的开关
    func primarySwitch(for device: MiDevice) async -> DevProp? {
        if let cached = switchCache[device.did] { return cached }
        guard let spec = await spec(for: device) else { return nil }
        let prop = spec.properties.first { $0.name == "on" && $0.isWritable }
            ?? spec.properties.first { $0.name == "switch" && $0.isWritable }
            ?? spec.properties.first { $0.type == "bool" && $0.isWritable }
        if let prop { switchCache[device.did] = prop }
        return prop
    }

    // MARK: - 状态刷新与控制

    /// 批量拉取一批设备的开关状态（一次请求，避免 N 次往返）。
    ///
    /// - Parameter force: `true` 表示忽略「已加载」跳过逻辑（节流判定已决定要刷新时用）。
    ///   单个设备返回 `code != 0` 时**保留上一次真值**，绝不回退成 `false`。
    func refreshSwitchState(for devices: [MiDevice], force: Bool = false) async {
        var targets: [(MiDevice, DevProp)] = []
        for device in devices {
            if !force,
               switchLoaded.contains(device.did)
                || switchUnavailable.contains(device.did)
                || switchFetching.contains(device.did) {
                continue
            }
            if let prop = await primarySwitch(for: device) {
                targets.append((device, prop))
            } else {
                // 确认没有可写开关属性（传感器等），标记后不再反复尝试
                switchUnavailable.insert(device.did)
            }
        }
        guard !targets.isEmpty else { return }

        // results 与 params 按下标一一对应，取 did 时同样按 targets 下标，避免隐式错位
        let dids = targets.map(\.0.did)
        switchFetching.formUnion(dids)
        defer { switchFetching.subtract(dids) }
        let params: [MiPayload] = targets.map { device, prop in
            ["did": .string(device.did), "siid": .int(prop.siid), "piid": .int(prop.piid)]
        }
        do {
            let results = try await cloud.getProps(params)
            // 批量返回是乱序的（实测 11 条里 10 条错位），必须按 did+siid+piid 归位
            let values = PropResponses.values(from: results)
            for (device, prop) in targets {
                guard let value = values[PropResponses.Key(did: device.did, prop: prop)]?.boolValue
                else { continue }
                switchState[device.did] = value
                switchLoaded.insert(device.did)
                switchUnavailable.remove(device.did)
            }
            settings.lastSwitchRefreshAt = Date()
            settings.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// 打开主窗口 / 菜单栏时调用：距上次刷新超过阈值才真正请求，否则复用缓存。
    /// - Parameter force: 手动点「刷新」时传 `true`，忽略阈值直接刷新。
    func refreshIfNeeded(force: Bool = false) async {
        guard phase == .ready else { return }
        let now = Date()

        let devicesStale = force || isStale(since: settings.lastDevicesRefreshAt, now: now)
        if devicesStale {
            await loadDevices()
            settings.lastDevicesRefreshAt = Date()
            settings.save()
        }

        if !settings.hideScenes, scenes.isEmpty, let home = homes.first {
            await loadScenes(homeId: home.id)
        }

        // 设备列表刚刷新过也要顺带重取开关，否则在线状态变了、开关还是旧值
        let switchStale = force || devicesStale || isStale(since: settings.lastSwitchRefreshAt, now: now)
        if switchStale {
            await refreshSwitchState(for: trayDevices(), force: true)
        }
    }

    private func isStale(since date: Date?, now: Date) -> Bool {
        RefreshPolicy.shouldRefresh(last: date, now: now, interval: Self.refreshInterval)
    }

    /// 记一次设备列表刷新时间（bootstrap / 登录后已显式拉过列表时用）
    private func markDevicesRefreshed() {
        settings.lastDevicesRefreshAt = Date()
        settings.save()
    }

    func toggle(_ device: MiDevice, to newValue: Bool) async {
        // 离线设备服务端必然返回 -704042011，与其等一个往返不如直接说清楚
        guard device.isOnline else {
            actionError = "「\(device.name)」当前离线，无法接收指令"
            return
        }
        guard let prop = await primarySwitch(for: device) else {
            actionError = "「\(device.name)」没有可用的开关属性"
            return
        }
        pendingDevices.insert(device.did)
        defer { pendingDevices.remove(device.did) }

        do {
            let results = try await cloud.setProps([
                ["did": .string(device.did),
                 "siid": .int(prop.siid),
                 "piid": .int(prop.piid),
                 "value": .bool(newValue)]
            ])
            if let first = results.first?.objectValue, first["code"]?.intValue == 0 {
                switchState[device.did] = newValue
                switchLoaded.insert(device.did)
                actionError = nil
            } else {
                let code = results.first?.objectValue?["code"]?.intValue ?? -1
                actionError = "「\(device.name)」下发失败：\(MiErrorCode.describe(code))"
            }
        } catch {
            actionError = "「\(device.name)」下发失败：\(error.localizedDescription)"
        }
    }

    /// 通用属性下发（供详情页的控件使用）
    @discardableResult
    func setProp(_ device: MiDevice, _ prop: DevProp, value: JSONValue) async -> Bool {
        guard device.isOnline else {
            actionError = "「\(device.name)」当前离线，无法接收指令"
            return false
        }
        do {
            let results = try await cloud.setProps([
                ["did": .string(device.did),
                 "siid": .int(prop.siid),
                 "piid": .int(prop.piid),
                 "value": value]
            ])
            let code = results.first?.objectValue?["code"]?.intValue ?? -1
            guard code == 0 else {
                actionError = "「\(device.name)」设置失败：\(MiErrorCode.describe(code))"
                return false
            }
            actionError = nil
            return true
        } catch {
            actionError = "「\(device.name)」设置失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 工作台：模块增删与排序

    /// 该设备要展示的模块 key。首次进入会用 `DeviceNaming.defaultKeys` 铺一个开关卡并落盘。
    ///
    /// 载入时会剔除当前 spec 已无法解析的旧 key（例如分组策略从「按 siid 服务」改为
    /// 「按属性名前缀」后，旧的 `group:{siid}` 组合卡 key 即失效），避免详情页出现空白/报错卡；
    /// 裁剪后若为空，则回退到新的 `defaultKeys` 重新落盘。
    func workbenchKeys(for device: MiDevice, spec: DeviceSpec) -> [String] {
        let stored = workbench.keys(for: device.did,
                                    defaultingTo: DeviceNaming.defaultKeys(props: spec.properties,
                                                                           actions: spec.actions))
        let resolver = WorkbenchResolver(spec: spec)
        let valid = stored.filter { resolver.module(for: $0) != nil }
        if valid.isEmpty {
            let fallback = DeviceNaming.defaultKeys(props: spec.properties, actions: spec.actions)
            workbench.setKeys(fallback, for: device.did)
            return fallback
        }
        if valid.count != stored.count {
            workbench.setKeys(valid, for: device.did)
        }
        return valid
    }

    func addModule(_ key: String, to device: MiDevice) {
        workbench.add(key, to: device.did)
    }

    func removeModule(_ key: String, from device: MiDevice) {
        workbench.remove(key, from: device.did)
    }

    /// 编辑模式里的拖动排序（fromIndex 处的项移动到 toIndex 处）
    func moveModule(did: String, fromIndex: Int, toIndex: Int) {
        guard fromIndex != toIndex else { return }
        let destination = toIndex > fromIndex ? toIndex + 1 : toIndex
        workbench.move(did: did, fromOffsets: IndexSet(integer: fromIndex), toOffset: destination)
    }

    // MARK: - 工作台：读写属性

    func value(_ prop: DevProp, of device: MiDevice) -> JSONValue? {
        propValues[device.did]?[prop.id]
    }

    func isPending(_ prop: DevProp, of device: MiDevice) -> Bool {
        pendingProps.contains(Self.guardKey(prop, of: device))
    }

    static func guardKey(_ prop: DevProp, of device: MiDevice) -> String {
        "\(device.did)|\(prop.id)"
    }

    /// 批量读取属性（一次请求）。命中写后静默期的属性保持乐观值，不被云端旧值弹回。
    func refreshProps(_ device: MiDevice, _ props: [DevProp]) async {
        let readable = props.filter(\.isReadable)
        guard !readable.isEmpty else { return }
        // 未登录（例如调试预览）时不要发起网络请求
        guard await cloud.isLoggedIn else { return }

        let params: [MiPayload] = readable.map { prop in
            ["did": .string(device.did), "siid": .int(prop.siid), "piid": .int(prop.piid)]
        }
        do {
            let results = try await cloud.getProps(params)
            let now = Date().timeIntervalSince1970
            writeGuard.prune(now: now)
            var merged = propValues[device.did] ?? [:]
            // 批量返回乱序，按 did+siid+piid 归位
            let values = PropResponses.values(from: results)
            for prop in readable {
                guard let value = values[PropResponses.Key(did: device.did, prop: prop)] else { continue }
                if writeGuard.shouldIgnore(Self.guardKey(prop, of: device), incoming: value, now: now) {
                    continue
                }
                merged[prop.id] = value
            }
            propValues[device.did] = merged
        } catch {
            errorMessage = "读取属性失败：\(error.localizedDescription)"
        }
    }

    /// 下发属性。先按乐观值渲染，失败则撤掉守卫让下一次回读恢复真实值。
    @discardableResult
    func writeProp(_ device: MiDevice, _ prop: DevProp, value: JSONValue) async -> Bool {
        guard device.isOnline else {
            actionError = "「\(device.name)」当前离线，无法接收指令"
            return false
        }
        let key = Self.guardKey(prop, of: device)
        pendingProps.insert(key)
        defer { pendingProps.remove(key) }

        propValues[device.did, default: [:]][prop.id] = value
        writeGuard.markWritten(key, value: value, now: Date().timeIntervalSince1970)

        do {
            let results = try await cloud.setProps([
                ["did": .string(device.did),
                 "siid": .int(prop.siid),
                 "piid": .int(prop.piid),
                 "value": value]
            ])
            let code = results.first?.objectValue?["code"]?.intValue ?? -1
            guard code == 0 else {
                writeGuard.clear(key)
                actionError = "「\(device.name)」设置失败：\(MiErrorCode.describe(code))"
                return false
            }
            actionError = nil
            return true
        } catch {
            writeGuard.clear(key)
            actionError = "「\(device.name)」设置失败：\(error.localizedDescription)"
            return false
        }
    }

    /// 执行动作；文本类动作（小爱播放文本等）带一个文本入参。
    @discardableResult
    func runAction(_ device: MiDevice, _ action: DevAction, text: String? = nil) async -> Bool {
        guard device.isOnline else {
            actionError = "「\(device.name)」当前离线，无法接收指令"
            return false
        }
        var param: MiPayload = [
            "did": .string(device.did),
            "siid": .int(action.siid),
            "aiid": .int(action.aiid),
        ]
        if let text, DeviceNaming.needsText(action.name), !text.isEmpty {
            param["in"] = .array([.string(text)])
        }
        do {
            let result = try await cloud.runAction(param)
            let code = result.objectValue?["code"]?.intValue ?? -1
            guard code == 0 else {
                actionError = "「\(device.name)」执行失败：\(MiErrorCode.describe(code))"
                return false
            }
            actionError = nil
            return true
        } catch {
            actionError = "「\(device.name)」执行失败：\(error.localizedDescription)"
            return false
        }
    }

    // MARK: - 调试预览（MIJIA_SHOW_DETAIL=1）

    /// 预置一份规格与属性值，让详情页能脱离网络渲染出来。
    /// 只用于本地看布局/文案，不涉及任何真实设备。
    func installPreview(spec: DeviceSpec, values: [String: JSONValue], for device: MiDevice) {
        specCache[spec.specType] = spec
        propValues[device.did] = values
    }

    func setPreviewWorkbench(_ keys: [String], for device: MiDevice) {
        workbench.setKeys(keys, for: device.did)
    }

    // MARK: - 分组

    func devices(inHome homeId: String?, inRoom roomId: String? = nil) -> [MiDevice] {
        let base: [MiDevice] = homeId.map { hid in
            devices.filter { $0.homeId == hid }
        } ?? devices
        guard let roomId, !roomId.isEmpty else { return base }
        return base.filter { $0.roomId == roomId }
    }

    // MARK: - 稳定顺序

    /// 让 `devices` 遵循持久化的稳定顺序：首次拉取播种，之后只追加新设备、剔除已消失的。
    /// 这样刷新时卡片位置不会因云端返回顺序或在线状态变化而跳动。
    private func applyStableOrder() {
        let merged = DeviceOrdering.merge(existing: settings.deviceOrder,
                                          current: devices.map(\.did))
        settings.deviceOrder = merged
        settings.save()
        devices = DeviceOrdering.sorted(devices, by: merged) { $0.did }
    }

    /// 稳定顺序下的设备列表（主窗口网格 / 菜单栏共用），避免各处各排各的。
    func orderedDevices(inHome homeId: String? = nil, inRoom roomId: String? = nil) -> [MiDevice] {
        devices(inHome: homeId, inRoom: roomId)
    }

    /// 用一整份 did 顺序覆盖当前顺序（原生重排结束后一次落盘）
    func commitDeviceOrder(_ dids: [String]) {
        settings.deviceOrder = dids
        settings.save()
        devices = DeviceOrdering.sorted(devices, by: dids) { $0.did }
    }

    /// 恢复默认顺序：清空自定义顺序并重新拉取，按云端返回顺序重新播种。
    /// 不能直接用当前 `devices`（它已被自定义顺序排过，等于没恢复）。
    func resetDeviceOrder() async {
        settings.deviceOrder = []
        settings.save()
        await loadDevices()
    }

    /// 网格拖拽落位：把 draggedDid 移到 targetDid 所在的位置。
    /// 向下拖（原位置更靠前）落在目标之后，向上拖落在目标之前，符合直觉。
    func moveDevice(_ draggedDid: String, relativeTo targetDid: String) {
        var order = settings.deviceOrder.isEmpty ? devices.map(\.did) : settings.deviceOrder
        guard let from = order.firstIndex(of: draggedDid),
              let targetIndex = order.firstIndex(of: targetDid),
              from != targetIndex else { return }
        let moveDown = from < targetIndex
        order.remove(at: from)
        guard let newTarget = order.firstIndex(of: targetDid) else { return }
        let insertAt = moveDown ? newTarget + 1 : newTarget
        order.insert(draggedDid, at: min(insertAt, order.count))
        settings.deviceOrder = order
        settings.save()
        devices = DeviceOrdering.sorted(devices, by: order) { $0.did }
    }

    /// 当前家庭的房间列表（按原始顺序）
    func rooms(inHome homeId: String?) -> [MiRoom] {
        guard let homeId, let home = homes.first(where: { $0.id == homeId }) else { return [] }
        return home.rooms
    }

    func homeName(_ homeId: String?) -> String? {
        guard let homeId else { return nil }
        return homes.first { $0.id == homeId }?.name
    }

    // MARK: - 小爱音箱候选

    /// 可作为小爱语音输出目标的设备：在线，且 model 指向小爱音箱系列。
    /// （精确判断需要拉取 spec 看是否含文本指令动作，这里用 model 前缀做低开销初筛，
    ///  设置里选定后实际下发时再按 spec 找文本动作。）
    var speakerCandidates: [MiDevice] {
        devices.filter { device in
            guard device.isOnline else { return false }
            return DeviceNaming.isSpeakerModel(device.model)
        }
    }

    /// 设置里选定的默认音箱（若未选 / 已删 / 不再是音箱型号则返回 nil）
    var defaultSpeaker: MiDevice? {
        guard let did = settings.defaultSpeakerDid else { return nil }
        guard let device = devices.first(where: { $0.did == did }),
              DeviceNaming.isSpeakerModel(device.model) else { return nil }
        return device
    }

    // MARK: - 菜单栏温湿度

    /// 从 spec 里挑出用于菜单栏展示的温度 / 湿度属性。
    ///
    /// 注意：`DevProp.name` 解析出来其实是**服务名**（如
    /// `temperature-humidity-sensor-2-1`），不能直接用来判断属性语义，
    /// 所以优先按 `desc` 匹配。同时排除目标值、室外温度、模块温度等非环境读数。
    func climateProps(in spec: DeviceSpec) -> (temperature: DevProp?, humidity: DevProp?) {
        func normalized(_ text: String) -> String {
            text.lowercased().replacingOccurrences(of: "_", with: "-")
        }

        // 只考虑可读的数值属性（排除 humidity-range 这类字符串范围）
        let numeric = spec.properties.filter {
            $0.isReadable && ["float", "int", "uint"].contains($0.type)
        }

        func isExcluded(_ prop: DevProp) -> Bool {
            let text = normalized("\(prop.name) \(prop.desc)")
            let blocked = ["target", "setpoint", "目标", "设定",
                           "outdoor", "室外", "户外", "模块", "压缩机",
                           "alarm", "报警"]
            return blocked.contains { text.contains($0) }
        }

        func temperatureScore(_ prop: DevProp) -> Int? {
            guard !isExcluded(prop) else { return nil }
            let name = normalized(prop.name)
            let desc = normalized(prop.desc)
            let byDesc = desc.contains("temperature") || desc.contains("温度")
            let byName = name == "temperature" || name.hasSuffix("-temperature")
            guard byDesc || byName else { return nil }

            var score = 0
            // 空调 / 净化器的环境服务里才是室温、室内湿度
            if name.hasPrefix("environment") { score += 4 }
            if desc.hasPrefix("temperature") || desc.hasPrefix("温度") { score += 2 }
            return score
        }

        func humidityScore(_ prop: DevProp) -> Int? {
            guard !isExcluded(prop) else { return nil }
            let name = normalized(prop.name)
            let desc = normalized(prop.desc)
            let byDesc = desc.contains("humidity") || desc.contains("湿度")
            let byName = name == "relative-humidity"
                || name == "humidity"
                || name.hasSuffix("-humidity")
            guard byDesc || byName else { return nil }

            var score = 0
            if name.hasPrefix("environment") { score += 4 }
            if desc.hasPrefix("relative-humidity")
                || desc.hasPrefix("humidity")
                || desc.hasPrefix("相对湿度")
                || desc.hasPrefix("湿度") { score += 2 }
            return score
        }

        func best(_ score: (DevProp) -> Int?) -> DevProp? {
            var result: DevProp?
            var bestScore = Int.min
            for prop in numeric {
                guard let value = score(prop) else { continue }
                if value > bestScore {
                    bestScore = value
                    result = prop
                }
            }
            return result
        }

        return (best(temperatureScore), best(humidityScore))
    }

    /// 扫描设备规格，找出能提供温湿度读数的设备（供设置页选择）。
    func loadClimateCandidates() async {
        guard !isLoadingClimateCandidates else { return }
        isLoadingClimateCandidates = true
        defer { isLoadingClimateCandidates = false }

        var result: [MiDevice] = []
        for device in devices {
            guard let spec = await spec(for: device) else { continue }
            let props = climateProps(in: spec)
            if props.temperature != nil || props.humidity != nil {
                result.append(device)
            }
        }
        // 温湿度传感器优先，其次空调 / 净化器 / 加湿器 / 浴霸，最后是其它设备
        func rank(_ device: MiDevice) -> Int {
            let model = device.model.lowercased()
            if model.contains("sensor") { return 0 }
            let climate = ["aircondition", "airp", "purifier", "humidifier", "bathheater"]
            if climate.contains(where: { model.contains($0) }) { return 1 }
            return 2
        }
        result.sort { rank($0) < rank($1) }
        climateCandidates = result

        // 已选设备已不存在 / 不再提供温湿度时清空
        if let did = settings.climateDeviceDid,
           !result.contains(where: { $0.did == did }) {
            settings.climateDeviceDid = nil
            settings.save()
        }

        // 温湿度模式下默认选第一台，避免菜单栏空着
        if settings.menuBarTitleMode == .climate,
           settings.climateDeviceDid == nil,
           let first = result.first {
            settings.climateDeviceDid = first.did
            settings.save()
            restartMenuBarClimateUpdates()
        }
    }

    /// 菜单栏文字：nil 表示只显示图标。
    var menuBarTitleText: String? {
        switch settings.menuBarTitleMode {
        case .none:
            return nil
        case .name:
            return "米家"
        case .climate:
            guard let reading = menuBarClimate else { return "米家" }
            let temperature = reading.temperature.map { "\(Int($0.rounded()))°" }
            let humidity = reading.humidity.map { "\(Int($0.rounded()))%" }
            switch (temperature, humidity) {
            case let (temperature?, humidity?):
                return "\(temperature)｜\(humidity)"
            case let (temperature?, nil):
                return temperature
            case let (nil, humidity?):
                return humidity
            default:
                return "米家"
            }
        }
    }

    /// 按设置启动 / 停止菜单栏温湿度轮询。每 60 秒刷新一次。
    func restartMenuBarClimateUpdates() {
        climateTask?.cancel()
        climateTask = nil
        menuBarClimate = nil

        guard settings.menuBarTitleMode == .climate,
              settings.climateDeviceDid != nil else { return }

        climateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshMenuBarClimate()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// 读取一次所选设备的温湿度属性。
    func refreshMenuBarClimate() async {
        guard settings.menuBarTitleMode == .climate,
              let did = settings.climateDeviceDid,
              let device = devices.first(where: { $0.did == did }),
              await cloud.isLoggedIn,
              let spec = await spec(for: device) else { return }

        let props = climateProps(in: spec)
        let targets = [props.temperature, props.humidity].compactMap { $0 }
        guard !targets.isEmpty else { return }

        let params: [MiPayload] = targets.map {
            ["did": .string(did), "siid": .int($0.siid), "piid": .int($0.piid)]
        }
        do {
            let results = try await cloud.getProps(params)
            var reading = menuBarClimate ?? ClimateReading()
            // 批量返回乱序，按 did+siid+piid 归位
            let values = PropResponses.values(from: results)
            for target in targets {
                guard let value = values[PropResponses.Key(did: did, prop: target)]?.doubleValue
                else { continue }
                if target.id == props.temperature?.id {
                    reading.temperature = value
                } else {
                    reading.humidity = value
                }
            }
            if !reading.isEmpty { menuBarClimate = reading }
        } catch {
            // 菜单栏读数刷新失败不打扰用户，保留上一次的值
        }
    }

    // MARK: - 关于

    /// GitHub 仓库地址（设置页「项目仓库」链接）。若与实际仓库不符，改这里即可。
    static let githubRepo = "dumo/mijia-mac"

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// 菜单栏里显示的设备（自动模式）：沿用稳定顺序取前 maxCount 个。
    /// 不再按在线状态重排，否则每次刷新在线集合变化，条目位置就会跳。
    func menuDevices(maxCount: Int = 8) -> [MiDevice] {
        Array(devices.prefix(maxCount))
    }

    /// 菜单栏托盘当前真正会展示的设备：自定义模式按 `trayOrder`，否则走自动模式。
    /// 刷新开关状态时按这个集合取，保证「看得到的」状态都是最新的。
    func trayDevices(maxCount: Int = 8) -> [MiDevice] {
        let byDid = Dictionary(uniqueKeysWithValues: devices.map { ($0.did, $0) })
        let prefix = "device:"
        if !settings.trayOrder.isEmpty {
            let picked = settings.trayOrder.compactMap { id -> MiDevice? in
                guard id.hasPrefix(prefix) else { return nil }
                return byDid[String(id.dropFirst(prefix.count))]
            }
            if !picked.isEmpty { return picked }
        }
        return menuDevices(maxCount: maxCount)
    }
}
