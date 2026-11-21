import Foundation
import Security

// MARK: - Keychain 安全存储（DeepL API Key 本地保存，不上传）
// 优先 Keychain 加密存储；若系统拒绝访问（如模拟器/无授权环境 SecItemAdd 失败），
// 自动兜底到 UserDefaults 本地存储，保证密钥永不静默丢失。
enum KeychainService {
    static let account = "deepl_api_key"
    private static let fallbackKey = "deepl_api_key_fallback"

    /// 保存密钥
    static func save(_ value: String) {
        // 先删除旧值（Keychain + 兜底两处都清）
        let delQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(delQuery as CFDictionary)
        UserDefaults.standard.removeObject(forKey: fallbackKey)
        guard !value.isEmpty else { return }

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status != errSecSuccess {
            // Keychain 不可用 → 本地兜底（仅保存在本机沙盒，不上传）
            UserDefaults.standard.set(value, forKey: fallbackKey)
        }
    }

    /// 读取密钥（优先 Keychain，其次兜底存储）
    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data,
           let str = String(data: data, encoding: .utf8), !str.isEmpty {
            return str
        }
        return UserDefaults.standard.string(forKey: fallbackKey) ?? ""
    }

    /// 清空密钥
    static func clear() {
        save("")
    }
}
