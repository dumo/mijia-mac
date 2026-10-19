import SwiftUI
import MijiaCore

/// 主窗口右下角常驻的小爱语音浮窗：点开输入文字，发给设置里指定的默认音箱。
struct XiaoAIVoiceView: View {
    @Environment(AppState.self) private var state
    @State private var expanded = false
    @State private var text = ""
    @State private var isSending = false
    @State private var feedback: String?

    private var speaker: MiDevice? { state.defaultSpeaker }

    var body: some View {
        @Bindable var state = state
        VStack(alignment: .trailing, spacing: 10) {
            if expanded { panel }
            floatingButton
        }
        .padding(14)
    }

    private var floatingButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                expanded.toggle()
            }
        } label: {
            Image(systemName: expanded ? "xmark" : "waveform")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.mijiaGreen))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("小爱语音")
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.mijiaGreen)
                Text("小爱同学")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            if let speaker {
                Text("发送给：\(speaker.name)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("未指定默认音箱，请在设置里选择")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            TextField("说点什么，例如：把客厅灯调到暖光", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .disabled(isSending || speaker == nil)

            if let feedback {
                Text(feedback)
                    .font(.system(size: 10.5))
                    .foregroundStyle(feedback.contains("失败") || feedback.contains("请") ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button {
                    Task { await send() }
                } label: {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("发送", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isSending || speaker == nil || text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .overlay(.thinMaterial, in: .rect(cornerRadius: 16).stroke(lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }

    private func send() async {
        guard let device = speaker else {
            feedback = "请先在设置里指定默认音箱"
            return
        }
        let directive = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directive.isEmpty else { return }

        isSending = true
        feedback = nil
        defer { isSending = false }

        // 找该设备的文本指令动作（execute-text-directive 等）
        guard let spec = await state.spec(for: device) else {
            feedback = "无法获取音箱能力，稍后重试"
            return
        }
        guard let action = spec.actions.first(where: { DeviceNaming.needsText($0.name) }) else {
            feedback = "该音箱不支持文本指令"
            return
        }
        let ok = await state.runAction(device, action, text: directive)
        if ok {
            feedback = "已发送"
            text = ""
        } else {
            feedback = state.actionError ?? "发送失败"
        }
    }
}
