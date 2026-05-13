# SwiftUI macOS 长列表 Shift 范围选择

## 简介

这个 demo 演示 macOS 长列表里的单选、多选、`Shift+↑` / `Shift+↓` 范围扩选。

重点不是普通 UI，而是两个行为：

1. 范围扩选始终以“首个锚点项”为起点。
2. 最后焦点项离开屏幕时，只做最小滚动把它拉回可视区。

## 快速开始

### 环境要求

- macOS
- Xcode 15+

### 运行

```bash
cd swiftui-macos-long-list-shift-arrow-range-selection-demo
open SwiftUILongListShiftArrowRangeSelectionDemo.xcodeproj
```

或直接：

```bash
cd swiftui-macos-long-list-shift-arrow-range-selection-demo
./dev.sh
```

## 注意事项

- 这个 demo 外层是 SwiftUI，核心列表不是 `SwiftUI.List`，而是包了一层 `NSTableView`。
- 原因很直接：长列表、键盘多选锚点、最小滚动可见，这三件事放在 `NSTableView` 上更稳、更可控。
- 默认数据量是 `20_000` 行，顶部按钮可切到 `2_000` 或 `100_000` 行。

## 教程

### 关键概念

这里有 3 个核心状态：

1. `selectedIDs`
   表示当前哪些项被选中。
2. `focusedID`
   表示“最后操作到哪一项”，也就是滚动要追踪的那一项。
3. `anchorID`
   表示范围选择固定起点。`Shift+↑` / `Shift+↓` 不会改它，只会改范围终点。

### demo 原理

主状态收在 `SelectionDemoStore`。

- 鼠标普通点击 → 单点选择。
- `Cmd+点击` → 增删某项。
- `Shift+点击` → 以 `anchorID` 到当前项做闭区间。
- `Shift+↑` / `Shift+↓` → 以 `anchorID` 为起点，向上或向下扩区。
- 焦点项变化后调用 `NSTableView.scrollRowToVisible`，由系统完成“最小距离滚动到可见区”。

### 关键代码解读

最重要的文件只有两个：

1. `Sources/ContentView.swift`
   这里同时放了 store、SwiftUI 外壳、AppKit 表格桥接层。
2. `Sources/AppMain.swift`
   这里只做窗口装配。

看主链时，顺序建议：

1. 先看 `SelectionDemoStore.handleArrow`
2. 再看 `SelectionDemoStore.applyRange`
3. 再看 `SelectionTableRepresentable.Coordinator.applyStoreState`

这样最快能看懂：

- 选择规则怎么收口
- 焦点怎么移动
- 离屏时为什么会自动回到视口

## 性能观察

当前实现有几个特意的取舍：

1. 行高固定。
2. 单元格文本单行截断。
3. 焦点变化时只局部刷新旧焦点和新焦点两行，不全表 reload。
4. 选择高亮直接走 `NSTableView` 原生能力。

这意味着：

- `20_000` 行通常应很稳。
- `100_000` 行也能跑，但数据模型和字符串本身会占更多内存。
- 如果后续把每一行换成复杂 SwiftUI 视图、动态高度、图片解码，性能瓶颈会更早出现。
