import SwiftUI
import MijiaCore

/// 添加功能抽屉：列出该设备全部属性（组合卡在前）与动作，已添加的置灰打勾。
struct AddFeatureSheet: View {
    @Environment(\.dismiss) private var dismiss

    let spec: DeviceSpec
    let addedKeys: Set<String>
    let onAdd: (String) -> Void

    /// 规格解析器只建一次（86 个属性的设备重算字典很浪费）
    private let resolver: WorkbenchResolver

    @State private var query = ""

    init(spec: DeviceSpec, addedKeys: Set<String>, onAdd: @escaping (String) -> Void) {
        self.spec = spec
        self.addedKeys = addedKeys
        self.onAdd = onAdd
        self.resolver = WorkbenchResolver(spec: spec)
    }

    private var filtered: [WorkbenchModule] {
        let all = resolver.addable
        let keyword = query.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return all }
        return all.filter {
            resolver.title(for: $0.key).localizedCaseInsensitiveContains(keyword)
                || $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.key.localizedCaseInsensitiveContains(keyword)
                || $0.subtitle.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var properties: [WorkbenchModule] { filtered.filter { !$0.isAction } }
    private var actions: [WorkbenchModule] { filtered.filter(\.isAction) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("添加功能")
                        .font(.headline)
                    Text(spec.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
            .padding(16)

            searchBar

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    if properties.isEmpty && actions.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .padding(.top, 40)
                    }
                    if !properties.isEmpty {
                        sectionHeader("属性", count: properties.count)
                        ForEach(properties) { row($0) }
                    }
                    if !actions.isEmpty {
                        sectionHeader("动作", count: actions.count)
                        ForEach(actions) { row($0) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("共 \(resolver.addable.count) 项可用功能，添加后可在工作台里拖动排序")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .frame(width: 470, height: 560)
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("搜索功能", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11.5, weight: .semibold))
            Text("\(count)").font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private func row(_ module: WorkbenchModule) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(resolver.title(for: module.key))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                Text(module.subtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if addedKeys.contains(module.key) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("已添加")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Button("添加") { onAdd(module.key) }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 9))
        .padding(.vertical, 2)
    }
}

private extension WorkbenchModule {
    var isAction: Bool {
        if case .action = self { return true }
        return false
    }
}
