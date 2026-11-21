import Foundation
import Security

// MARK: - Keychain 安全存储（DeepL API Key 本地加密保存，不上传）
enum KeychainService {
    static let account = "deepl_api_key"

    /// 保存密钥
    static func save(_ value: String) {
        let data = Data(value.utf8)
        // 先删除旧值
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delQuery as CFDictionary)
        guard !value.isEmpty else { return }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    /// 读取密钥
    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 清空密钥
    static func clear() {
        save("")
    }
}
