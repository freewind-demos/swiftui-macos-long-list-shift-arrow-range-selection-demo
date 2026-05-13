import AppKit
import Observation
import SwiftUI

// 选择模式。
enum SelectionMode: String, CaseIterable, Identifiable {
    // 单选模式。
    case single = "单选"
    // 多选模式。
    case multiple = "多选"

    // 供 Picker 识别稳定 id。
    var id: Self { self }

    // 映射到底层表格是否允许多选。
    var allowsMultipleSelection: Bool { self == .multiple }
}

// 列表项模型。
struct DemoItem: Identifiable, Hashable {
    // 直接用行号做 id，避免额外映射。
    let id: Int
    // 主标题。
    let title: String
    // 补充信息。
    let detail: String

    // 生成大量稳定测试数据。
    static func makeItems(count: Int) -> [DemoItem] {
        // 一次性生成固定数据，便于性能观察。
        (0..<count).map { index in
            // 构造可读文本。
            DemoItem(
                id: index,
                title: String(format: "Item %05d", index),
                detail: "group \(index / 50) · payload \(index % 11) · hash \(index * 31 % 997)"
            )
        }
    }
}

// 主状态收口。
@Observable
final class SelectionDemoStore {
    // 当前数据集。
    private(set) var items: [DemoItem]
    // 当前模式。
    var selectionMode: SelectionMode {
        didSet {
            // 切模式时压平非法选择。
            normalizeSelectionForMode()
        }
    }
    // 当前选中集合。
    var selectedIDs: Set<Int>
    // 当前焦点项。
    var focusedID: Int?
    // Shift 范围锚点。
    var anchorID: Int?
    // 当前数据量。
    var datasetSize: Int
    // 最近一次动作说明。
    var lastAction: String

    // 初始化默认数据。
    init() {
        // 默认直接给 2w 行，便于压测。
        let initialCount = 20_000
        // 生成默认数据。
        self.items = DemoItem.makeItems(count: initialCount)
        // 默认开多选，更贴近需求。
        self.selectionMode = .multiple
        // 默认焦点放在中段，方便试滚动。
        self.selectedIDs = [10_000]
        // 初始焦点。
        self.focusedID = 10_000
        // 初始锚点。
        self.anchorID = 10_000
        // 记录数据量。
        self.datasetSize = initialCount
        // 首次动作说明。
        self.lastAction = "初始选中 10000"
    }

    // 当前选中个数。
    var selectedCount: Int { selectedIDs.count }

    // 选中项预览。
    var selectionPreview: String {
        // 没选中时直接给占位。
        guard !selectedIDs.isEmpty else { return "无" }
        // 只展示前几项，避免状态栏过长。
        let preview = selectedIDs.sorted().prefix(8).map(String.init).joined(separator: ", ")
        // 选中太多时补省略号。
        let suffix = selectedIDs.count > 8 ? " ..." : ""
        // 拼接最终文案。
        return preview + suffix
    }

    // 焦点项描述。
    var focusedDescription: String {
        // 无焦点时给占位。
        guard let focusedID else { return "无" }
        // 直接展示数字 id。
        return String(focusedID)
    }

    // 锚点描述。
    var anchorDescription: String {
        // 无锚点时给占位。
        guard let anchorID else { return "无" }
        // 直接展示数字 id。
        return String(anchorID)
    }

    // 重建数据集。
    func rebuildItems(count: Int) {
        // 避免重复生成相同数据。
        guard count != datasetSize else { return }
        // 生成新数据。
        items = DemoItem.makeItems(count: count)
        // 更新数据量。
        datasetSize = count
        // 选中中间位置，方便继续试。
        let middleID = max(0, count / 2)
        // 重置为单点选择。
        selectedIDs = [middleID]
        // 更新焦点。
        focusedID = middleID
        // 更新锚点。
        anchorID = middleID
        // 记录动作。
        lastAction = "重建 \(count) 行并选中 \(middleID)"
    }

    // 处理鼠标点选。
    func handleRowClick(id: Int, modifiers: NSEvent.ModifierFlags) {
        // 单选模式全部收敛到单点选择。
        if selectionMode == .single {
            selectOnly(id: id, reason: "单选点选")
            return
        }

        // Shift 点选走范围选择。
        if modifiers.contains(.shift) {
            selectRange(to: id, reason: "Shift+点选")
            return
        }

        // Cmd 点选走增删选择。
        if modifiers.contains(.command) {
            toggleSelection(id: id)
            return
        }

        // 普通点选重置为单点。
        selectOnly(id: id, reason: "点选")
    }

    // 处理方向键。
    func handleArrow(direction: Int, extendingRange: Bool) {
        // 空数据直接返回。
        guard !items.isEmpty else { return }
        // 以当前焦点为起点。
        let startID = focusedID ?? anchorID ?? 0
        // 计算下一行。
        let nextID = clampedID(startID + direction)
        // 识别动作名称。
        let moveName = direction > 0 ? "下" : "上"

        // 多选模式且按住 Shift 时，固定锚点扩范围。
        if selectionMode == .multiple, extendingRange {
            // 若此前没锚点，则把当前焦点固化成锚点。
            if anchorID == nil {
                anchorID = startID
            }
            // 用锚点到目标行形成闭区间选择。
            applyRange(from: anchorID ?? nextID, to: nextID, reason: "Shift+\(moveName)")
            return
        }

        // 非 Shift 方向键重置成单点选择。
        selectOnly(id: nextID, reason: "\(moveName)移")
    }

    // 直接跳到指定行。
    func jump(to id: Int) {
        // 空数据时忽略。
        guard !items.isEmpty else { return }
        // 对齐到合法范围。
        let targetID = clampedID(id)
        // 选中目标行。
        selectOnly(id: targetID, reason: "跳到 \(targetID)")
    }

    // 清空选择。
    func clearSelection() {
        // 清空集合。
        selectedIDs.removeAll()
        // 清空焦点。
        focusedID = nil
        // 清空锚点。
        anchorID = nil
        // 记录动作。
        lastAction = "清空选择"
    }

    // 单点选择。
    private func selectOnly(id: Int, reason: String) {
        // 覆盖成单元素集合。
        selectedIDs = [id]
        // 焦点落在当前项。
        focusedID = id
        // 锚点也重置到当前项。
        anchorID = id
        // 记录动作。
        lastAction = reason
    }

    // 切换某一项选中态。
    private func toggleSelection(id: Int) {
        // 已选中则移除。
        if selectedIDs.contains(id) {
            // 删除当前项。
            selectedIDs.remove(id)
            // 焦点仍指向刚操作的项。
            focusedID = id
            // 如果锚点被删掉，则把锚点迁到最小剩余项。
            if anchorID == id {
                anchorID = selectedIDs.sorted().first
            }
            // 如果已空，则顺带清掉焦点。
            if selectedIDs.isEmpty {
                focusedID = nil
                anchorID = nil
            }
            // 记录动作。
            lastAction = "Cmd+点选取消 \(id)"
            return
        }

        // 未选中则加入集合。
        selectedIDs.insert(id)
        // 焦点落到当前项。
        focusedID = id
        // 首次多选保留首个锚点。
        if anchorID == nil {
            anchorID = id
        }
        // 记录动作。
        lastAction = "Cmd+点选加入 \(id)"
    }

    // 以现有锚点扩成范围。
    private func selectRange(to id: Int, reason: String) {
        // 若没锚点，则把当前焦点或当前项当锚点。
        let startAnchorID = anchorID ?? focusedID ?? id
        // 固化锚点。
        anchorID = startAnchorID
        // 应用区间选择。
        applyRange(from: startAnchorID, to: id, reason: reason)
    }

    // 把闭区间刷进选中集合。
    private func applyRange(from startID: Int, to endID: Int, reason: String) {
        // 计算起点。
        let lower = min(startID, endID)
        // 计算终点。
        let upper = max(startID, endID)
        // 直接构造连续 IndexSet。
        selectedIDs = Set(lower...upper)
        // 焦点移动到区间末端。
        focusedID = endID
        // 锚点保持不变。
        anchorID = startID
        // 记录动作。
        lastAction = "\(reason) \(startID) -> \(endID)"
    }

    // 模式变更后的收敛。
    private func normalizeSelectionForMode() {
        // 单选模式只保留焦点项。
        if selectionMode == .single {
            // 有焦点就保留焦点。
            if let focusedID {
                selectedIDs = [focusedID]
                anchorID = focusedID
            } else if let firstID = selectedIDs.sorted().first {
                // 没焦点就保留最小项。
                selectedIDs = [firstID]
                focusedID = firstID
                anchorID = firstID
            }
            // 记录动作。
            lastAction = "切到单选"
            return
        }

        // 多选模式若当前为空，则给一个稳定起点。
        if selectedIDs.isEmpty, !items.isEmpty {
            // 选中当前焦点或首行。
            let fallbackID = focusedID ?? 0
            selectedIDs = [fallbackID]
            focusedID = fallbackID
            anchorID = fallbackID
        }
        // 记录动作。
        lastAction = "切到多选"
    }

    // 约束到合法 id。
    private func clampedID(_ id: Int) -> Int {
        // 空数据时直接给 0。
        guard !items.isEmpty else { return 0 }
        // 压到首尾区间。
        return min(max(id, 0), items.count - 1)
    }
}

// SwiftUI 主界面。
struct ContentView: View {
    // 用 Observation store 集中状态。
    @State private var store = SelectionDemoStore()

    // 模式绑定。
    private var selectionModeBinding: Binding<SelectionMode> {
        // 直接把 store 属性映射给 Picker。
        Binding(
            get: { store.selectionMode },
            set: { store.selectionMode = $0 }
        )
    }

    // 视图主体。
    var body: some View {
        // 顶到底线性排布。
        VStack(spacing: 12) {
            // 顶部控制区。
            headerControls
            // 中间长列表。
            SelectionTableRepresentable(store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 底部状态区。
            footer
        }
        // 整体留白。
        .padding(16)
        // 给窗口一个稳定背景。
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // 顶部控制区。
    private var headerControls: some View {
        // 左右分布控制项。
        VStack(alignment: .leading, spacing: 10) {
            // 第一行。
            HStack(spacing: 12) {
                // 模式切换。
                Picker("选择模式", selection: selectionModeBinding) {
                    // 枚举所有模式。
                    ForEach(SelectionMode.allCases) { mode in
                        // 每个模式一个标签。
                        Text(mode.rawValue).tag(mode)
                    }
                }
                // 用分段控件缩短操作路径。
                .pickerStyle(.segmented)
                // 控件宽度固定，避免挤压后面按钮。
                .frame(width: 180)

                // 数据规模按钮组。
                ControlGroup("数据量") {
                    // 2k 行。
                    Button("2k") { store.rebuildItems(count: 2_000) }
                    // 2w 行。
                    Button("20k") { store.rebuildItems(count: 20_000) }
                    // 10w 行。
                    Button("100k") { store.rebuildItems(count: 100_000) }
                }

                // 分隔空间。
                Spacer()

                // 快速跳转到中段。
                Button("跳中段") { store.jump(to: store.datasetSize / 2) }
                // 快速跳转到尾部。
                Button("跳尾部") { store.jump(to: store.datasetSize - 1) }
                // 清空选择。
                Button("清空") { store.clearSelection() }
            }

            // 第二行操作提示。
            Text("操作：点击列表获得焦点。普通点选 = 单点；Cmd+点选 = 增删；Shift+点选 / Shift+↑ / Shift+↓ = 以首个锚点扩范围。焦点项离屏时，表格只做最小滚动让它回到视口。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // 底部状态区。
    private var footer: some View {
        // 用竖排收拢状态信息。
        VStack(alignment: .leading, spacing: 8) {
            // 分隔线。
            Divider()
            // 第一行核心状态。
            HStack(spacing: 18) {
                // 当前行数。
                Text("rows \(store.datasetSize)")
                // 当前模式。
                Text("mode \(store.selectionMode.rawValue)")
                // 当前选中数量。
                Text("selected \(store.selectedCount)")
                // 当前锚点。
                Text("anchor \(store.anchorDescription)")
                // 当前焦点。
                Text("focus \(store.focusedDescription)")
            }
            .font(.system(.body, design: .monospaced))

            // 第二行预览。
            Text("selection \(store.selectionPreview)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)

            // 第三行最近动作。
            Text("last \(store.lastAction)")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

// AppKit 表格桥接层。
struct SelectionTableRepresentable: NSViewRepresentable {
    // 共享主状态。
    let store: SelectionDemoStore

    // 创建协调器。
    func makeCoordinator() -> Coordinator {
        // coordinator 负责 data source / delegate / 同步。
        Coordinator(parent: self)
    }

    // 创建底层 NSScrollView。
    func makeNSView(context: Context) -> NSScrollView {
        // 外层滚动容器。
        let scrollView = NSScrollView()
        // 开启纵向滚动条。
        scrollView.hasVerticalScroller = true
        // 关闭横向滚动条，宽度自适应。
        scrollView.hasHorizontalScroller = false
        // 表格视图。
        let tableView = SelectionTableView()
        // 绑定 coordinator。
        context.coordinator.tableView = tableView
        // 注册 data source。
        tableView.dataSource = context.coordinator
        // 注册 delegate。
        tableView.delegate = context.coordinator
        // 隐藏表头，突出列表感。
        tableView.headerView = nil
        // 用满单列。
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("main"))
        // 列宽跟着容器走。
        column.resizingMask = .autoresizingMask
        // 把列加入表格。
        tableView.addTableColumn(column)
        // 统一行高，减少布局抖动。
        tableView.rowHeight = 30
        // 开启交替底色，便于观察滚动位置。
        tableView.usesAlternatingRowBackgroundColors = true
        // 允许空选中，便于测试边界。
        tableView.allowsEmptySelection = true
        // 让多选能力受模式控制。
        tableView.allowsMultipleSelection = store.selectionMode.allowsMultipleSelection
        // 关闭列选择。
        tableView.allowsColumnSelection = false
        // 用常规选择高亮。
        tableView.selectionHighlightStyle = .regular
        // 绑定点击回调。
        tableView.onRowClick = { [weak coordinator = context.coordinator] row, modifiers in
            // 交给 store 统一处理。
            coordinator?.handleRowClick(row: row, modifiers: modifiers)
        }
        // 绑定方向键回调。
        tableView.onArrowKey = { [weak coordinator = context.coordinator] direction, extendingRange in
            // 交给 store 统一处理。
            coordinator?.handleArrow(direction: direction, extendingRange: extendingRange)
        }
        // 把表格塞进滚动容器。
        scrollView.documentView = tableView
        // 首次装载后尝试抢焦点。
        DispatchQueue.main.async {
            // 让键盘事件直接进表格。
            scrollView.window?.makeFirstResponder(tableView)
        }
        // 首次同步 store 到视图。
        context.coordinator.applyStoreState()
        // 返回最终控件。
        return scrollView
    }

    // 更新底层视图。
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // 让 coordinator 拿到最新 parent。
        context.coordinator.parent = self
        // 同步最新状态。
        context.coordinator.applyStoreState()
    }

    // 表格协调器。
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        // 最新 parent。
        var parent: SelectionTableRepresentable
        // 表格引用。
        weak var tableView: SelectionTableView?
        // 上次数据量。
        private var lastItemCount: Int = 0
        // 上次焦点，用于局部刷新。
        private var lastFocusedID: Int?

        // 注入 parent。
        init(parent: SelectionTableRepresentable) {
            // 保存 parent。
            self.parent = parent
        }

        // 行数。
        func numberOfRows(in tableView: NSTableView) -> Int {
            // 直接返回数据集大小。
            parent.store.items.count
        }

        // 生成单元格视图。
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            // 取复用标识。
            let identifier = NSUserInterfaceItemIdentifier("LongListCell")
            // 尝试复用已有视图。
            let cell = (tableView.makeView(withIdentifier: identifier, owner: nil) as? ItemCellView) ?? ItemCellView()
            // 写回标识。
            cell.identifier = identifier
            // 取当前项。
            let item = parent.store.items[row]
            // 刷新内容。
            cell.configure(item: item, isFocused: item.id == parent.store.focusedID)
            // 返回视图。
            return cell
        }

        // 处理鼠标点选。
        func handleRowClick(row: Int, modifiers: NSEvent.ModifierFlags) {
            // 交给 store。
            parent.store.handleRowClick(id: row, modifiers: modifiers)
            // 立刻回刷 UI。
            applyStoreState()
        }

        // 处理方向键。
        func handleArrow(direction: Int, extendingRange: Bool) {
            // 交给 store。
            parent.store.handleArrow(direction: direction, extendingRange: extendingRange)
            // 立刻回刷 UI。
            applyStoreState()
        }

        // 把 store 状态同步到底层表格。
        func applyStoreState() {
            // 没表格则直接结束。
            guard let tableView else { return }
            // 模式变化时更新底层能力。
            tableView.allowsMultipleSelection = parent.store.selectionMode.allowsMultipleSelection

            // 数据量变化时全量重载。
            if lastItemCount != parent.store.items.count {
                // 全量刷新。
                tableView.reloadData()
                // 记住最新数量。
                lastItemCount = parent.store.items.count
            } else {
                // 只刷新旧焦点和新焦点两行。
                refreshRows([lastFocusedID, parent.store.focusedID].compactMap { $0 })
            }

            // 把选择集精确同步到表格。
            tableView.selectRowIndexes(IndexSet(parent.store.selectedIDs), byExtendingSelection: false)

            // 焦点项离屏时，用系统最小滚动拉回视口。
            if let focusedID = parent.store.focusedID, focusedID >= 0, focusedID < parent.store.items.count {
                tableView.scrollRowToVisible(focusedID)
            }

            // 更新焦点快照。
            lastFocusedID = parent.store.focusedID
        }

        // 局部刷新若干行。
        private func refreshRows(_ rows: [Int]) {
            // 去重并剔掉非法行。
            let validRows = rows.filter { $0 >= 0 && $0 < parent.store.items.count }
            // 无合法行则直接返回。
            guard !validRows.isEmpty, let tableView else { return }
            // 只刷新一列。
            let columns = IndexSet(integer: 0)
            // 逐行刷新。
            for row in Set(validRows) {
                // 刷这一行。
                tableView.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: columns)
            }
        }
    }
}

// 自定义表格，接管点击与方向键。
final class SelectionTableView: NSTableView {
    // 行点击回调。
    var onRowClick: ((Int, NSEvent.ModifierFlags) -> Void)?
    // 方向键回调。
    var onArrowKey: ((Int, Bool) -> Void)?

    // 允许成为第一响应者。
    override var acceptsFirstResponder: Bool { true }

    // 接管鼠标点击。
    override func mouseDown(with event: NSEvent) {
        // 把窗口坐标转成自身坐标。
        let localPoint = convert(event.locationInWindow, from: nil)
        // 计算命中的行。
        let row = row(at: localPoint)

        // 命中合法行时走自定义选择逻辑。
        if row >= 0, let onRowClick {
            // 抢到焦点，确保后续方向键可用。
            window?.makeFirstResponder(self)
            // 把行号和修饰键抛出去。
            onRowClick(row, event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            return
        }

        // 空白区域交回系统。
        super.mouseDown(with: event)
    }

    // 接管键盘事件。
    override func keyDown(with event: NSEvent) {
        // 取出标准化修饰键。
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 识别是否按着 Shift。
        let extendingRange = modifiers.contains(.shift)

        // 根据 keyCode 识别方向键。
        switch event.keyCode {
        case 125:
            // 下箭头。
            onArrowKey?(1, extendingRange)
        case 126:
            // 上箭头。
            onArrowKey?(-1, extendingRange)
        default:
            // 其他键交回系统。
            super.keyDown(with: event)
        }
    }
}

// 单元格视图。
final class ItemCellView: NSTableCellView {
    // 主文本控件。
    private let label = NSTextField(labelWithString: "")

    // 初始化。
    override init(frame frameRect: NSRect) {
        // 走父类初始化。
        super.init(frame: frameRect)
        // 关自动 mask。
        label.translatesAutoresizingMaskIntoConstraints = false
        // 用等宽字体方便观察行号跳动。
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        // 单行截断，避免超长字符串撑坏布局。
        label.lineBreakMode = .byTruncatingTail
        // 挂到视图树。
        addSubview(label)
        // 约束贴边。
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    // 禁止 storyboard 初始化。
    @available(*, unavailable)
    required init?(coder: NSCoder) {
        // 这个 demo 不走 nib。
        fatalError("init(coder:) has not been implemented")
    }

    // 刷新文本。
    func configure(item: DemoItem, isFocused: Bool) {
        // 焦点项打一个箭头，便于区分“范围末端”。
        let marker = isFocused ? "▶" : " "
        // 拼成稳定单行文本。
        label.stringValue = "\(marker) \(item.title)    \(item.detail)"
    }
}
