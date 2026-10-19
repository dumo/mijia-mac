import SwiftUI
import MijiaCore

/// 属性 / 动作 → 控件 的工厂。
///
/// spec 决定控件形态：bool → 开关，数值 → 滑块（严格套 value-range 的 step），
/// 带 value-list → 少量选项用按钮、多选项用菜单，string → 输入框，其余只读展示。
/// 所有控件在设备离线时整体禁用，避免点一下换来一个 `-704042011`。

enum PropText {
    /// 卡片标题：只给人看中文
    static func title(_ prop: DevProp) -> String {
        DeviceNaming.chineseTitle(desc: prop.desc, fallbackName: prop.name)
    }

    static func title(_ action: DevAction) -> String {
        DeviceNaming.chineseTitle(desc: action.desc, fallbackName: action.name)
    }

    /// 技术名（去重后缀、副标题用）
    static func technical(_ prop: DevProp) -> String {
        DeviceNaming.englishTitle(desc: prop.desc, fallbackName: prop.name)
    }

    /// 当前值的展示文案
    static func display(_ value: JSONValue?, prop: DevProp) -> String {
        guard let value else { return "—" }
        if case .null = value { return "—" }
        if prop.type == "bool" { return value.boolValue == true ? "开" : "关" }

        // 枚举值尽量显示选项的中文描述
        if let list = prop.valueList, !list.isEmpty {
            for option in list where WriteGuard.looseEqual(option.value, value) {
                let text = chineseTitle(of: option.desc)
                return text.isEmpty ? (value.stringValue ?? "—") : text
            }
        }
        if prop.isNumeric, let number = value.doubleValue {
            return NumericRange(prop: prop).text(number)
        }
        return value.stringValue ?? "—"
    }

    /// value-list 的描述形如 `"Auto / 自动"`，取中文
    static func chineseTitle(of desc: String) -> String {
        DeviceNaming.chineseTitle(desc: desc, fallbackName: "")
    }

    static func optionTitle(_ option: ValueOption) -> String {
        let text = chineseTitle(of: option.desc)
        return text.isEmpty ? (option.value.stringValue ?? "—") : text
    }
}

// MARK: - 属性控件

struct PropControlView: View {
    let prop: DevProp
    let value: JSONValue?
    let isOnline: Bool
    let isPending: Bool
    /// 组合卡成员行等窄容器：按钮放不下时更早退回菜单。
    var compact: Bool = false
    let onCommit: (JSONValue) async -> Void

    @State private var sliderValue: Double = 0
    @State private var textDraft: String = ""

    var body: some View {
        Group {
            if isPending {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 44, alignment: .leading)
            } else if !prop.isWritable {
                readOnlyText
            } else if prop.type == "bool" {
                toggle
            } else if let list = prop.valueList, !list.isEmpty {
                enumControl(list)
            } else if prop.isNumeric {
                slider
            } else if prop.type == "string" {
                textField
            } else {
                readOnlyText
            }
        }
        .disabled(!isOnline)
        .help(helpText)
    }

    private var helpText: String {
        guard !isOnline else { return "" }
        return "设备离线，无法控制"
    }

    private var readOnlyText: some View {
        Text(PropText.display(value, prop: prop))
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(value == nil ? .tertiary : .primary)
            .lineLimit(1)
    }

    private var toggle: some View {
        Toggle("", isOn: Binding(
            get: { value?.boolValue ?? false },
            set: { newValue in Task { await onCommit(.bool(newValue)) } }))
        .labelsHidden()
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    // MARK: 枚举：少量选项用按钮

    @ViewBuilder
    private func enumControl(_ list: [ValueOption]) -> some View {
        if prefersButtons(list) {
            enumButtons(list)
        } else {
            enumMenu(list)
        }
    }

    /// 2–4 个选项、且估算文字宽度放得下时才用按钮；
    /// 风机档位、扫风角度、输入源等选项多的仍保持菜单。
    private func prefersButtons(_ list: [ValueOption]) -> Bool {
        guard (2...4).contains(list.count) else { return false }
        return estimatedButtonWidth(list) <= (compact ? 190 : 300)
    }

    private func estimatedButtonWidth(_ list: [ValueOption]) -> CGFloat {
        let widths = list.map { option -> CGFloat in
            let textWidth = PropText.optionTitle(option).reduce(CGFloat(0)) { partial, character in
                partial + (character.isASCII ? 6.5 : 11.5)
            }
            return textWidth + 20
        }
        return widths.reduce(0, +) + CGFloat(max(0, list.count - 1)) * 4
    }

    private func enumButtons(_ list: [ValueOption]) -> some View {
        HStack(spacing: 4) {
            ForEach(list, id: \.value) { option in
                let isSelected = value.map { WriteGuard.looseEqual(option.value, $0) } ?? false
                Button {
                    Task { await onCommit(option.value) }
                } label: {
                    Text(PropText.optionTitle(option))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(PropText.optionTitle(option))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func enumMenu(_ list: [ValueOption]) -> some View {
        Menu {
            ForEach(list, id: \.value) { option in
                Button(PropText.optionTitle(option)) {
                    Task { await onCommit(option.value) }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(PropText.display(value, prop: prop))
                    .font(.system(size: 11, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var slider: some View {
        let spec = NumericRange(prop: prop)
        let lower = min(spec.min, spec.max)
        let upper = max(spec.min, spec.max)
        return HStack(spacing: 8) {
            Slider(value: $sliderValue,
                   in: lower...upper,
                   step: spec.step > 0 ? spec.step : 1) { editing in
                guard !editing else { return }
                let snapped = spec.jsonValue(sliderValue)
                Task { await onCommit(snapped) }
            }
            .frame(minWidth: 84)
            Text(spec.text(sliderValue))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
        .onAppear { sliderValue = value?.doubleValue ?? spec.min }
        .onChange(of: value?.doubleValue) { _, newValue in
            if let newValue { sliderValue = newValue }
        }
    }

    private var textField: some View {
        TextField("输入", text: $textDraft, onCommit: {
            Task { await onCommit(.string(textDraft)) }
        })
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11))
        .frame(minWidth: 96)
        .onAppear { textDraft = value?.stringValue ?? "" }
    }
}

// MARK: - 动作控件

struct ActionControlView: View {
    let action: DevAction
    let isOnline: Bool
    let onRun: (String?) async -> Void

    @State private var isRunning = false
    @State private var text = ""

    private var wantsText: Bool { DeviceNaming.needsText(action.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if wantsText {
                TextField("输入文本", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }
            Button {
                guard !isRunning else { return }
                isRunning = true
                Task {
                    await onRun(wantsText ? text : nil)
                    isRunning = false
                }
            } label: {
                Text(isRunning ? "执行中…" : "执行")
                    .frame(minWidth: 44)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(!isOnline || isRunning)
            .help(isOnline ? "" : "设备离线，无法控制")
        }
    }
}
