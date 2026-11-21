import Foundation
import UIKit

// MARK: - 本地 JSON 持久化存储（兼容 iOS 16，替代 SwiftData）
// 缓存与历史记录统一存储到 Documents/snaptrans_store.json；截图以文件形式存于 Documents/images/
final class AppStore: ObservableObject {
    static let shared = AppStore()

    // MARK: 数据模型
    struct CacheEntry: Codable, Identifiable {
        var id = UUID()
        var cacheKey: String
        var provider: String        // deepl | apple
        var translation: String
        var updatedAt: Date
    }

    struct HistoryEntry: Codable, Identifiable {
        var id = UUID()
        var imageFile: String       // 原始截图文件名（存于 images/ 目录）
        var overlayFile: String?    // 叠加译文预览图文件名
        var originals: [String]     // 原文列表
        var deeplTexts: [String]    // DeepL 译文列表
        var appleTexts: [String]    // 苹果译文列表
        var createdAt: Date
        var targetLang: String
        var usedCache: Bool
        var engine: String
        var isFavorite: Bool = false
    }

    struct Snapshot: Codable {
        var cache: [CacheEntry] = []
        var history: [HistoryEntry] = []
    }

    @Published var snapshot = Snapshot()
    private let fileURL: URL
    private let queue = DispatchQueue(label: "snaptrans.store")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = docs.appendingPathComponent("snaptrans_store.json")
        // 启动时加载
        if let data = try? Data(contentsOf: fileURL),
           let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = s
        }
    }

    /// 写盘（后台队列，原子写入）
    func persist() {
        let data = try? JSONEncoder().encode(snapshot)
        let url = fileURL
        queue.async {
            if let data { try? data.write(to: url, options: .atomic) }
        }
    }

    // MARK: 图片文件存取
    static var imagesDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func saveImage(_ img: UIImage?, name: String) -> String? {
        guard let img, let data = img.jpegData(compressionQuality: 0.85) else { return nil }
        let url = imagesDir.appendingPathComponent("\(name).jpg")
        try? data.write(to: url, options: .atomic)
        return "\(name).jpg"
    }

    static func loadImage(_ rel: String?) -> UIImage? {
        guard let rel else { return nil }
        let url = imagesDir.appendingPathComponent(rel)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
}

// MARK: - 翻译缓存服务（缓存 key = 原文+源语言+目标语言+服务商）
struct CacheService {
    static let shared = CacheService()
    private var store: AppStore { AppStore.shared }

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
        guard let item = store.snapshot.cache.first(where: { $0.cacheKey == key }) else { return nil }
        if let interval = CacheService.expiryInterval(policy),
           Date().timeIntervalSince(item.updatedAt) > interval {
            // 已过期：删除并返回 nil
            store.snapshot.cache.removeAll { $0.cacheKey == key }
            return nil
        }
        return item.translation
    }

    /// 写入/刷新缓存
    func save(key: String, provider: String, translation: String) {
        if let idx = store.snapshot.cache.firstIndex(where: { $0.cacheKey == key }) {
            store.snapshot.cache[idx].translation = translation
            store.snapshot.cache[idx].updatedAt = Date()
        } else {
            store.snapshot.cache.append(AppStore.CacheEntry(cacheKey: key, provider: provider,
                                                            translation: translation, updatedAt: Date()))
        }
        store.persist()
    }

    /// 清空全部缓存
    func clearAll() {
        store.snapshot.cache.removeAll()
        store.persist()
    }
}

// MARK: - 历史记录服务
struct HistoryService {
    static let shared = HistoryService()
    private var store: AppStore { AppStore.shared }

    /// 新增历史记录（截图写入文件）
    @discardableResult
    func add(image: UIImage, overlay: UIImage?, blocks: [TextBlock], targetLang: String,
             usedCache: Bool, engine: String) -> AppStore.HistoryEntry {
        let fileId = UUID().uuidString
        let entry = AppStore.HistoryEntry(
            imageFile: AppStore.saveImage(image, name: "orig_\(fileId)") ?? "",
            overlayFile: AppStore.saveImage(overlay, name: "ovl_\(fileId)"),
            originals: blocks.map { $0.original },
            deeplTexts: blocks.map { $0.deepl },
            appleTexts: blocks.map { $0.apple },
            createdAt: Date(),
            targetLang: targetLang,
            usedCache: usedCache,
            engine: engine
        )
        store.snapshot.history.insert(entry, at: 0)
        store.persist()
        return entry
    }

    /// 按时间倒序查询（可搜索关键词 / 仅收藏）
    func fetch(keyword: String = "", favoritesOnly: Bool = false) -> [AppStore.HistoryEntry] {
        var items = store.snapshot.history
        if favoritesOnly { items = items.filter { $0.isFavorite } }
        if keyword.isEmpty { return items }
        // 原文/译文关键词搜索
        return items.filter {
            $0.originals.contains { $0.localizedCaseInsensitiveContains(keyword) } ||
            $0.deeplTexts.contains { $0.localizedCaseInsensitiveContains(keyword) } ||
            $0.appleTexts.contains { $0.localizedCaseInsensitiveContains(keyword) }
        }
    }

    /// 删除单条（同时删除图片文件）
    func delete(_ entry: AppStore.HistoryEntry) {
        deleteFiles(of: entry)
        store.snapshot.history.removeAll { $0.id == entry.id }
        store.persist()
    }

    /// 批量删除
    func delete(_ entries: [AppStore.HistoryEntry]) {
        for e in entries { deleteFiles(of: e) }
        let ids = Set(entries.map { $0.id })
        store.snapshot.history.removeAll { ids.contains($0.id) }
        store.persist()
    }

    private func deleteFiles(of entry: AppStore.HistoryEntry) {
        for f in [entry.imageFile, entry.overlayFile].compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: AppStore.imagesDir.appendingPathComponent(f))
        }
    }

    /// 切换收藏
    func toggleFavorite(_ entry: AppStore.HistoryEntry) {
        guard let idx = store.snapshot.history.firstIndex(where: { $0.id == entry.id }) else { return }
        store.snapshot.history[idx].isFavorite.toggle()
        store.persist()
    }

    /// 导出 TXT（可选是否包含双翻译源对比）
    static func exportTXT(_ entry: AppStore.HistoryEntry, withCompare: Bool) -> String {
        var lines: [String] = []
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        lines.append("=== 译拍通翻译记录 ===")
        lines.append("时间：\(df.string(from: entry.createdAt))")
        lines.append("目标语言：\(entry.targetLang)   引擎：\(entry.engine)   命中缓存：\(entry.usedCache ? "是" : "否")")
        lines.append("")
        for (i, o) in entry.originals.enumerated() {
            lines.append("【\(i + 1)】原文：\(o)")
            if withCompare {
                if i < entry.deeplTexts.count { lines.append("    DeepL：\(entry.deeplTexts[i])") }
                if i < entry.appleTexts.count { lines.append("    苹果翻译：\(entry.appleTexts[i])") }
            } else {
                let t = entry.engine == "apple" ? (i < entry.appleTexts.count ? entry.appleTexts[i] : "") :
                    (i < entry.deeplTexts.count ? entry.deeplTexts[i] : "")
                lines.append("    译文：\(t)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
