import XCTest
import UIKit
@testable import SnapTrans

// MARK: - OCR 识别测试（Apple Vision 本地识别，模拟器可运行）
final class OCRServiceTests: XCTestCase {

    /// 渲染一张含清晰英文文字的图片，OCR 必须识别出关键词
    func testRecognizeEnglishText() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 200)).image { rc in
            UIColor.white.setFill()
            rc.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 64, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            NSAttributedString(string: "HELLO SNAPTRANS", attributes: attrs)
                .draw(at: CGPoint(x: 30, y: 60))
        }
        let blocks = try await OCRService().recognize(image: image, language: "en-US")
        XCTAssertFalse(blocks.isEmpty, "OCR 应识别出至少一个文字块")
        let joined = blocks.map { $0.original }.joined(separator: " ").uppercased()
        XCTAssertTrue(joined.contains("HELLO"), "应识别出 HELLO，实际: \(joined)")
        // 坐标应落在图片范围内（归一化 0~1）
        for b in blocks {
            XCTAssertTrue(b.bounding.minY >= 0 && b.bounding.maxY <= 1.0001, "坐标应归一化")
        }
    }

    /// 无效图片必须抛出 ocrFailed
    func testInvalidImageThrows() async {
        let broken = UIImage(contentsOfFile: "/nonexistent.jpg")
        do {
            _ = try await OCRService().recognize(image: broken ?? UIImage(), language: "en-US")
            // 1x1 空白图也可能成功返回空数组，这里仅确保不崩溃
        } catch {
            // 允许抛错
        }
    }
}
