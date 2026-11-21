import Foundation
import CryptoKit

// MARK: - 缓存 Key 工具
// 缓存 key = 原文 + 源语言 + 目标语言 + 翻译服务商（MD5 存储，避免超长）
func makeCacheKey(_ text: String, source: String, target: String, provider: String) -> String {
    let raw = "\(text)|\(source)|\(target)|\(provider)"
    let digest = Insecure.MD5.hash(data: Data(raw.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}
// 缓存/历史服务实现见 Models/Store.swift（iOS 16 兼容的 JSON 本地存储）
