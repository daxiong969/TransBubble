import AppIntents
import UIKit

// MARK: - 「翻译截图」快捷指令（推荐主入口）
// 配合系统「截图」动作使用：快捷指令 = [截图] → [翻译截图（译拍通）]
// 可绑定：辅助触控（小白点）/ 轻点背面 / Siri / 动作按钮。
// 触发后：小白点单击 → 系统截取当前页面 → 图片传入本 Intent → 打开 App 直接显示译文叠加。
struct TranslateScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "翻译截图"
    static var description: IntentDescription = .init(
        "接收截图并 OCR 识别文字，翻译成中文（或您设置的目标语言）。\n\n推荐用法：在快捷指令中先添加「截图」动作，再把其输出连接到本动作，然后绑定到辅助触控（小白点）或轻点背面。"
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "截图", description: "要翻译的截图图片", requestValueDialog: "请提供要翻译的截图")
    var image: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 设置页可关闭外部触发
        let allowed = UserDefaults.standard.bool(forKey: "allowIntentTrigger_set")
        let realAllowed = UserDefaults.standard.object(forKey: "allowIntentTrigger") == nil ? true : allowed
        guard realAllowed else {
            return .result(dialog: "译拍通已关闭外部触发，请到 App 设置中开启。")
        }
        // 图片写入待处理文件，App 回前台后立即消费并弹出译文
        PendingImageStore.saveData(image.data)
        return .result(dialog: "已收到截图，正在打开译拍通翻译…")
    }
}

// MARK: - 「打开译拍通选图翻译」快捷指令（辅助入口）
// 不带参数：打开 App 并自动弹出相册选图（PHPicker），把已截图/已保存的图片拿来翻译。
struct SnapTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "选图翻译"
    static var description: IntentDescription = .init(
        "打开译拍通并弹出相册选图，选择一张截图进行 OCR 识别和翻译。"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "pendingOpenPicker")
        return .result()
    }
}

// MARK: - App 快捷方式（长按图标 / Siri 可见）
struct SnapTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SnapTranslateIntent(),
            phrases: ["用\(.applicationName)截图翻译", "用\(.applicationName)翻译截图"],
            shortTitle: "截图翻译",
            systemImageName: "camera.viewfinder"
        )
    }
}
