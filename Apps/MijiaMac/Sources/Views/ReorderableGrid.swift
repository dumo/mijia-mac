import SwiftUI

/// iOS 桌面风格的网格拖拽排序：拖动时其余卡片实时让位，被拖卡片跟手移动。
///
/// 不用系统 `.reorderable()`：它在「抬起」时对卡片做快照，玻璃材质与 SwiftUI 绘制的
/// 文字/背景会丢失（只剩 AppKit 控件如 Toggle 可见）。这里用普通手势 + 帧检测，
/// 卡片始终是活视图，所见即所得。
///
/// 关键实现细节：
/// - 帧在 `scaleEffect/offset` **之前**测量，并在手势开始时冻结成「槽位帧」数组。
///   若直接用实时帧，被拖卡片的帧会随 offset 变化，形成「dragOffset ↔ frame」反馈回路而抖动。
/// - 槽位是位置固定的：重排只是内容换槽，槽位坐标不变，所以冻结一次即可，
///   且不受 scale（1.04）对测量的影响。
struct ReorderableGrid<Item: Identifiable, Content: View>: View where Item.ID == String {

    @Binding var items: [Item]
    let columns: [GridItem]
    var spacing: CGFloat = 14
    var liftScale: CGFloat = 1.04
    var onCommit: ([Item]) -> Void = { _ in }
    @ViewBuilder var content: (Item, Bool) -> Content

    /// 实时帧（未拖动时的真实布局帧），仅在手势开始时取样
    @State private var frames: [String: CGRect] = [:]
    /// 手势开始时冻结的槽位帧，按当时的 items 顺序排列
    @State private var slotFrames: [CGRect] = []
    @State private var draggingID: String?
    @State private var dragOffset: CGSize = .zero
    /// 按住点相对卡片左上角的偏移，保证卡片不「跳」到指针中心
    @State private var grabOffset: CGSize = .zero

    private static var space: String { "ReorderableGridSpace" }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            ForEach(items) { item in
                let isDragging = draggingID == item.id
                content(item, isDragging)
                    // 先测量，再变换：测量到的是未缩放、未偏移的布局帧
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: GridFramesKey.self,
                                value: [item.id: proxy.frame(in: .named(Self.space))])
                        }
                    )
                    .scaleEffect(isDragging ? liftScale : 1)
                    .shadow(color: .black.opacity(isDragging ? 0.18 : 0),
                            radius: isDragging ? 16 : 0,
                            y: isDragging ? 8 : 0)
                    .offset(isDragging ? dragOffset : .zero)
                    .zIndex(isDragging ? 1 : 0)
                    // 被拖卡片不做布局动画：它的位置由指针决定，动画会让它跟不上手
                    .transaction { transaction in
                        if isDragging { transaction.animation = nil }
                    }
                    .gesture(dragGesture(for: item))
            }
        }
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(GridFramesKey.self) { frames = $0 }
    }

    // MARK: - 手势

    private func dragGesture(for item: Item) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(Self.space))
            .onChanged { value in
                if draggingID != item.id {
                    draggingID = item.id
                    beginDrag(item: item, startLocation: value.startLocation)
                }
                applyDrag(item: item, location: value.location)
            }
            .onEnded { _ in
                finishDrag()
            }
    }

    /// 冻结槽位帧 + 记录按住点偏移。必须在 scale/offset 生效前的这一帧取样。
    private func beginDrag(item: Item, startLocation: CGPoint) {
        slotFrames = items.map { frames[$0.id] ?? .zero }
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              slotFrames.indices.contains(index) else { return }
        let base = slotFrames[index]
        grabOffset = CGSize(width: startLocation.x - base.minX,
                            height: startLocation.y - base.minY)
    }

    private func applyDrag(item: Item, location: CGPoint) {
        guard let from = items.firstIndex(where: { $0.id == item.id }),
              slotFrames.count == items.count,
              slotFrames.indices.contains(from) else { return }
        let base = slotFrames[from]
        guard !base.isEmpty else { return }

        dragOffset = CGSize(width: location.x - grabOffset.width - base.minX,
                            height: location.y - grabOffset.height - base.minY)

        // 被拖卡片中心落在哪个槽位上，就插到那个位置（iOS 桌面同款判定）
        let center = CGPoint(x: base.midX + dragOffset.width,
                             y: base.midY + dragOffset.height)
        guard let to = slotFrames.indices.first(where: {
            $0 != from && !slotFrames[$0].isEmpty && slotFrames[$0].contains(center)
        }) else { return }

        var updated = items
        updated.move(fromOffsets: IndexSet(integer: from),
                     toOffset: to > from ? to + 1 : to)
        withAnimation(.smooth(duration: 0.2)) { items = updated }
    }

    private func finishDrag() {
        guard draggingID != nil else { return }
        let ordered = items
        draggingID = nil
        dragOffset = .zero
        grabOffset = .zero
        slotFrames = []
        onCommit(ordered)
    }
}

private struct GridFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}
