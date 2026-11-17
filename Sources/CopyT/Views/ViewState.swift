import Foundation

// 说明：新版 SDK 中 SwiftUI 的 @State 由宏实现，而宏插件只随完整 Xcode 提供，
// 只装 Command Line Tools 时无法编译。因此本项目不使用 @State / @StateObject，
// 所有界面状态都放在下面这些 ObservableObject 中，由 AppDelegate 创建并通过
// @EnvironmentObject 注入。

/// 菜单栏弹窗的界面状态（每次打开弹窗重新创建）
@MainActor
final class PopoverState: ObservableObject {
    @Published var query = ""
    @Published var results: [ClipItem] = []
    @Published var hoveredID: ClipItem.ID?
}

/// 历史窗口的界面状态
@MainActor
final class HistoryState: ObservableObject {
    @Published var selection = Set<ClipItem.ID>()
    @Published var exportMessage: String?
    /// 刚刚在详情页点了"复制"的记录
    @Published var copiedID: ClipItem.ID?
}

/// 设置窗口的界面状态
@MainActor
final class SettingsState: ObservableObject {
    @Published var launchAtLogin = LaunchAtLogin.isEnabled
    @Published var moveExisting = true
    @Published var storageSize: Int64?
    @Published var message: String?
    @Published var confirmClear = false
}
