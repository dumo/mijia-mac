import SwiftUI
import MijiaCore

struct DeviceCardView: View {
    @Environment(AppState.self) private var state
    let device: MiDevice
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image(systemName: DeviceIcon.systemName(for: device))
                    .font(.system(size: 22))
                    // 不用 .tertiary：在玻璃材质上离线设备的图标几乎不可见
                    .foregroundStyle(device.isOnline ? Color.primary : Color.secondary)
                Spacer(minLength: 0)
                trailingContent
            }
            .padding(.bottom, 10)

            // 名称固定占 2 行高度；超过 2 行则尾部省略号截断。
            Text(device.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            // 在线状态 + 位置：固定在卡片底部。
            HStack(spacing: 5) {
                Circle()
                    .fill(device.isOnline ? Color.green : Color.gray.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let room = device.roomName {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Text(room)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // 只读传感器离线时无「控制不可用」语义，不整体调暗，保留读数参考价值
        .opacity(device.isOnline || state.isReadOnlySensor(device) ? 1 : 0.62)
        .task {
            await state.refreshSwitchState(for: [device])
            if state.isReadOnlySensor(device) {
                await state.refreshSensorReading(for: device)
            }
        }
    }

    /// 状态文案：在线 / 离线；只读传感器离线时显示「未连接」而非「离线」，
    /// 避免误导成「可控设备离线、控制不可用」。
    private var statusText: String {
        if device.isOnline { return "在线" }
        return state.isReadOnlySensor(device) ? "未连接" : "离线"
    }

    /// 卡片右上角内容：可控设备显示开关；只读传感器显示温湿度读数；其它不显示。
    private var sensorReading: AppState.ClimateReading? {
        guard state.isReadOnlySensor(device) else { return nil }
        return state.sensorReadings[device.did]
    }

    @ViewBuilder
    private var trailingContent: some View {
        if state.pendingDevices.contains(device.did) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 22)
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
                .help(device.isOnline ? "点击控制" : "设备离线，无法控制")
        } else if let reading = sensorReading {
            VStack(alignment: .trailing, spacing: 2) {
                if let temperature = reading.temperature {
                    Text(String(format: "%.1f°", temperature))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                if let humidity = reading.humidity {
                    Text(String(format: "%.0f%%", humidity))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        } else if !state.switchUnavailable.contains(device.did) {
            // 还没拿到真实开关值：转圈等待，不要显示成「关」
            ProgressView()
                .controlSize(.small)
                .frame(width: 36, height: 22)
        }
    }
}
