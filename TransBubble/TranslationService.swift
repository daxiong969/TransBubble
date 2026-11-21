import Foundation

struct TranslationResult {
    let detectedLanguage: String
    let translatedText: String
}

enum TranslationError: LocalizedError {
    case emptyText
    case network(String)
    case parseFailed

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "当前页面没有可翻译的内容"
        case .network(let msg):
            return "翻译请求失败：\(msg)（国内网络可能需要代理访问 translate.googleapis.com）"
        case .parseFailed:
            return "翻译结果解析失败，请稍后重试"
        }
    }
}

/// 免费翻译服务（无需 API Key），支持 100+ 语言自动检测并翻译为中文
final class TranslationService {
    static let shared = TranslationService()

    private let endpoint = "https://translate.googleapis.com/translate_a/single"
    private let chunkLimit = 1400
    private let maxTextLength = 20000

    func translate(_ text: String, target: String = "zh-CN") async throws -> TranslationResult {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTextLength))
        guard !trimmed.isEmpty else { throw TranslationError.emptyText }

        let chunks = splitIntoChunks(trimmed)
        var outputs: [String] = []
        var detected = ""
        for chunk in chunks {
            let result = try await requestTranslation(chunk, target: target)
            outputs.append(result.translatedText)
            if detected.isEmpty { detected = result.detectedLanguage }
        }
        return TranslationResult(detectedLanguage: detected,
                                 translatedText: outputs.joined(separator: "\n\n"))
    }

    // MARK: - Private

    private func splitIntoChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for paragraph in text.components(separatedBy: "\n") {
            if current.isEmpty {
                current = paragraph
            } else if current.count + paragraph.count + 1 <= chunkLimit {
                current += "\n" + paragraph
            } else {
                if !current.isEmpty { chunks.append(current) }
                current = paragraph
            }
            // 超长单段强制切分
            while current.count > chunkLimit {
                let idx = current.index(current.startIndex, offsetBy: chunkLimit)
                chunks.append(String(current[..<idx]))
                current = String(current[idx...])
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func requestTranslation(_ text: String, target: String) async throws -> TranslationResult {
        var comps = URLComponents(string: endpoint)!
        comps.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: target),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        var request = URLRequest(url: comps.url!)
        request.timeoutInterval = 30
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)",
                         forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TranslationError.network("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return try parseResponse(data)
    }

    private func parseResponse(_ data: Data) throws -> TranslationResult {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = array.first as? [Any] else {
            throw TranslationError.parseFailed
        }
        var parts: [String] = []
        for item in segments {
            if let seg = item as? [Any], let piece = seg.first as? String {
                parts.append(piece)
            }
        }
        guard !parts.isEmpty else { throw TranslationError.parseFailed }
        let detected = array.count > 2 ? (array[2] as? String ?? "") : ""
        return TranslationResult(detectedLanguage: detected,
                                 translatedText: parts.joined())
    }
}
