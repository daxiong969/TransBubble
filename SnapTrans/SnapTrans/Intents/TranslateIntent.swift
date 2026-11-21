import AppIntents
import UIKit

// MARK: - 「一键截图翻译」快捷指令
// 可在系统快捷指令 App 中添加，并可在「辅助触控（小白点）」自定义菜单绑定触发。
// 触发逻辑：打开 App 并置位触发标记 → 主页面 onAppear 消费 → 截图一次 → OCR → 翻译。
struct SnapTranslateIntent: AppIntent {
    static var title: LocalizedStringResource = "一键截图翻译"
    static var description: IntentDescription = .init(
        "截取当前屏幕一帧，OCR 识别文字并翻译成中文（或您设置的目标语言）。可在辅助触控（小白点）自定义菜单中绑定。"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // 设置页可关闭外部触发
        let allowed = UserDefaults.standard.bool(forKey: "allowIntentTrigger_set") // 默认 true 处理
        let realAllowed = UserDefaults.standard.object(forKey: "allowIntentTrigger") == nil ? true : allowed
        if realAllowed {
            UserDefaults.standard.set(true, forKey: "pendingIntentTrigger")
        }
        return .result()
    }
}

// MARK: - App 快捷方式（App Shortcut，长按图标可见）
struct SnapTranslateShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SnapTranslateIntent(),
            phrases: ["用\(.applicationName)截图翻译"],
            shortTitle: "截图翻译",
            systemImageName: "camera.viewfinder"
        )
    }
}
