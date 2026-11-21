import Foundation
import Translation

// MARK: - 苹果系统翻译服务（Translation 框架，实际 API 需 iOS 18+）
// 说明：TranslationSession 等 API 在 iOS 18.0 才可用，本文件采用"跨版本包装"结构：
// 协调器本体不引用任何高版本符号（可在 iOS 17 上编译），仅 extension 限定 iOS 18+。

// 待翻译项
struct ApplePendingItem {
    let key: String        // 缓存 key
    let text: String       // 原文
}

// MARK: 跨版本协调器（视图层通过 translationTask 调用 perform）
@MainActor
final class AppleTranslateCoordinator: ObservableObject {
    struct ConfigData {
        var source: Locale.Language?
        var target: Locale.Language
    }

    /// 配置版本号（每次入队 +1，触发视图层 translationTask）
    @Published var configRevision = 0
    var configData: ConfigData?
    var pending: [ApplePendingItem] = []
    /// 翻译完成回调：key -> 译文
    var onResult: ((String, String) -> Void)?
    var onError: ((TranslateError) -> Void)?

    /// 发起一批翻译
    func enqueue(items: [ApplePendingItem], source: Locale.Language?, target: Locale.Language) {
        pending = items
        configData = ConfigData(source: source, target: target)
        configRevision += 1
    }

    /// iOS 18 以下无实现（由下方 extension 覆盖真实逻辑）
    func perform(session: Any) async {}
}

// MARK: iOS 18+ 的真实翻译实现
@available(iOS 18.0, *)
extension AppleTranslateCoordinator {
    func perform(session: TranslationSession) async {
        let items = pending
        pending = []
        for item in items {
            do {
                let response = try await session.translate(item.text)
                onResult?(item.key, response.targetText)
            } catch {
                // 常见失败：离线包未下载 / 语言不受支持
                onError?(.appleOfflinePackMissing)
                break
            }
        }
    }
}

// MARK: 苹果翻译可用性检查（iOS 18.0+）
enum AppleTranslateService {
    static var isSupported: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }
}
