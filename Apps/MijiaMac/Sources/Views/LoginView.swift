import SwiftUI
import MijiaCore

struct LoginView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 18) {
            Text("扫码登录米家")
                .font(.title2)
                .fontWeight(.semibold)

            Group {
                if let image = state.qrImage {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 230, height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(width: 230, height: 230)
                }
            }

            Text(state.isWaitingForScan ? "请用米家 App 扫描二维码" : "正在准备二维码…")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let url = state.qrImageURL {
                Link("在浏览器中打开二维码", destination: url)
                    .font(.callout)
            }

            if let message = state.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = state.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await state.startLogin() }
            } label: {
                Label("重新获取二维码", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.glass)
            .disabled(state.isWaitingForScan)
        }
        .padding(36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
