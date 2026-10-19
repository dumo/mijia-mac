import SwiftUI
import MijiaCore

/// 场景列表：展示当前家庭的手动场景，一键执行（执行前二次确认）。
struct ScenesView: View {
    @Environment(AppState.self) private var state
    @State private var runningId: String?

    var body: some View {
        @Bindable var state = state
        Group {
            if state.isLoadingScenes, state.scenes.isEmpty {
                ProgressView("正在加载场景…")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.scenes.isEmpty {
                ContentUnavailableView {
                    Label("暂无场景", systemImage: "sparkles")
                } description: {
                    Text("在米家 App 里创建的手动场景会出现在这里")
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 14)], spacing: 14) {
                        ForEach(state.scenes) { scene in
                            SceneCard(scene: scene, isRunning: runningId == scene.id) {
                                confirmAndRun(scene)
                            }
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle("场景")
        .task { await state.loadScenes() }
        .refreshable { await state.loadScenes() }
    }

    private func confirmAndRun(_ scene: MiScene) {
        // 二次确认，避免误触把家里灯全关了
        let alert = NSAlert()
        alert.messageText = "执行场景「\(scene.name)」？"
        alert.informativeText = "该操作会立即下发到设备，确认继续吗？"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "执行")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        Task {
            runningId = scene.id
            _ = await state.runScene(scene)
            runningId = nil
        }
    }
}

private struct SceneCard: View {
    let scene: MiScene
    let isRunning: Bool
    let onRun: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.mijiaGreen)
                Spacer(minLength: 0)
                if isRunning {
                    ProgressView().controlSize(.small)
                }
            }
            Text(scene.name.isEmpty ? "未命名场景" : scene.name)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                onRun()
            } label: {
                Label("执行", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .disabled(isRunning)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}
