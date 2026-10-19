import SwiftUI
import MijiaCore

/// 设置页：外观、开机自启、隐藏场景入口、默认小爱音箱、版本检测。
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @State private var checking = false

    var body: some View {
        @Bindable var settings = state.settings
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                menuBarSection
                traySection
                generalSection
                speakerSection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .onChange(of: settings.colorScheme) {
                settings.applyAppearance()
                settings.save()
            }
            .onChange(of: settings.hideScenes) { settings.save() }
            .onChange(of: settings.defaultSpeakerDid) { settings.save() }
            .onChange(of: settings.menuBarTitleMode) {
                settings.save()
                state.restartMenuBarClimateUpdates()
                if settings.menuBarTitleMode == .climate {
                    Task { await state.loadClimateCandidates() }
                }
            }
            .onChange(of: settings.climateDeviceDid) {
                settings.save()
                state.restartMenuBarClimateUpdates()
            }
            .task { await state.loadClimateCandidates() }
        }
        .tint(Color.mijiaGreen)
    }

    // MARK: - 账号

    private var accountSection: some View {
        Section("账号") {
            HStack {
                Text("登录状态")
                Spacer()
                if let id = state.accountId {
                    Label("已登录 (\(id))", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(Color.mijiaGreen)
                } else {
                    Text("未登录").foregroundStyle(.secondary)
                }
            }
            if state.accountId != nil {
                Button {
                    Task { await state.logout() }
                } label: {
                    Label("退出登录 / 切换账号", systemImage: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        @Bindable var settings = state.settings
        return Section("外观") {
            Picker("主题", selection: $settings.colorScheme) {
                ForEach(SettingsStore.ColorSchemeMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - 菜单栏

    private var menuBarSection: some View {
        @Bindable var settings = state.settings
        return Section {
            Picker("文字", selection: $settings.menuBarTitleMode) {
                ForEach(SettingsStore.MenuBarTitleMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            if settings.menuBarTitleMode == .climate {
                if state.isLoadingClimateCandidates {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在查找可提供温湿度的设备…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else if state.climateCandidates.isEmpty {
                    Text("未找到可读取温湿度的设备。请确认设备支持温度 / 湿度属性。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Picker("温湿度来源", selection: $settings.climateDeviceDid) {
                        Text("未选择").tag(String?.none)
                        ForEach(state.climateCandidates) { device in
                            Text(device.name).tag(String?.some(device.did))
                        }
                    }
                }
            }
        } header: {
            Text("菜单栏")
        } footer: {
            Text("菜单栏图标旁显示的内容；选择温湿度时格式为「23°｜70%」。")
                .font(.system(size: 11))
        }
    }

    // MARK: - 状态栏菜单条目

    private var traySection: some View {
        Section {
            NavigationLink("自定义菜单条目…") {
                TrayItemsSettingsView()
                    .environment(state)
            }
            Button("恢复默认卡片顺序") {
                Task { await state.resetDeviceOrder() }
            }
            .help("清除拖拽产生的顺序，按云端返回的设备顺序重新排列")
        } header: {
            Text("状态栏菜单")
        } footer: {
            Text("勾选要在状态栏菜单中显示的设备与场景；未自定义时按设备顺序显示前 8 个。")
                .font(.system(size: 11))
        }
    }

    // MARK: - 通用

    private var generalSection: some View {
        @Bindable var settings = state.settings
        return Section("通用") {
            Toggle("开机自动启动", isOn: launchBinding)
            Toggle("隐藏「场景」入口", isOn: $settings.hideScenes)
        }
    }

    private var launchBinding: Binding<Bool> {
        .init(
            get: { state.settings.launchAtLogin },
            set: { newValue in
                state.settings.setLaunchAtLogin(newValue)
            })
    }

    // MARK: - 小爱语音

    private var speakerSection: some View {
        @Bindable var settings = state.settings
        return Section {
            if state.speakerCandidates.isEmpty {
                Text("未发现在线的小爱音箱。请确认音箱已联网并在米家 App 中可见。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("默认输出音箱", selection: $settings.defaultSpeakerDid) {
                    Text("未指定").tag(String?.none)
                    ForEach(state.speakerCandidates) { device in
                        Text(device.name).tag(String?.some(device.did))
                    }
                }
            }
        } header: {
            Text("小爱语音")
        } footer: {
            Text("发文字指令给小爱时使用的默认设备。")
                .font(.system(size: 11))
        }
    }

    // MARK: - 关于 / 版本

    private var aboutSection: some View {
        @Bindable var settings = state.settings
        return Section("关于") {
            HStack {
                Text("当前版本")
                Spacer()
                Text(state.currentVersion)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await check() }
            } label: {
                if checking {
                    HStack { ProgressView().controlSize(.small); Text("正在检查…") }
                } else {
                    Text("检查更新")
                }
            }
            .disabled(checking)

            if let latest = settings.latestVersion {
                HStack {
                    Text("最新版本")
                    Spacer()
                    Text(latest).foregroundStyle(.secondary)
                }
                if state.hasUpdate {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(Color.mijiaGreen)
                        Text("发现新版本，可前往 GitHub Releases 下载")
                            .foregroundStyle(Color.mijiaGreen)
                        Spacer()
                    }
                    .font(.system(size: 11.5))
                }
            }

            if let date = settings.lastVersionCheckAt {
                HStack {
                    Text("上次检查")
                    Spacer()
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11))
            }

            if let url = URL(string: "https://github.com/\(AppState.githubRepo)") {
                Link("项目仓库", destination: url)
                    .font(.system(size: 12))
            }
        }
    }

    private func check() async {
        checking = true
        await state.checkForUpdate()
        checking = false
    }
}
