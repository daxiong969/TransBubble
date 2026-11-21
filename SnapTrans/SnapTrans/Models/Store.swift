import Foundation
import SwiftData

// MARK: - 翻译缓存（SwiftData 持久化）
// 缓存 key = 原文 + 源语言 + 目标语言 + 翻译服务商（MD5 摘要存储）
@Model
final class CacheItem {
    @Attribute(.unique) var cacheKey: String
    var provider: String        // deepl | apple
    var translation: String
    var updatedAt: Date

    init(cacheKey: String, provider: String, translation: String, updatedAt: Date = Date()) {
        self.cacheKey = cacheKey
        self.provider = provider
        self.translation = translation
        self.updatedAt = updatedAt
    }
}

// MARK: - 翻译历史记录（SwiftData 持久化）
@Model
final class HistoryItem {
    var imageData: Data          // 原始截图（JPEG）
    var overlayData: Data?       // 叠加译文预览图（JPEG）
    var originalsJSON: String    // 原文列表 JSON [String]
    var deeplJSON: String        // DeepL 译文列表 JSON
    var appleJSON: String        // 苹果译文列表 JSON
    var createdAt: Date
    var targetLang: String
    var usedCache: Bool          // 本次是否命中缓存
    var engine: String           // 本次主引擎
    var isFavorite: Bool = false // 收藏标记

    init(imageData: Data, overlayData: Data?, originals: [String],
         deepl: [String], apple: [String], createdAt: Date = Date(),
         targetLang: String, usedCache: Bool, engine: String) {
        self.imageData = imageData
        self.overlayData = overlayData
        self.originalsJSON = Self.encode(originals)
        self.deeplJSON = Self.encode(deepl)
        self.appleJSON = Self.encode(apple)
        self.createdAt = createdAt
        self.targetLang = targetLang
        self.usedCache = usedCache
        self.engine = engine
    }

    var originals: [String] { Self.decode(originalsJSON) }
    var deeplTexts: [String] { Self.decode(deeplJSON) }
    var appleTexts: [String] { Self.decode(appleJSON) }

    static func encode(_ arr: [String]) -> String {
        guard let d = try? JSONEncoder().encode(arr) else { return "[]" }
        return String(data: d, encoding: .utf8) ?? "[]"
    }
    static func decode(_ s: String) -> [String] {
        guard let d = s.data(using: .utf8), let arr = try? JSONDecoder().decode([String].self, from: d) else { return [] }
        return arr
    }
}
