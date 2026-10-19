import SwiftUI
import MijiaCore

/// 工作台里的一张功能卡。
///
/// - 组合卡：标题是主开关，右侧直接给开关，展开后列出同服务的其它成员
/// - 单属性卡：标题 + 副标题（技术名/类型/范围）+ 控件
/// - 动作卡：标题 + 执行按钮（文本类动作带输入框）
struct WorkbenchCardView: View {
    @Environment(AppState.self) private var state

    let module: WorkbenchModule
    let device: MiDevice
    /// 用来取消歧后的展示标题；为空时退回模块自带标题
    var resolver: WorkbenchResolver? = nil
    /// 当前可见范围内的标题（同屏重名才带后缀）
    var displayTitle: String? = nil
    var isEditing: Bool = false
    var isExpanded: Bool = false
    var onToggleExpanded: () -> Void = {}
    var onRemove: () -> Void = {}

    /// 单卡统一高度：标题一行 + 控件一行，避免卡片高低不齐。
    private static let fixedHeight: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if isComposite {
                if isExpanded {
                    Divider().opacity(0.4)
                    members
                }
            } else {
                controlRow
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: isFixedHeight ? Self.fixedHeight : nil, alignment: .leading)
        .animation(.smooth(duration: 0.22), value: isExpanded)
    }

    private var isComposite: Bool { module.isComposite }

    /// 组合卡按成员数自适应；带文本输入的动作卡也自适应，避免固定高度装不下。
    private var isFixedHeight: Bool {
        switch module {
        case .group:
            return false
        case .prop:
            return true
        case .action(let action):
            return !DeviceNaming.needsText(action.name)
        }
    }

    /// 两行结构的第二行：布尔开关靠右，其它控件占满整行。
    @ViewBuilder
    private var controlRow: some View {
        if case .prop(let prop) = module, prop.type == "bool" {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                bodyControl
            }
        } else {
            bodyControl
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // 非编辑态用不带消歧后缀的简明标题；编辑态才显示 `(属性名)` 后缀。
                Text(isEditing
                     ? (resolver?.title(for: module.key) ?? module.title)
                     : (displayTitle ?? module.title))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if isEditing {
                    Text(headerSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)

            if isEditing {
                HStack(spacing: 7) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .help("拖动排序")
                    Button { onRemove() } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("从工作台移除")
                }
            } else {
                // 组合卡：主开关放在头部；单属性卡的开关走第二行控件区
                if isComposite, let master = module.master, master.type == "bool" {
                    PropControlView(prop: master,
                                    value: state.value(master, of: device),
                                    isOnline: device.isOnline,
                                    isPending: state.isPending(master, of: device)) { value in
                        await state.writeProp(device, master, value: value)
                    }
                    .fixedSize()
                }
                if isComposite {
                    Button { onToggleExpanded() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "收起" : "展开")
                }
            }
        }
        .animation(.smooth(duration: 0.22), value: isExpanded)
    }

    private var headerSubtitle: String { module.subtitle }

    // MARK: - 卡片主体

    @ViewBuilder
    private var bodyControl: some View {
        switch module {
        case .group:
            EmptyView()
        case .prop(let prop):
            PropControlView(prop: prop,
                            value: state.value(prop, of: device),
                            isOnline: device.isOnline,
                            isPending: state.isPending(prop, of: device)) { value in
                await state.writeProp(device, prop, value: value)
            }
        case .action(let action):
            ActionControlView(action: action, isOnline: device.isOnline) { text in
                await state.runAction(device, action, text: text)
            }
        }
    }

    /// 展开后显示的成员：主开关已经在头部时不再重复
    private var displayedMembers: [DevProp] {
        guard case .group(let group) = module else { return [] }
        if let master = group.master, master.type == "bool" {
            return group.members.filter { $0.id != master.id }
        }
        return group.members
    }

    private var members: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(displayedMembers) { prop in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(isEditing
                             ? (resolver?.title(forProp: prop) ?? PropText.title(prop))
                             : PropText.title(prop))
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        // 成员行很窄，用紧凑元信息（16-30 / 4 选项），开关类不占这行；
                        // 非编辑态隐藏，降低噪声（范围/选项由控件本身表达）。
                        let meta = DeviceNaming.compactMeta(prop)
                        if isEditing, !meta.isEmpty {
                            Text(meta)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    PropControlView(prop: prop,
                                    value: state.value(prop, of: device),
                                    isOnline: device.isOnline,
                                    isPending: state.isPending(prop, of: device),
                                    compact: true) { value in
                        await state.writeProp(device, prop, value: value)
                    }
                    .fixedSize()
                }
            }
        }
    }
}
