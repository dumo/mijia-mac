import SwiftUI
import MijiaCore

/// 状态栏菜单条目自定义：勾选哪些设备 / 场景出现在菜单里，并调整它们的先后顺序。
///
/// `trayOrder` 非空即为「自定义模式」：菜单只显示这些条目且严格按此顺序；
/// 清空后回到自动模式（按设备稳定顺序取前 8 个 + 全部场景）。
struct TrayItemsSettingsView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Form {
            Section {
                Text("勾选后固定显示在状态栏菜单中，未勾选的不显示；在「已显示」里拖动可调整顺序。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Button("恢复自动选取") {
                    state.settings.trayOrder = []
                    state.settings.save()
                }
                .help("清空自定义，按设备顺序显示前 8 个设备与全部场景")
            }

            Section("已显示（按此顺序）") {
                if selectedItems.isEmpty {
                    Text("未自定义，当前按自动顺序显示")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selectedItems) { item in
                        row(item)
                            .draggable(item.id) {
                                HStack(spacing: 8) {
                                    Image(systemName: item.iconName)
                                        .font(.system(size: 12))
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .dropDestination(for: String.self) { ids, _ in
                                guard let dragged = ids.first, dragged != item.id else { return false }
                                moveSelected(dragged, relativeTo: item.id)
                                return true
                            }
                    }
                }
            }

            Section("设备") {
                ForEach(deviceItems) { item in row(item) }
            }

            if !state.settings.hideScenes {
                Section("场景") {
                    ForEach(sceneItems) { item in row(item) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("状态栏菜单条目")
        .task {
            if state.scenes.isEmpty, let home = state.homes.first {
                await state.loadScenes(homeId: home.id)
            }
        }
    }

    // MARK: - 数据

    private var deviceItems: [TrayItem] { state.devices.map(TrayItem.device) }

    private var sceneItems: [TrayItem] {
        state.settings.hideScenes ? [] : state.scenes.map(TrayItem.scene)
    }

    private var allItems: [TrayItem] { deviceItems + sceneItems }

    private var selectedItems: [TrayItem] {
        let byId = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) })
        return state.settings.trayOrder.compactMap { byId[$0] }
    }

    private func isSelected(_ item: TrayItem) -> Bool {
        state.settings.trayOrder.contains(item.id)
    }

    private func setSelected(_ item: TrayItem, _ selected: Bool) {
        var order = state.settings.trayOrder
        if selected {
            if !order.contains(item.id) { order.append(item.id) }
        } else {
            order.removeAll { $0 == item.id }
        }
        state.settings.trayOrder = order
        state.settings.save()
    }

    /// 已显示列表内拖拽排序：向下拖落在目标之后，向上拖落在目标之前
    private func moveSelected(_ draggedId: String, relativeTo targetId: String) {
        var order = state.settings.trayOrder
        guard let from = order.firstIndex(of: draggedId),
              let targetIndex = order.firstIndex(of: targetId),
              from != targetIndex else { return }
        let moveDown = from < targetIndex
        order.remove(at: from)
        guard let newTarget = order.firstIndex(of: targetId) else { return }
        order.insert(draggedId, at: min(moveDown ? newTarget + 1 : newTarget, order.count))
        state.settings.trayOrder = order
        state.settings.save()
    }

    // MARK: - 行

    private func row(_ item: TrayItem) -> some View {
        Toggle(isOn: Binding(
            get: { isSelected(item) },
            set: { setSelected(item, $0) })) {
            HStack(spacing: 8) {
                Image(systemName: item.iconName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

private extension TrayItem {
    var title: String {
        switch self {
        case .device(let device): device.name
        case .scene(let scene): scene.name.isEmpty ? "未命名场景" : scene.name
        }
    }

    var subtitle: String {
        switch self {
        case .device(let device): device.roomName ?? ""
        case .scene: "场景"
        }
    }

    var iconName: String {
        switch self {
        case .device(let device): DeviceIcon.systemName(for: device)
        case .scene: "sparkles"
        }
    }
}
