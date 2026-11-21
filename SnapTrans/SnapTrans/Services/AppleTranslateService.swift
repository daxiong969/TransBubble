import Foundation
import Translation

// MARK: - 苹果系统翻译服务（Translation 框架，iOS 17.4+，离线包可用时本地完成）
// 说明：Translation 框架的 TranslationSession 由 SwiftUI 的 translationTask 修饰符托管，
// 视图层把待翻译文本投递给 Coordinator，session 就绪后逐条翻译并回调。
@available(iOS 17.4, *)
struct ApplePendingItem {
    let key: String        // 缓存 key
    let text: String       // 原文
    let index: Int         // 在 blocks 中的下标
}

@available(iOS 17.4, *)
@MainActor
final class AppleTranslateCoordinator: ObservableObject {
    /// SwiftUI translationTask 绑定的配置
    @Published var configuration: TranslationSession.Configuration?
    /// 待翻译队列
    private var pending: [ApplePendingItem] = []
    /// 翻译完成回调：key -> 译文
    var onResult: ((String, String) -> Void)?
    var onError: ((TranslateError) -> Void)?
    private var processing = false

    /// 发起一批翻译（设置源/目标语言后自动触发 translationTask）
    func enqueue(items: [ApplePendingItem], source: Locale.Language?, target: Locale.Language) {
        pending = items
        configuration = TranslationSession.Configuration(
            source: source,
            target: target
        )
    }

    /// translationTask 就绪回调：逐条翻译
    func perform(session: TranslationSession) async {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        for item in pending {
            do {
                let response = try await session.translate(item.text)
                onResult?(item.key, response.targetText)
            } catch {
                // 常见失败：离线包未下载 / 语言不受支持
                onError?(.appleOfflinePackMissing)
                break
            }
        }
        pending = []
        configuration = nil // 结束本批次
    }
}

// MARK: - 苹果翻译可用性检查
enum AppleTranslateService {
    /// 系统是否支持 Translation 框架（iOS 17.4+）
    static var isSupported: Bool {
        if #available(iOS 17.4, *) { return true }
        return false
    }
}
