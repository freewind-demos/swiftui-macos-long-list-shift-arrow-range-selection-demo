import SwiftUI

// 应用入口。
@main
struct LongListShiftRangeSelectionApp: App {
    // 主窗口。
    var body: some Scene {
        // 用更直白的标题说明 demo 目标。
        Window("长列表 Shift 范围选择", id: "main") {
            // 挂载主界面。
            ContentView()
        }
        // 给长列表更大的默认空间。
        .defaultSize(width: 960, height: 720)
    }
}
