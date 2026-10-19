import SwiftUI
import MijiaCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏常驻：不在 Dock 显示图标
        NSApp.setActivationPolicy(.accessory)

        Task { @MainActor in
            let state = AppState.shared

            // 调试开关：只用本地假数据渲染详情页，不触网、不下发任何指令
            let env = ProcessInfo.processInfo.environment
            if let mode = env["MIJIA_SHOW_DETAIL"], !mode.isEmpty, mode != "0" {
                if mode == "live" {
                    // 真实设备：只读 spec 与属性，不做任何下发
                    await state.bootstrap()
                    if let device = state.devices.first(where: \.isOnline) ?? state.devices.first {
                        MainWindowController.shared.showRealDetail(state: state, device: device)
                    }
                } else {
                    MainWindowController.shared.showDetailPreview(
                        state: state,
                        online: mode != "offline",
                        editing: mode == "edit",
                        showAdd: mode == "add")
                }
                return
            }

            await state.bootstrap()
            // 启动即显示主窗口（未登录时用于扫码，已登录时直接看设备）。
            MainWindowController.shared.show(state: state)
            if env["MIJIA_SHOW_MENU"] == "1" {
                MainWindowController.shared.showMenuPreview(state: state)
            }
            if env["MIJIA_SHOW_SETTINGS"] == "1" {
                MainWindowController.shared.showSettings(state: state)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct MijiaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environment(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏图标 + 可选文字（不显示 / 米家 / 实时温湿度）。
private struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "house.fill")
            if let text = state.menuBarTitleText {
                Text(text)
                    .monospacedDigit()
            }
        }
    }
}
