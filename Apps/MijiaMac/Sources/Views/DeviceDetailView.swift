import SwiftUI
import MijiaCore

/// 设备详情（工作台）：只展示用户添加过的功能，卡片化、中文命名。
///
/// 属性名来自 miot-spec 的 `"English / 中文"`，这里一律取中文作标题，
/// 技术名退到副标题；同一服务的属性聚合成一张组合卡，避免一屏几十行原始指令名。
struct DeviceDetailView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let device: MiDevice
    /// 调试用：直接以编辑模式 / 打开添加抽屉渲染
    var initialEditing: Bool = false
    var initialShowAdd: Bool = false

    @State private var spec: DeviceSpec?
    /// 规格解析器（含消歧后的标题），规格一变就重建，避免每帧重算字典
    @State private var resolver: WorkbenchResolver?
    @State private var keys: [String] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isEditing = false
    @State private var showAdd = false
    @State private var expanded: Set<String> = []
    @Namespace private var glassNamespace

    /// 两列瀑布流：按估算卡高把模块分配到当前较矮的一列，避免等高网格把一张高卡独占一列。
    private func splitColumns(_ modules: [WorkbenchModule]) -> (left: [WorkbenchModule], right: [WorkbenchModule]) {
        var left: [WorkbenchModule] = []
        var right: [WorkbenchModule] = []
        var leftH = 0, rightH = 0
        for module in modules {
            let h = Self.estimatedHeight(module)
            if leftH <= rightH {
                left.append(module); leftH += h + 12
            } else {
                right.append(module); rightH += h + 12
            }
        }
        return (left, right)
    }

    /// 估算单张卡高度（与 Windows 版 estimated_height 同思路），用于瀑布流两列平衡。
    private static func estimatedHeight(_ module: WorkbenchModule) -> Int {
        switch module {
        case .group(let group):
            return 56 + max(1, group.members.count) * 48
        case .action, .prop:
            return 92
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !device.isOnline {
                if state.isReadOnlySensor(device) {
                    sensorOfflineBar
                } else {
                    offlineBar
                }
            }
            Divider()
            content
            footer
        }
        .frame(width: 760, height: 680)
        .task { await load() }
        .onAppear {
            if initialEditing { isEditing = true }
            if initialShowAdd { showAdd = true }
        }
        .sheet(isPresented: $showAdd) {
            AddFeatureSheet(spec: spec ?? .empty, addedKeys: Set(keys)) { key in
                add(key)
            }
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: DeviceIcon.systemName(for: device))
                .font(.system(size: 26))
                .foregroundStyle(device.isOnline ? .primary : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(device.model)
                    if let room = device.roomName, !room.isEmpty {
                        Text("·").foregroundStyle(.tertiary)
                        Text(room)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(isEditing ? "完成" : "编辑功能") {
                withAnimation(.smooth(duration: 0.22)) { isEditing.toggle() }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(spec == nil)
            Button("关闭") { dismiss() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(16)
    }

    private var offlineBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.exclamationmark")
            Text("设备离线，控制不可用")
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Button {
                Task { await state.loadDevices() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("重新检测在线状态")
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.orange.opacity(0.12))
    }

    /// 只读传感器离线：没有「控制」概念，只提示未连接、暂不更新数据，不给橙色告警。
    private var sensorOfflineBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.exclamationmark")
            Text("设备未连接，暂不更新数据")
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Button {
                Task { await state.loadDevices() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("重新检测在线状态")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.secondary.opacity(0.1))
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 10) {
                ProgressView()
                Text("正在读取规格与属性…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if spec != nil {
            if keys.isEmpty {
                emptyState
            } else {
                ScrollView {
                    GlassEffectContainer(spacing: 12) {
                        let columns = splitColumns(modules)
                        HStack(alignment: .top, spacing: 14) {
                            VStack(spacing: 12) {
                                ForEach(columns.left, id: \.key) { module in
                                    card(module)
                                }
                            }
                            VStack(spacing: 12) {
                                ForEach(columns.right, id: \.key) { module in
                                    card(module)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text(loadError ?? "该设备未发布功能规格（常见于蓝牙类产品）")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("此设备控制面板还是空的")
                .font(.system(size: 13, weight: .medium))
            Text("点击下方「添加功能」把常用的开关、亮度等加进来")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { showAdd = true } label: { Label("添加功能", systemImage: "plus") }
                .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var modules: [WorkbenchModule] {
        resolver?.modules(for: keys) ?? []
    }

    /// 仅当前可见卡片的标题（同屏重名才带消歧后缀）
    private var displayTitles: [String: String] {
        resolver?.visibleTitles(for: keys) ?? [:]
    }

    @ViewBuilder
    private func card(_ module: WorkbenchModule) -> some View {
        let index = keys.firstIndex(of: module.key) ?? 0
        let base = WorkbenchCardView(
            module: module,
            device: device,
            resolver: resolver,
            displayTitle: displayTitles[module.key],
            isEditing: isEditing,
            isExpanded: expanded.contains(module.key),
            onToggleExpanded: {
                withAnimation(.smooth(duration: 0.22)) {
                    if expanded.contains(module.key) { expanded.remove(module.key) }
                    else { expanded.insert(module.key) }
                }
            },
            onRemove: { remove(module.key) })
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            .glassEffectID(module.key, in: glassNamespace)

        if isEditing {
            base
                .draggable(module.key)
                .dropDestination(for: String.self) { items, _ in
                    guard let key = items.first,
                          let from = keys.firstIndex(of: key),
                          from != index else { return false }
                    state.moveModule(did: device.did, fromIndex: from, toIndex: index)
                    keys = state.workbenchKeys(for: device, spec: spec!)
                    return true
                } isTargeted: { _ in }
        } else {
            base
        }
    }

    // MARK: - 底部

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Button {
                    showAdd = true
                } label: {
                    Label("添加功能", systemImage: "plus")
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(spec == nil)

                Spacer()

                if let error = state.actionError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                } else if isEditing, let spec {
                    Text("共 \(spec.properties.count) 个属性 · \(spec.actions.count) 个动作")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - 数据

    private func load() async {
        isLoading = true
        let spec = await state.spec(for: device)
        self.spec = spec
        guard let spec else {
            loadError = device.specType == nil
                ? "该设备未发布功能规格（常见于蓝牙类产品）"
                : "无法获取设备规格"
            keys = []
            isLoading = false
            return
        }
        syncKeys()
        // 一次批量读取已添加模块涉及的属性，避免逐个往返
        await state.refreshProps(device, modules.flatMap(\.allProperties))
        isLoading = false
    }

    private func add(_ key: String) {
        state.addModule(key, to: device)
        syncKeys()
        Task { await state.refreshProps(device, modules.flatMap(\.allProperties)) }
    }

    private func remove(_ key: String) {
        state.removeModule(key, from: device)
        syncKeys()
    }

    /// 从持久化里重新取一次 key，并让组合卡默认展开（成员直接可见）
    private func syncKeys() {
        guard let spec else { return }
        resolver = WorkbenchResolver(spec: spec)
        keys = state.workbenchKeys(for: device, spec: spec)
        expanded.formUnion(keys.filter { $0.hasPrefix(PropGroup.compositePrefix) })
    }
}
