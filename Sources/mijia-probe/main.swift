import Foundation
import MijiaCore

// MARK: - 参数解析

let arguments = CommandLine.arguments

func value(of flag: String) -> String? {
    guard let i = arguments.firstIndex(of: flag), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

if arguments.contains("--help") {
    print("""
    mijia-probe —— P0 协议验证探针

    用法:
      mijia-probe                                  登录并列出家庭/设备
      mijia-probe --auth /path/to/auth.json        指定认证文件（默认 ~/.config/mijia-mac/auth.json）
      mijia-probe --spec urn:miot-spec-v2:device:...  额外打印某个设备的规格
      mijia-probe --did <did> --siid 2 --piid 1    额外读取一个属性值
      mijia-probe --switchscan                     只读：批量 vs 逐台读取开关属性，
                                                   检查返回条数/did 字段/取值是否与请求对齐
    """)
    exit(0)
}

let authFile = value(of: "--auth").map { URL(fileURLWithPath: $0) }
let cloud = MiCloud(authFile: authFile)

func log(_ message: String) { print(message) }

/// 二维码有效期短，超时后必须**重新拉一张**再等，这里最多刷 4 轮。
func ensureLogin() async throws {
    for round in 1...4 {
        guard let ticket = try await cloud.fetchQRTicket() else {
            log("✅ 已有有效登录态，无需扫码")
            return
        }

        log("")
        log("== 第 \(round) 轮二维码（每轮 110 秒，超时会自动换一张）==")
        log("")
        if let ascii = QRCode.ascii(ticket.loginURL) {
            print(ascii)
        }

        // 终端 ASCII 容易因字体导致扫不出来，同时落一张 PNG 直接打开
        let qrPath = "/tmp/mijia-login-qr.png"
        if let png = QRCode.pngData(ticket.loginURL) {
            try? png.write(to: URL(fileURLWithPath: qrPath))
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = [qrPath]
            try? open.run()
            log("已打开二维码图片: \(qrPath)")
        }
        log("二维码图片链接（备选）: \(ticket.imageURL)")
        log("等待扫码...")

        do {
            try await cloud.completeLogin(lp: ticket.longPollingURL)
            log("")
            log("✅ 登录成功，已保存到 \(cloud.authFile.path)")
            return
        } catch let error as MiError where error == .timeout {
            log("⏱ 本轮超时，正在刷新二维码...")
            continue
        }
    }
    throw MiError.timeout
}

do {
    log("认证文件: \(cloud.authFile.path)")
    try await ensureLogin()

    let homes = try await cloud.homes()
    log("")
    log("家庭 (\(homes.count)):")
    for home in homes {
        let rooms = home.rooms.map(\.name).joined(separator: "、")
        log("  • \(home.name)   id=\(home.id)   uid=\(home.uid)   房间: \(rooms)")
    }

    let devices = try await cloud.devices()
    log("")
    log("设备 (\(devices.count)):")
    for device in devices {
        let room = device.roomName.map { "  [\($0)]" } ?? ""
        log("  • \(device.name)\(room)   \(device.isOnline ? "在线" : "离线")")
        log("      model=\(device.model)   did=\(device.did)")
        log("      spec_type=\(device.specType ?? "(缺失，需 model 兜底)")")
    }

    if let specType = value(of: "--spec") {
        let spec = try await MiotSpecStore().spec(forType: specType)
        log("")
        log("规格 \(spec.name)  (\(spec.specType)):")
        for p in spec.properties {
            let range = p.range.map { "\($0)" } ?? "-"
            log("  [\(p.id)] \(p.name)  \(p.desc)   type=\(p.type) rw=\(p.rw) range=\(range)")
        }
        for a in spec.actions {
            log("  <\(a.id)> \(a.name)  \(a.desc)")
        }
    }

    // 只读：把规格按工作台规则展开，检查中文标题/分组/默认 key 是否符合预期
    if arguments.contains("--workbench") {
        let specType = value(of: "--spec") ?? devices.first(where: \.isOnline)?.specType
        if let specType {
            let spec = try await MiotSpecStore().spec(forType: specType)
            log("")
            log("工作台预览 \(spec.name)  (\(spec.specType)):")
            let groups = DeviceNaming.groups(spec.properties)
            for group in groups {
                let master = group.master.map { DeviceNaming.chineseTitle(desc: $0.desc, fallbackName: $0.name) } ?? "(无 master)"
                let kind = group.isComposite ? "组合 · \(group.members.count) 项" : "单属性"
                log("  [\(group.key)] \(master)   \(kind)")
                if group.isComposite {
                    for member in group.members where member.id != group.master?.id {
                        log("      · \(DeviceNaming.chineseTitle(desc: member.desc, fallbackName: member.name))   \(DeviceNaming.metaText(member))")
                    }
                }
            }
            for action in spec.actions {
                log("  [\(DeviceNaming.actionKey(action))] \(DeviceNaming.chineseTitle(desc: action.desc, fallbackName: action.name))   动作")
            }
            let defaults = DeviceNaming.defaultKeys(props: spec.properties, actions: spec.actions)
            log("  默认展示: \(defaults)")
        } else {
            log("⚠️ 没有可用于工作台预览的 spec_type")
        }
    }

    // 写属性（用于验证下发链路）
    if let did = value(of: "--set-did"),
       let siid = value(of: "--siid").flatMap(Int.init),
       let piid = value(of: "--piid").flatMap(Int.init),
       let raw = value(of: "--set-value") {
        let value: JSONValue
        switch raw {
        case "true": value = .bool(true)
        case "false": value = .bool(false)
        default: value = Int(raw).map { .int($0) } ?? .string(raw)
        }
        let result = try await cloud.setProps([[
            "did": .string(did), "siid": .int(siid), "piid": .int(piid), "value": value,
        ]])
        log("")
        log("设置 \(siid).\(piid) = \(raw) => \(try result.first?.compactJSON() ?? "nil")")
    }

    if let did = value(of: "--did"),
       let siid = value(of: "--siid").flatMap(Int.init),
       let piid = value(of: "--piid").flatMap(Int.init) {
        let result = try await cloud.getProp(["did": .string(did),
                                              "siid": .int(siid),
                                              "piid": .int(piid)])
        log("")
        log("属性 \(siid).\(piid) => \(try result?.compactJSON() ?? "nil")")
    }

    // 只读：验证 /miotspec/prop/get 的批量返回是否与请求严格对齐。
    // AppState.refreshSwitchState 当前是「按下标」把结果配回 did 的，
    // 一旦服务端省略/重排条目，开关值就会张冠李戴（表现为设备显示别人的开关状态）。
    if arguments.contains("--switchscan") {
        log("")
        log("== 开关属性扫描（只读，不下发任何指令）==")

        /// 复刻 AppState.primarySwitch 的选取规则
        func primarySwitch(of device: MiDevice) async -> DevProp? {
            guard let specType = device.specType, !specType.isEmpty else { return nil }
            guard let spec = try? await MiotSpecStore().spec(forType: specType) else { return nil }
            return spec.properties.first { $0.name == "on" && $0.isWritable }
                ?? spec.properties.first { $0.name == "switch" && $0.isWritable }
                ?? spec.properties.first { $0.type == "bool" && $0.isWritable }
        }

        var targets: [(device: MiDevice, prop: DevProp)] = []
        for device in devices {
            if let prop = await primarySwitch(of: device) {
                targets.append((device, prop))
            } else {
                log("  ⚠️ 无开关属性 / spec 拉取失败: \(device.name)  did=\(device.did)")
            }
        }

        let params: [MiPayload] = targets.map {
            ["did": .string($0.device.did), "siid": .int($0.prop.siid), "piid": .int($0.prop.piid)]
        }
        log("")
        log("批量请求 \(params.count) 条；可解析出开关属性的设备 \(targets.count)/\(devices.count)")

        let results = try await cloud.getProps(params)
        let countOK = params.count == results.count
        log("批量返回 \(results.count) 条 → \(countOK ? "✅ 条数一致" : "❌ 条数不一致：按下标取值会整体错位！")")

        var missingDid = 0
        var mismatch = 0
        for (index, result) in results.enumerated() {
            let obj = result.objectValue
            let responseDid = obj?["did"]?.stringValue
            let code = obj?["code"]?.intValue
            let value = obj?["value"]
            let requestDid = index < targets.count ? targets[index].device.did : "?"
            if responseDid == nil { missingDid += 1 }
            let matched = responseDid == requestDid
            if !matched { mismatch += 1 }
            let valueText = (value.flatMap { try? $0.compactJSON() }) ?? "nil"
            let codeText = code.map { "\($0)" } ?? "?"
            log("  [\(String(format: "%02d", index))] req=\(requestDid) resp=\(responseDid ?? "(无did)") code=\(codeText) value=\(valueText)\(matched ? "" : "   ❌ did 不匹配")")
        }

        log("")
        log("返回项自带 did : \(missingDid == 0 ? "✅ 全部都有（可改用按 did 匹配）" : "❌ 有 \(missingDid) 条没有 did 字段")")
        log("did 不匹配条数 : \(mismatch)\(mismatch == 0 && countOK ? "   ✅ 顺序与请求一致" : "   ❌ 顺序/条数有问题")")

        log("")
        log("== 逐台单设备对照（批量 vs 单台）==")
        var diff = 0
        for (index, target) in targets.enumerated() {
            let single = try await cloud.getProp(["did": .string(target.device.did),
                                                  "siid": .int(target.prop.siid),
                                                  "piid": .int(target.prop.piid)])
            let sObj = single?.objectValue
            let sCode = sObj?["code"]?.intValue
            let sValue = sObj?["value"]?.boolValue
            let bObj = index < results.count ? results[index].objectValue : nil
            let bCode = bObj?["code"]?.intValue
            let bValue = bObj?["value"]?.boolValue
            let same = sCode == bCode && sValue == bValue
            if !same { diff += 1 }
            let bCodeText = bCode.map { "\($0)" } ?? "-"
            let bValueText = bValue.map { "\($0)" } ?? "-"
            let sCodeText = sCode.map { "\($0)" } ?? "-"
            let sValueText = sValue.map { "\($0)" } ?? "-"
            log("  \(target.device.name)  批量(code=\(bCodeText), val=\(bValueText))  单台(code=\(sCodeText), val=\(sValueText))\(same ? "" : "   ❌ 不一致")")
        }
        log("")
        log("批量与单台取值不一致: \(diff) 台")
    }

} catch let error as MiError {
    log("❌ \(error.localizedDescription)")
    exit(1)
} catch {
    log("❌ \(error)")
    exit(1)
}
