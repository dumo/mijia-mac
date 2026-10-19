import SwiftUI
import MijiaCore

/// 托盘快捷窗口里的条目：设备开关 或 场景一键执行
enum TrayItem: Identifiable, Hashable {
    case device(MiDevice)
    case scene(MiScene)

    var id: String {
        switch self {
        case .device(let d): "device:\(d.did)"
        case .scene(let s): "scene:\(s.sceneId)"
        }
    }
}

/// 菜单栏玻璃面板：最常用的「一键开关」+ 场景执行，支持单列/双列与混排拖拽排序。
struct MenuPanelView: View {
    @Environment(AppState.self) private var state
    @State private var items: [TrayItem] = []
    @State private var runningSceneId: String?

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if state.phase == .needLogin {
                needLoginBlock
            } else if items.isEmpty {
                emptyBlock
            } else {
                grid
            }
            Divider()
            toolbar
        }
        .padding(14)
        // 双列时加宽面板，否则设备名会被截成「毒…」
        .frame(width: state.settings.trayColumns == 2 ? 470 : 322)
        .task { await reload() }
        .onChange(of: state.devices) { _, _ in Task { await reload() } }
        .onChange(of: state.scenes) { _, _ in Task { await reload() } }
        .onChange(of: state.settings.hideScenes) { _, _ in Task { await reload() } }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "house.fill").foregroundStyle(.secondary)
            Text("米家")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if state.isLoadingDevices || state.isWaitingForScan || state.isLoadingScenes {
                ProgressView().controlSize(.small)
            }
            // 单列 / 双列切换
            Picker("列数", selection: columnBinding) {
                Image(systemName: "rectangle.grid.1x2").tag(1)
                Image(systemName: "rectangle.split.2x2").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 70)
            .help("切换单列 / 双列")
        }
    }

    private var columnBinding: Binding<Int> {
        .init(
            get: { state.settings.trayColumns },
            set: { newValue in
                state.settings.trayColumns = newValue
                state.settings.save()
            })
    }

    // MARK: - 内容

    @ViewBuilder
    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = state.actionError {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                trayGrid
                    .padding(.vertical, 1)
            }
            // 面板高度封顶，避免设备+场景很多时撑出屏幕。
            // ScrollView 没有固有高度，这里按条目数算出明确高度，否则窗口会塌陷。
            .frame(height: gridHeight)
            .scrollIndicators(.visible)
        }
    }

    private var trayColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8),
              count: max(1, min(2, state.settings.trayColumns)))
    }

    /// 与主窗口同一套自定义手势重排：条目始终是活视图，拖动时不会只剩 AppKit 控件。
    private var trayGrid: some View {
        ReorderableGrid(items: $items, columns: trayColumns, spacing: 8, liftScale: 1.03) { ordered in
            state.settings.trayOrder = ordered.map(\.id)
            state.settings.save()
        } content: { item, _ in
            trayCell(item)
        }
    }

    private func trayCell(_ item: TrayItem) -> some View {
        // 与网格同理：不挂 glassEffectID，避免拖动时源视图被隐藏
        cell(for: item)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12))
    }

    private var gridHeight: CGFloat {
        let cols = max(1, min(2, state.settings.trayColumns))
        let rows = ceil(Double(items.count) / Double(cols))
        return min(380, max(64, CGFloat(rows) * 52))
    }

    @ViewBuilder
    private func cell(for item: TrayItem) -> some View {
        switch item {
        case .device(let device):
            DeviceToggleRow(device: device)
        case .scene(let scene):
            SceneQuickRow(scene: scene, isRunning: runningSceneId == scene.id) {
                Task {
                    runningSceneId = scene.id
                    _ = await state.runScene(scene)
                    runningSceneId = nil
                }
            }
        }
    }

    private var needLoginBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("需要扫码登录")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                MainWindowController.shared.show(state: state)
            } label: {
                Label("打开主窗口扫码", systemImage: "qrcode")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    private var emptyBlock: some View {
        Text(state.isLoadingDevices ? "正在加载设备…" : "暂无设备与场景")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    // MARK: - 底部工具栏

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                MainWindowController.shared.show(state: state)
            } label: {
                Label("主窗口", systemImage: "macwindow")
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Button {
                Task { await reload(force: true) }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .controlSize(.small)

            Spacer()

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
    }

    // MARK: - 数据

    /// - Parameter force: 手动点「刷新」时传 true，忽略节流阈值。
    /// 打开面板时按 30s 阈值判断是否真正请求，未超时直接复用缓存。
    private func reload(force: Bool = false) async {
        guard state.phase == .ready else { return }
        await state.refreshIfNeeded(force: force)
        items = buildItems()
    }

    private func buildItems() -> [TrayItem] {
        let sceneItems: [TrayItem] = state.settings.hideScenes ? [] : state.scenes.map(TrayItem.scene)

        // 自定义模式可以选到「前 8 个」之外的设备，所以索引用全量设备
        let allDeviceItems: [TrayItem] = state.devices.map(TrayItem.device)
        let byId = Dictionary(uniqueKeysWithValues:
            (allDeviceItems + sceneItems).map { ($0.id, $0) })

        // 自定义模式：trayOrder 非空时，它就是「要显示哪些 + 按什么顺序」
        let stored = state.settings.trayOrder
        if !stored.isEmpty {
            let picked = stored.compactMap { byId[$0] }
            if !picked.isEmpty { return picked }
        }

        // 自动模式：稳定顺序的前 8 个设备 → 场景
        return state.menuDevices().map(TrayItem.device) + sceneItems
    }
}

/// 场景在托盘里的快捷执行行
private struct SceneQuickRow: View {
    let scene: MiScene
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        Button(action: onRun) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.mijiaGreen)
                Text(scene.name.isEmpty ? "未命名场景" : scene.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 2)
                if isRunning { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
    }
}

/// 设备开关行（与托盘玻璃卡片配套）
struct DeviceToggleRow: View {
    @Environment(AppState.self) private var state
    let device: MiDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: DeviceIcon.systemName(for: device))
                .font(.system(size: 13))
                .foregroundStyle(device.isOnline ? .primary : .tertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                if let room = device.roomName {
                    Text(room)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if state.pendingDevices.contains(device.did) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            } else if state.switchLoaded.contains(device.did) {
                Toggle("", isOn: Binding(
                    get: { state.switchState[device.did] ?? false },
                    set: { newValue in
                        Task { await state.toggle(device, to: newValue) }
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!device.isOnline)
            } else if state.switchUnavailable.contains(device.did) {
                // 没有可写开关的设备（传感器等）：显示状态点足矣
                Circle()
                    .fill(device.isOnline ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 8, height: 8)
            } else {
                // 还没拿到真实状态：不要显示成「关」，转圈等一下
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 34)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .opacity(device.isOnline ? 1 : 0.55)
    }
}
