import Foundation
import SwiftUI
import AppKit

/// 全局设置：主题、开机自启、隐藏场景入口、默认小爱音箱、版本检测缓存。
///
/// 落盘在 `~/Library/Application Support/mijia-mac/settings.json`，
/// 写入走「临时文件 + 原子替换」（与 `WorkbenchStore` 同一范式）。
///
/// 开机自启在 macOS 上不是注册表，而是 `~/Library/LaunchAgents/<bundleId>.plist`。
@MainActor
@Observable
final class SettingsStore {

    enum ColorSchemeMode: String, Codable, CaseIterable {
        case system, light, dark

        var label: String {
            switch self {
            case .system: "跟随系统"
            case .light: "浅色"
            case .dark: "深色"
            }
        }

        /// 映射到 SwiftUI 的 `preferredColorScheme` 入参（`.system` 为 nil）。
        var swiftUI: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    /// 菜单栏图标旁显示的文字
    enum MenuBarTitleMode: String, Codable, CaseIterable {
        case none
        case name
        case climate

        var label: String {
            switch self {
            case .none: "不显示文字"
            case .name: "显示米家"
            case .climate: "显示温湿度"
            }
        }
    }

    var colorScheme: ColorSchemeMode = .system
    var launchAtLogin: Bool = false
    var hideScenes: Bool = false
    var defaultSpeakerDid: String? = nil
    /// 菜单栏文字模式：不显示 / 米家 / 温湿度
    var menuBarTitleMode: MenuBarTitleMode = .name
    /// 菜单栏温湿度的数据来源设备
    var climateDeviceDid: String? = nil
    /// 最近一次版本检测结果（最新 release 的 tag，如 "v1.2.0"）
    var latestVersion: String? = nil
    var lastVersionCheckAt: Date? = nil

    /// 托盘快捷窗口列数：1 或 2
    var trayColumns: Int = 1
    /// 托盘里设备/场景的混排顺序（id 形如 `device:<did>` / `scene:<sid>`）。
    /// 非空 = 自定义模式：只显示这些条目，且按此顺序；空 = 自动模式。
    var trayOrder: [String] = []
    /// 主窗口设备卡片的稳定顺序（did 列表）：首次拉取播种，之后只追加新设备。
    /// 空 = 未播种；用户拖拽排序后即为自定义顺序。
    var deviceOrder: [String] = []
    /// 上次刷新设备列表（含家庭/房间）的时间
    var lastDevicesRefreshAt: Date? = nil
    /// 上次批量刷新开关状态的时间
    var lastSwitchRefreshAt: Date? = nil

    private let fileURL: URL
    private let launchAgentURL: URL

    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        self.fileURL = dir.appendingPathComponent("settings.json")
        let bundleId = Bundle.main.bundleIdentifier ?? "com.mijia.mac"
        self.launchAgentURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(bundleId).plist")
        load()
        // 以磁盘上是否真有 plist 为准，纠正开关状态（避免上次写入被手动删掉）
        launchAtLogin = FileManager.default.fileExists(atPath: launchAgentURL.path)
        // 让 AppKit 窗口/毛玻璃材质跟随主题（SwiftUI 的 preferredColorScheme 管不到侧边栏 vibrancy）
        applyAppearance()
    }

    /// 把主题同步到 AppKit，保证 NSVisualEffectView、菜单、popover 与 SwiftUI 内容一致。
    func applyAppearance() {
        switch colorScheme {
        case .system: NSApp?.appearance = nil
        case .light: NSApp?.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp?.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func defaultDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/mijia-mac")
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        colorScheme = decoded.colorScheme
        hideScenes = decoded.hideScenes
        defaultSpeakerDid = decoded.defaultSpeakerDid
        latestVersion = decoded.latestVersion
        lastVersionCheckAt = decoded.lastVersionCheckAt
        trayColumns = decoded.trayColumns
        trayOrder = decoded.trayOrder
        menuBarTitleMode = decoded.menuBarTitleMode ?? .name
        climateDeviceDid = decoded.climateDeviceDid
        deviceOrder = decoded.deviceOrder
        lastDevicesRefreshAt = decoded.lastDevicesRefreshAt
        lastSwitchRefreshAt = decoded.lastSwitchRefreshAt
        // launchAtLogin 以磁盘 plist 为准，不读持久化里的值
    }

    func save() {
        let payload = Persisted(
            colorScheme: colorScheme,
            hideScenes: hideScenes,
            defaultSpeakerDid: defaultSpeakerDid,
            latestVersion: latestVersion,
            lastVersionCheckAt: lastVersionCheckAt,
            trayColumns: trayColumns,
            trayOrder: trayOrder,
            menuBarTitleMode: menuBarTitleMode,
            climateDeviceDid: climateDeviceDid,
            deviceOrder: deviceOrder,
            lastDevicesRefreshAt: lastDevicesRefreshAt,
            lastSwitchRefreshAt: lastSwitchRefreshAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        writeAtomically(data, to: fileURL)
    }

    /// 任意字段变更后调用；目前所有 setter 都已在各自方法里 save，
    /// 这个便捷方法给外部批量修改用。
    func persist() { save() }

    // MARK: - 开机自启（LaunchAgent）

    func setLaunchAtLogin(_ enabled: Bool) {
        if enabled {
            writeLaunchAgent()
        } else {
            try? FileManager.default.removeItem(at: launchAgentURL)
        }
        launchAtLogin = enabled
        save()
    }

    private func writeLaunchAgent() {
        let bundle = Bundle.main
        let executable = bundle.executableURL?.path
            ?? bundle.bundleURL.appendingPathComponent("Contents/MacOS/MijiaMac").path
        let label = bundle.bundleIdentifier ?? "com.mijia.mac"
        let dict: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        guard let plistData = try? PropertyListSerialization.data(
            fromPropertyList: dict, format: .xml, options: 0)
        else { return }
        writeAtomically(plistData, to: launchAgentURL)
    }

    // MARK: - 版本检测缓存

    func recordVersionCheck(_ latest: String?) {
        latestVersion = latest
        lastVersionCheckAt = Date()
        save()
    }

    // MARK: - 原子写（临时文件 + 替换）

    private func writeAtomically(_ data: Data, to url: URL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.moveItem(at: tmp, to: url)
            } else {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    // MARK: - 持久化结构

    private struct Persisted: Codable {
        var colorScheme: ColorSchemeMode
        var hideScenes: Bool
        var defaultSpeakerDid: String?
        var latestVersion: String?
        var lastVersionCheckAt: Date?
        var trayColumns: Int = 1
        var trayOrder: [String] = []
        /// 可选：老版本 settings.json 没有这两个字段时按默认值处理
        var menuBarTitleMode: MenuBarTitleMode?
        var climateDeviceDid: String?
        /// 后加的字段都要有默认值，否则旧 settings.json 会解码失败、静默丢设置
        var deviceOrder: [String] = []
        var lastDevicesRefreshAt: Date? = nil
        var lastSwitchRefreshAt: Date? = nil
    }
}
