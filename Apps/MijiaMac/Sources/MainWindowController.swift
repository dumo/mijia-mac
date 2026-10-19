import AppKit
import SwiftUI
import MijiaCore

/// 主窗口用 AppKit 托管：LSUIElement + SwiftUI Window 场景在 accessory 模式下
/// 不会自动出现，用 NSWindow 反而更可控（也方便做「打开时显示 Dock 图标，
/// 关闭后回到纯菜单栏」的切换）。
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {

    static let shared = MainWindowController()

    private var window: NSWindow?
    /// 供窗口激活回调使用（重新打开主窗口时按需刷新）
    private var state: AppState?

    func show(state: AppState) {
        self.state = state
        if let window {
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Task { await state.refreshIfNeeded() }
            return
        }

        let hosting = NSHostingController(rootView: MainWindowView().environment(state))
        let window = NSWindow(contentViewController: hosting)

        // 窗口底色用系统语义色 `windowBackgroundColor`：它是动态色，
        // 会随 NSApp.appearance（跟随系统/浅色/深色）实时重新解析，
        // 既保证整窗背景正确切换，又不会像 `behindWindow` 毛玻璃那样透出桌面。
        window.title = "米家"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = true
        window.setContentSize(NSSize(width: 1000, height: 680))
        window.minSize = NSSize(width: 860, height: 540)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.tabbingMode = .disallowed

        self.window = window
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task { await state.refreshIfNeeded() }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    /// 窗口重新变为 key（例如从菜单栏再次唤起、或点击窗口）时按需刷新。
    /// 内部有 30s 节流，重复触发不会造成多余请求。
    func windowDidBecomeKey(_ notification: Notification) {
        guard let state else { return }
        Task { await state.refreshIfNeeded() }
    }

    // MARK: - 设置窗口（独立窗口，可点红钮关闭，改动即时生效）

    private var settingsWindow: NSWindow?

    func showSettings(state: AppState) {
        if let settingsWindow {
            NSApp.setActivationPolicy(.regular)
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView().environment(state))
        let window = NSWindow(contentViewController: hosting)
        window.title = "设置"
        window.styleMask = [.titled, .closable]
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.setContentSize(NSSize(width: 580, height: 640))
        window.minSize = NSSize(width: 520, height: 560)
        window.center()
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        settingsWindow = window

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 调试：把详情页单独渲染出来（MIJIA_SHOW_DETAIL=1）

    private var detailPreview: NSWindow?

    /// 用 DetailPreview 的假数据渲染详情页：**不触网、不下发任何指令**。
    func showDetailPreview(state: AppState, online: Bool = true,
                           editing: Bool = false, showAdd: Bool = false) {
        let device = DetailPreview.makeDevice(online: online)
        let spec = DetailPreview.makeSpec()
        state.installPreview(spec: spec, values: DetailPreview.makeValues(), for: device)
        state.setPreviewWorkbench(DetailPreview.moduleKeys, for: device)
        presentDetail(state: state, device: device, editing: editing, showAdd: showAdd)
    }

    /// 用真实设备渲染详情页（只读：拉 spec + 读属性，不下发任何指令）
    func showRealDetail(state: AppState, device: MiDevice, editing: Bool = false) {
        presentDetail(state: state, device: device, editing: editing, showAdd: false)
    }

    private func presentDetail(state: AppState, device: MiDevice,
                               editing: Bool, showAdd: Bool) {
        let hosting = NSHostingController(
            rootView: DeviceDetailView(device: device,
                                       initialEditing: editing,
                                       initialShowAdd: showAdd)
                .environment(state))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable]
        window.title = "详情页预览"
        window.backgroundColor = NSColor.windowBackgroundColor
        window.setContentSize(NSSize(width: 540, height: 640))
        window.center()
        window.isReleasedWhenClosed = false

        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        detailPreview = window
    }

    // MARK: - 调试：把菜单栏面板单独渲染出来（MIJIA_SHOW_MENU=1）

    private var menuPreview: NSWindow?

    func showMenuPreview(state: AppState) {
        let hosting = NSHostingController(rootView: MenuPanelView().environment(state))
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.center()
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        menuPreview = window
    }
}
