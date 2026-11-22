import XCTest
import UIKit
@testable import SnapTrans

// MARK: - 直播翻译共享存储层测试（App Group 容器 / 回退目录）
final class BroadcastSharedTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // 清理现场，避免互相影响
        try? FileManager.default.removeItem(at: BroadcastShared.configURL)
        try? FileManager.default.removeItem(at: BroadcastShared.frameURL)
        try? FileManager.default.removeItem(at: BroadcastShared.frameInfoURL)
        try? FileManager.default.removeItem(at: BroadcastShared.resultURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: BroadcastShared.configURL)
        try? FileManager.default.removeItem(at: BroadcastShared.frameURL)
        try? FileManager.default.removeItem(at: BroadcastShared.frameInfoURL)
        try? FileManager.default.removeItem(at: BroadcastShared.resultURL)
        super.tearDown()
    }

    /// 配置写入/读取往返（主 App → 扩展）
    func testConfigRoundtrip() {
        let cfg = BroadcastShared.Config(
            deeplKey: "abc123:fx", sourceLang: "auto",
            targetLang: "zh-Hans", ocrLanguage: "en-US")
        BroadcastShared.saveConfig(cfg)
        let loaded = BroadcastShared.loadConfig()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.deeplKey, "abc123:fx")
        XCTAssertEqual(loaded?.targetLang, "zh-Hans")
        XCTAssertEqual(loaded?.ocrLanguage, "en-US")
    }

    /// 画面保存/读取/消费标记（扩展 → 主 App）
    func testFrameSaveLoadConsume() throws {
        let jpeg = UIImageRenderer.makeFakeJPEG()
        BroadcastShared.saveFrame(jpeg)
        let frame = try XCTUnwrap(BroadcastShared.loadFrame())
        XCTAssertFalse(frame.info.consumed)
        XCTAssertEqual(frame.data, jpeg)
        // 标记消费后 consumed 置位
        BroadcastShared.markFrameConsumed()
        let consumed = try XCTUnwrap(BroadcastShared.loadFrame())
        XCTAssertTrue(consumed.info.consumed)
    }

    /// 结果写入/读取往返（扩展 → 主 App）
    func testResultRoundtrip() {
        let r = BroadcastShared.Result(
            timestamp: 1700000000, originalText: "Hello world",
            translatedText: "你好，世界", engine: "deepl")
        BroadcastShared.saveResult(r)
        let loaded = BroadcastShared.loadResult()
        XCTAssertEqual(loaded?.originalText, "Hello world")
        XCTAssertEqual(loaded?.translatedText, "你好，世界")
        XCTAssertEqual(loaded?.engine, "deepl")
    }

    /// 空状态读取不崩溃
    func testEmptyState() {
        XCTAssertNil(BroadcastShared.loadConfig())
        XCTAssertNil(BroadcastShared.loadFrame())
        XCTAssertNil(BroadcastShared.loadResult())
    }
}

// MARK: - 测试辅助：生成一张小尺寸 JPEG
private enum UIImageRenderer {
    static func makeFakeJPEG() -> Data {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let img = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return img.jpegData(compressionQuality: 0.8)!
    }
}
