import Foundation
import UIKit

// MARK: - DeepL 翻译服务（原生 URLSession，支持错误重试，禁止第三方库）
final class DeepLTranslateService {
    /// 批量翻译（DeepL 支持一次请求多段文本）
    /// - Parameters:
    ///   - texts: 原文列表
    ///   - source: 源语言（nil=自动检测）
    ///   - target: 目标语言（DeepL 代码，如 ZH）
    ///   - apiKey: 用户配置的密钥（free 密钥以 ":fx" 结尾）
    ///   - timeout: 超时秒数
    func translate(texts: [String], source: String?, target: String,
                   apiKey: String, timeout: Double) async throws -> [String] {
        guard !apiKey.isEmpty else { throw TranslateError.emptyKey }
        // free 账户（密钥以 :fx 结尾）走 api-free 域名
        let host = apiKey.hasSuffix(":fx") ? "api-free.deepl.com" : "api.deepl.com"
        guard let url = URL(string: "https://\(host)/v2/translate") else {
            throw TranslateError.badResponse
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("DeepL-Auth-Key \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 请求体
        var body: [String: Any] = ["text": texts, "target_lang": target]
        if let source = source { body["source_lang"] = source }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        // 执行请求（限流/超时自动重试一次）
        return try await executeWithRetry(request, textsCount: texts.count)
    }

    /// 带重试的执行（429 限流 / 超时各重试一次，间隔 1.5s）
    private func executeWithRetry(_ request: URLRequest, textsCount: Int) async throws -> [String] {
        var lastError: TranslateError = .badResponse
        for attempt in 0..<2 {
            if attempt > 0 { try await Task.sleep(nanoseconds: 1_500_000_000) }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw TranslateError.badResponse }
                switch http.statusCode {
                case 200:
                    // 解析返回 JSON
                    guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let arr = obj["translations"] as? [[String: Any]] else {
                        throw TranslateError.badResponse
                    }
                    let result = arr.compactMap { $0["text"] as? String }
                    guard result.count == textsCount else { throw TranslateError.badResponse }
                    return result
                case 401, 403:
                    throw TranslateError.authFailed
                case 456:
                    throw TranslateError.quotaExceeded
                case 429:
                    lastError = .rateLimited
                    continue // 限流 → 重试
                default:
                    throw TranslateError.badResponse
                }
            } catch let e as TranslateError {
                if case .rateLimited = e { lastError = e; continue }
                throw e // 业务错误不重试
            } catch let e as URLError {
                if e.code == .timedOut {
                    lastError = .timeout
                    continue // 超时 → 重试一次
                }
                throw TranslateError.network(e.localizedDescription)
            } catch {
                throw TranslateError.network(error.localizedDescription)
            }
        }
        throw lastError
    }
}
