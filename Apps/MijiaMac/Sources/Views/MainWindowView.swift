import SwiftUI
import MijiaCore

extension Color {
    /// 米家绿强调色（深/浅双主题一致）
    static let mijiaGreen = Color(red: 7 / 255, green: 193 / 255, blue: 96 / 255)
}

/// 侧边栏选中项：全部 / 家庭 / 房间 / 未分配房间（未知）
enum SidebarSelection: Hashable {
    case all
    case home(String)
    case room(String, String)   // homeId, roomId
    case unknownRoom            // 未分配房间（或房间已不存在）的设备

    var homeId: String? {
        switch self {
        case .all, .unknownRoom: return nil
        case .home(let id), .room(let id, _): return id
        }
    }
    var roomId: String? {
        if case .room(_, let rid) = self { rid } else { nil }
    }
}

enum DetailTab: Hashable {
    case devices
    case scenes
}

struct MainWindowView: View {
    @Environment(AppState.self) private var state
    @State private var selection: SidebarSelection? = .all
    @State private var detailTab: DetailTab =
        ProcessInfo.processInfo.environment["MIJIA_SHOW_SCENES"] == "1" ? .scenes : .devices
    @State private var detailDevice: MiDevice?
    @Namespace private var glassNamespace
    /// 拖拽期间渲染的本地顺序；松手提交后置空，回到 state 的稳定顺序
    @State private var dragOrder: [MiDevice]?
    /// 拖拽刚结束时短暂抑制「点开详情」，避免松手误触
    @State private var suppressCardTapUntil = Date.distantPast

    private var homeId: String? { selection.flatMap(\.homeId) }
    private var roomId: String? { selection?.roomId }

    /// 位置由「首次拉取时播种、之后只追加」的稳定顺序决定：
    /// 不再按在线状态重排，否则每次刷新在线集合变化卡片就会跳位。
    private var visibleDevices: [MiDevice] {
        switch selection ?? .all {
        case .all:
            return state.orderedDevices()
        case .unknownRoom:
            return state.orderedDevices().filter(isUnknownRoom)
        case .home, .room:
            return state.orderedDevices(inHome: homeId, inRoom: roomId)
        }
    }

    /// 「未知」：设备没有房间，或房间已不存在（即米家里的「未分配房间」）。
    private func isUnknownRoom(_ device: MiDevice) -> Bool {
        guard let rid = device.roomId, !rid.isEmpty else { return true }
        return !state.rooms(inHome: device.homeId).contains { $0.id == rid }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 196, maximum: 250), spacing: 14)]
    }

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 188, ideal: 210)
        } detail: {
            detailContent
                .frame(minWidth: 520)
        }
        .tint(.mijiaGreen)
        .sheet(item: $detailDevice) { device in
            DeviceDetailView(device: device)
                .environment(state)
        }
        .onChange(of: selection) { _, new in
            state.currentHomeId = new.flatMap(\.homeId)
            if detailTab == .scenes { Task { await state.loadScenes() } }
        }
        .onChange(of: detailTab) { _, new in
            if new == .scenes { Task { await state.loadScenes() } }
        }
        // 打开主窗口时按阈值节流刷新；切换分组只补开关状态，不重复拉设备列表
        .task {
            await state.refreshIfNeeded()
        }
        .task(id: selection) {
            await state.refreshSwitchState(for: visibleDevices, force: false)
        }
    }

    // MARK: - 侧边栏

    @ViewBuilder
    private var sidebar: some View {
        @Bindable var state = state
        List(selection: $selection) {
            Section {
                sidebarRow("全部", icon: "square.grid.2x2", value: .all)
                    .font(.system(size: 13, weight: .medium))

                ForEach(state.homes) { home in
                    sidebarRow(home.name, icon: "house", value: .home(home.id))
                        .font(.system(size: 13, weight: .medium))

                    ForEach(state.rooms(inHome: home.id)) { room in
                        sidebarRow(room.name, icon: "rectangle.portrait",
                                   value: .room(home.id, room.id))
                            .font(.system(size: 12.5))
                            .padding(.leading, 14)
                    }
                }

                sidebarRow("未知", icon: "questionmark.circle", value: .unknownRoom)
                    .font(.system(size: 13, weight: .medium))
            } header: {
                Text("家庭与房间")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.sidebar)
        .tint(.mijiaGreen)
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
    }

    /// 侧边栏行：图标统一为线性风格。
    /// 未选中用次级前景色（不拿主题色染图标），选中时用白色，靠底色高亮区分。
    private func sidebarRow(_ title: String,
                            icon: String,
                            value: SidebarSelection) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(selection == value ? Color.white : Color.secondary)
        }
        .symbolVariant(.none)
        .tag(value)
    }

    private var bottomBar: some View {
        @Bindable var state = state
        return VStack(alignment: .leading, spacing: 6) {
            if let error = state.actionError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let status = state.statusMessage {
                Text(status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    Task { await state.refreshIfNeeded(force: true) }
                } label: {
                    Label("刷新设备", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(nil)
                .controlSize(.small)

                Spacer()

                Button {
                    MainWindowController.shared.showSettings(state: state)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.bordered)
                .tint(nil)
                .controlSize(.small)

                Button {
                    Task { await state.logout() }
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .buttonStyle(.bordered)
                .tint(nil)
                .controlSize(.small)
                .help("退出登录")
            }
        }
        .padding(10)
    }

    // MARK: - 详情区

    @ViewBuilder
    private var detailContent: some View {
        if state.phase == .needLogin {
            LoginView()
        } else if state.devices.isEmpty {
            ContentUnavailableView {
                Label(state.isLoadingDevices ? "正在加载设备" : "暂无设备",
                      systemImage: "square.grid.2x2")
            } description: {
                Text(state.isLoadingDevices ? "正在从米家云拉取设备列表" : "登录后可看到账号下的设备")
            }
        } else {
            VStack(spacing: 0) {
                if state.settings.hideScenes {
                    devicesGrid
                } else {
                    Picker("视图", selection: $detailTab) {
                        Text("设备").tag(DetailTab.devices)
                        Text("场景").tag(DetailTab.scenes)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    if detailTab == .devices {
                        devicesGrid
                    } else {
                        ScenesView()
                            .environment(state)
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                XiaoAIVoiceView()
                    .environment(state)
            }
        }
    }

    private var devicesGrid: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                deviceCountLabel
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    gridContent
                        .padding(20)
                }
            }
        }
    }

    /// 自定义手势重排（`ReorderableGrid`）：卡片始终是活视图。
    /// 系统 `.reorderable()` 抬起时会做快照，玻璃与 SwiftUI 文字会丢失、只剩 AppKit 控件，
    /// 因此这里不用它。
    private var gridContent: some View {
        ReorderableGrid(items: deviceBinding,
                        columns: columns,
                        spacing: 14,
                        onCommit: { ordered in
                            state.commitDeviceOrder(ordered.map(\.did))
                            suppressCardTapUntil = Date().addingTimeInterval(0.3)
                            dragOrder = nil
                        }) { device, _ in
            card(for: device)
        }
    }

    /// 拖拽时用本地副本渲染；松手提交后回到 state 的稳定顺序
    private var deviceBinding: Binding<[MiDevice]> {
        Binding(get: { dragOrder ?? visibleDevices },
                set: { dragOrder = $0 })
    }

    private func card(for device: MiDevice) -> some View {
        DeviceCardView(device: device) {
            guard Date() >= suppressCardTapUntil else { return }
            detailDevice = device
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        .glassEffectID(device.id, in: glassNamespace)
    }

    /// 设备统计：共 N 台设备 • M 台在线（纯文本，不带按钮/胶囊背景）
    private var deviceCountLabel: some View {
        let total = visibleDevices.count
        let online = visibleDevices.filter(\.isOnline).count
        return HStack(spacing: 6) {
            Text("共 \(total) 台设备")
            Circle()
                .fill(Color.mijiaGreen)
                .frame(width: 6, height: 6)
            Text("\(online) 台在线")
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
}
