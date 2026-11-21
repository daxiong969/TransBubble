import XCTest
@testable import SnapTrans

// MARK: - Keychain 密钥存取测试（回归：设置页「保存密钥被清空」问题）
final class KeychainServiceTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KeychainService.clear()
    }

    override func tearDown() {
        KeychainService.clear()
        super.tearDown()
    }

    /// 保存后必须能原样读回
    func testSaveAndLoad() {
        let key = "4a1b2c3d-1111-2222-3333-abcdefabcdef:fx"
        KeychainService.save(key)
        XCTAssertEqual(KeychainService.load(), key, "保存的密钥应能原样读回")
    }

    /// 保存后再次保存 → 覆盖旧值（不能出现两条）
    func testOverwrite() {
        KeychainService.save("first-key:fx")
        KeychainService.save("second-key:fx")
        XCTAssertEqual(KeychainService.load(), "second-key:fx", "重复保存应覆盖旧值")
    }

    /// 清空后读取必须为空
    func testClear() {
        KeychainService.save("some-key:fx")
        KeychainService.clear()
        XCTAssertEqual(KeychainService.load(), "", "清空后读取应为空字符串")
    }

    /// 空字符串保存 = 清空
    func testSaveEmptyEqualsClear() {
        KeychainService.save("some-key:fx")
        KeychainService.save("")
        XCTAssertEqual(KeychainService.load(), "", "保存空字符串等同于清空")
    }
}
