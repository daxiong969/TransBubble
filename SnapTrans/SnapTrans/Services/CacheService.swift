import Foundation
import CryptoKit

// MARK: - 缓存 Key 工具
// 缓存 key = 原文 + 源语言 + 目标语言 + 翻译服务商（MD5 存储，避免超长）
func makeCacheKey(_ text: String, source: String, target: String, provider: String) -> String {
    let raw = "\(text)|\(source)|\(target)|\(provider)"
    let digest = Insecure.MD5.hash(data: Data(raw.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - 翻译缓存服务（SwiftData）
struct CacheService {
    let context: ModelContext

    /// 缓存过期秒数（never=永久）
    static func expiryInterval(_ policy: String) -> TimeInterval? {
        switch policy {
        case "7d": return 7 * 24 * 3600
        case "30d": return 30 * 24 * 3600
        default: return nil
        }
    }

    /// 查询缓存（自动按过期策略过滤）
    func lookup(key: String, policy: String) -> String? {
        let req = FetchDescriptor<CacheItem>(predicate: #Predicate { $0.cacheKey == key })
        guard let item = try? context.fetch(req).first else { return nil }
        // 过期检查
        if let interval = CacheService.expiryInterval(policy),
           Date().timeIntervalSince(item.updatedAt) > interval {
            // 已过期：删除并返回 nil
            try? context.delete(item)
            return nil
        }
        return item.translation
    }

    /// 写入/刷新缓存
    func save(key: String, provider: String, translation: String) {
        let req = FetchDescriptor<CacheItem>(predicate: #Predicate { $0.cacheKey == key })
        if let existing = try? context.fetch(req).first {
            existing.translation = translation
            existing.updatedAt = Date()
        } else {
            context.insert(CacheItem(cacheKey: key, provider: provider, translation: translation))
        }
        try? context.save()
    }

    /// 清空全部缓存
    func clearAll() {
        let req = FetchDescriptor<CacheItem>()
        if let items = try? context.fetch(req) {
            for it in items { try? context.delete(it) }
        }
        try? context.save()
    }

    /// 删除单条历史时，可选删除其关联缓存（按原文列表）
    func deleteCaches(for texts: [String], target: String) {
        for t in texts {
            for provider in ["deepl", "apple"] {
                let key = makeCacheKey(t, source: "auto", target: target, provider: provider)
                let req = FetchDescriptor<CacheItem>(predicate: #Predicate { $0.cacheKey == key })
                if let item = try? context.fetch(req).first {
                    try? context.delete(item)
                }
            }
        }
        try? context.save()
    }
}

// MARK: - 历史记录服务（SwiftData）
struct HistoryService {
    let context: ModelContext

    /// 新增历史记录
    @discardableResult
    func add(image: UIImage, overlay: UIImage?, blocks: [TextBlock], targetLang: String,
             usedCache: Bool, engine: String) -> HistoryItem {
        let item = HistoryItem(
            imageData: image.jpegData(compressionQuality: 0.85) ?? Data(),
            overlayData: overlay?.jpegData(compressionQuality: 0.85),
            originals: blocks.map { $0.original },
            deepl: blocks.map { $0.deepl },
            apple: blocks.map { $0.apple },
            targetLang: targetLang,
            usedCache: usedCache,
            engine: engine
        )
        context.insert(item)
        try? context.save()
        return item
    }

    /// 按时间倒序查询（可搜索关键词 / 仅收藏）
    func fetch(keyword: String = "", favoritesOnly: Bool = false) -> [HistoryItem] {
        var req = FetchDescriptor<HistoryItem>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if favoritesOnly {
            req.predicate = #Predicate { $0.isFavorite }
        }
        guard let items = try? context.fetch(req) else { return [] }
        if keyword.isEmpty { return items }
        // 原文/译文关键词搜索
        return items.filter {
            $0.originals.contains { $0.localizedCaseInsensitiveContains(keyword) } ||
            $0.deeplTexts.contains { $0.localizedCaseInsensitiveContains(keyword) } ||
            $0.appleTexts.contains { $0.localizedCaseInsensitiveContains(keyword) }
        }
    }

    /// 删除单条
    func delete(_ item: HistoryItem) {
        try? context.delete(item)
        try? context.save()
    }

    /// 批量删除
    func delete(_ items: [HistoryItem]) {
        for it in items { try? context.delete(it) }
        try? context.save()
    }

    /// 切换收藏
    func toggleFavorite(_ item: HistoryItem) {
        item.isFavorite.toggle()
        try? context.save()
    }

    /// 导出 TXT（可选是否包含双翻译源对比）
    static func exportTXT(_ item: HistoryItem, withCompare: Bool) -> String {
        var lines: [String] = []
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("=== 译拍通翻译记录 ===")
        lines.append("时间：\(df.string(item.createdAt))")
        lines.append("目标语言：\(item.targetLang)   引擎：\(item.engine)   命中缓存：\(item.usedCache ? "是" : "否")")
        lines.append("")
        let originals = item.originals
        let deepl = item.deeplTexts
        let apple = item.appleTexts
        for (i, o) in originals.enumerated() {
            lines.append("【\(i + 1)】原文：\(o)")
            if withCompare {
                if i < deepl.count { lines.append("    DeepL：\(deepl[i])") }
                if i < apple.count { lines.append("    苹果翻译：\(apple[i])") }
            } else {
                let t = item.engine == "apple" ? (i < apple.count ? apple[i] : "") : (i < deepl.count ? deepl[i] : "")
                lines.append("    译文：\(t)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
