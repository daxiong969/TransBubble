import SwiftUI

// MARK: - App 入口（iOS 16+ 兼容）
@main
struct SnapTransApp: App {
    @StateObject private var theme = ThemeManager()
    @StateObject private var flow = AppFlowManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(theme)
                .environmentObject(flow)
                .preferredColorScheme(theme.colorScheme)
        }
    }
}

// MARK: - 主题管理（跟随系统 / 强制浅色 / 强制深色）
final class ThemeManager: ObservableObject {
    @AppStorage("themeMode") var modeRaw: String = "system" // system | light | dark
    var colorScheme: ColorScheme? {
        switch modeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

// MARK: - 全局流程管理：悬浮球 / 快捷指令触发
@MainActor
final class AppFlowManager: ObservableObject {
    /// 快捷指令 / 悬浮球触发时置位，主页面 onAppear 消费
    @Published var pendingCaptureTrigger = false
    /// PiP 悬浮球是否已开启
    @Published var pipActive = false
    /// 悬浮球点击后需要打开的结果页（携带截图）
    @Published var capturedImage: UIImage?
    @Published var showPreview = false
}
