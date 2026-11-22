import XCTest
@testable import SnapTrans

// MARK: - 待翻译截图交接测试（快捷指令 → App 的图片传递通道）
final class PendingImageStoreTests: XCTestCase {

    override func tearDown() {
        // 清理待处理状态，避免影响其他测试/真机使用
        UserDefaults.standard.set(false, forKey: "pendingTranslateImage")
        try? FileManager.default.removeItem(at: FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("pending_translate.jpg"))
        super.tearDown()
    }

    /// 保存 → 消费：图片必须原样读回
    func testSaveAndConsumeRoundtrip() throws {
        let img = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50)).image { rc in
            UIColor.orange.setFill()
            rc.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        let data = try XCTUnwrap(img.jpegData(compressionQuality: 0.9))
        PendingImageStore.saveData(data)
        XCTAssertTrue(PendingImageStore.hasPending, "保存后应有待处理标记")
        let consumed = try XCTUnwrap(PendingImageStore.consume(), "消费应能读回图片")
        XCTAssertEqual(consumed.size.width, 50, accuracy: 1)
        XCTAssertFalse(PendingImageStore.hasPending, "消费后标记应清除")
        XCTAssertNil(PendingImageStore.consume(), "重复消费应返回 nil（文件已删除）")
    }

    /// 未保存时消费必须返回 nil 且不崩溃
    func testConsumeWithoutSave() {
        UserDefaults.standard.set(false, forKey: "pendingTranslateImage")
        XCTAssertFalse(PendingImageStore.hasPending)
        XCTAssertNil(PendingImageStore.consume())
    }
}
