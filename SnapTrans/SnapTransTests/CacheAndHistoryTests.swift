import XCTest
import UIKit
@testable import SnapTrans

// MARK: - 缓存 / 历史记录测试（本地 JSON 存储）
final class CacheAndHistoryTests: XCTestCase {

    func testMakeCacheKeyDeterministic() {
        // 同参数 → 同 key
        let a = makeCacheKey("hello", source: "auto", target: "zh", provider: "deepl")
        let b = makeCacheKey("hello", source: "auto", target: "zh", provider: "deepl")
        XCTAssertEqual(a, b, "缓存 key 必须确定性生成")
    }

    func testMakeCacheKeyProviderIsolation() {
        // 双翻译源独立缓存：key 必须包含服务商维度
        let deepl = makeCacheKey("hello", source: "auto", target: "zh", provider: "deepl")
        let apple = makeCacheKey("hello", source: "auto", target: "zh", provider: "apple")
        XCTAssertNotEqual(deepl, apple, "不同服务商必须得到不同缓存 key")
    }

    func testCacheSaveAndLookup() {
        let key = makeCacheKey("测试文本\(UUID())", source: "auto", target: "zh", provider: "deepl")
        CacheService.shared.save(key: key, provider: "deepl", translation: "已缓存译文")
        XCTAssertEqual(CacheService.shared.lookup(key: key, policy: "never"), "已缓存译文", "缓存命中应返回译文")
        // 二次写入刷新
        CacheService.shared.save(key: key, provider: "deepl", translation: "刷新后译文")
        XCTAssertEqual(CacheService.shared.lookup(key: key, policy: "never"), "刷新后译文")
        CacheService.shared.clearAll()
        XCTAssertNil(CacheService.shared.lookup(key: key, policy: "never"), "清空后缓存应未命中")
    }

    func testCacheExpiryPolicy() {
        XCTAssertNil(CacheService.expiryInterval("never"), "永久策略不应有过期时间")
        XCTAssertEqual(CacheService.expiryInterval("7d"), 7 * 86400)
        XCTAssertEqual(CacheService.expiryInterval("30d"), 30 * 86400)
    }

    func testHistoryAddFetchSearchFavoriteExport() {
        // 造一张 1x1 图片
        let img = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { rc in
            UIColor.blue.setFill(); rc.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let blocks = [TextBlock(original: "UniqueKeywordXYZ", bounding: CGRect(x: 0, y: 0, width: 1, height: 1),
                                confidence: 0.9, deepl: "关键词译文", apple: "")]
        let entry = HistoryService.shared.add(image: img, overlay: nil, blocks: blocks,
                                              targetLang: "zh", usedCache: false, engine: "deepl")
        // 倒序查询应包含新记录
        XCTAssertTrue(HistoryService.shared.fetch().contains { $0.id == entry.id })
        // 关键词搜索（原文 + 译文双向）
        XCTAssertEqual(HistoryService.shared.fetch(keyword: "UniqueKeywordXYZ").count, 1)
        XCTAssertEqual(HistoryService.shared.fetch(keyword: "关键词译文").count, 1)
        // 收藏与收藏分类
        HistoryService.shared.toggleFavorite(entry)
        XCTAssertTrue(HistoryService.shared.fetch(favoritesOnly: true).contains { $0.id == entry.id })
        // TXT 导出（单源 / 双源对比）
        let txt1 = HistoryService.exportTXT(entry, withCompare: false)
        XCTAssertTrue(txt1.contains("UniqueKeywordXYZ") && txt1.contains("关键词译文"))
        let txt2 = HistoryService.exportTXT(entry, withCompare: true)
        XCTAssertTrue(txt2.contains("DeepL："), "对比导出应含 DeepL 标签")
        // 清理
        HistoryService.shared.delete(entry)
        XCTAssertFalse(HistoryService.shared.fetch(keyword: "UniqueKeywordXYZ").contains { $0.id == entry.id })
    }
}
