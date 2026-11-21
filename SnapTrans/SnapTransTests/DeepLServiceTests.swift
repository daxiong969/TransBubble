import XCTest
@testable import SnapTrans

// MARK: - DeepL 翻译服务测试（不发真实网络请求，只测错误分支与文案）
final class DeepLServiceTests: XCTestCase {

    /// 空密钥必须抛 emptyKey
    func testEmptyKeyThrows() async {
        do {
            _ = try await DeepLTranslateService().translate(
                texts: ["hi"], source: nil, target: "ZH", apiKey: "", timeout: 5)
            XCTFail("空密钥应抛出 emptyKey")
        } catch let e as TranslateError {
            XCTAssertEqual(e, .emptyKey, "应抛出 emptyKey 错误")
        } catch {
            XCTFail("应抛出 TranslateError，实际: \(error)")
        }
    }

    /// 每种错误都有非空中文提示（面向用户的详细错误提示要求）
    func testAllErrorMessagesNonEmpty() {
        let errors: [TranslateError] = [.emptyKey, .authFailed, .quotaExceeded, .rateLimited,
                                        .timeout, .badResponse, .network("x"), .appleUnavailable,
                                        .appleOfflinePackMissing, .ocrFailed("x"), .captureFailed("x")]
        for e in errors {
            let msg = e.errorDescription ?? ""
            XCTAssertFalse(msg.isEmpty, "\(e) 的提示文案不能为空")
            XCTAssertTrue(msg.contains("，") || msg.count > 6, "\(e) 的提示应包含指引信息")
        }
    }
}
