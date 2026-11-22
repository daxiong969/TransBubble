import Foundation

// MARK: - 主 App 与「录屏广播扩展」共享的存储层（App Group 容器）
// 该文件同时编译进主 App 与 SnapTransBroadcast 扩展两个 target，
// 通过 App Group 共享目录交换：翻译配置（主 App → 扩展）、最新画面与结果（扩展 → 主 App）。
enum BroadcastShared {
    static let appGroupID = "group.com.daxiong969.SnapTrans"

    /// App Group 容器（需签名时包含对应 entitlement；免签/测试环境可能为 nil）
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    /// App Group 不可用时（免签调试 / 单元测试环境）退回沙盒缓存目录，
    /// 保证单进程内功能可用、测试可跑；仅跨进程共享会失效。
    static var box: URL {
        if let url = containerURL { return url }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    // MARK: 数据模型
    /// 主 App 下发给扩展的翻译配置（扩展读不到主 App 的 Keychain，必须在开播前同步）
    struct Config: Codable {
        var deeplKey: String
        var sourceLang: String
        var targetLang: String
        var ocrLanguage: String
    }

    /// 最新画面元信息
    struct FrameInfo: Codable {
        var timestamp: Double
        var consumed: Bool
    }

    /// 扩展产出的识别+翻译结果
    struct Result: Codable {
        var timestamp: Double
        var originalText: String
        var translatedText: String
        var engine: String   // "deepl" | "none"
    }

    // MARK: 文件路径
    static var configURL: URL { box.appendingPathComponent("broadcast_config.json") }
    static var frameURL: URL { box.appendingPathComponent("broadcast_frame.jpg") }
    static var frameInfoURL: URL { box.appendingPathComponent("broadcast_frame_info.json") }
    static var resultURL: URL { box.appendingPathComponent("broadcast_result.json") }

    // MARK: 配置（主 App 写，扩展读）
    static func saveConfig(_ c: Config) {
        guard let data = try? JSONEncoder().encode(c) else { return }
        try? data.write(to: configURL, options: .atomic)
    }
    static func loadConfig() -> Config? {
        guard let data = try? Data(contentsOf: configURL) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    // MARK: 最新画面（扩展写，主 App 读）
    static func saveFrame(_ jpeg: Data) {
        try? jpeg.write(to: frameURL, options: .atomic)
        let info = FrameInfo(timestamp: Date().timeIntervalSince1970, consumed: false)
        if let data = try? JSONEncoder().encode(info) {
            try? data.write(to: frameInfoURL, options: .atomic)
        }
    }
    static func loadFrame() -> (data: Data, info: FrameInfo)? {
        guard let data = try? Data(contentsOf: frameURL),
              let infoData = try? Data(contentsOf: frameInfoURL),
              let info = try? JSONDecoder().decode(FrameInfo.self, from: infoData) else { return nil }
        return (data, info)
    }
    static func markFrameConsumed() {
        guard let data = try? Data(contentsOf: frameInfoURL),
              var info = try? JSONDecoder().decode(FrameInfo.self, from: data) else { return }
        info.consumed = true
        if let updated = try? JSONEncoder().encode(info) {
            try? updated.write(to: frameInfoURL, options: .atomic)
        }
    }

    // MARK: 识别+翻译结果（扩展写，主 App 读）
    static func saveResult(_ r: Result) {
        guard let data = try? JSONEncoder().encode(r) else { return }
        try? data.write(to: resultURL, options: .atomic)
    }
    static func loadResult() -> Result? {
        guard let data = try? Data(contentsOf: resultURL) else { return nil }
        return try? JSONDecoder().decode(Result.self, from: data)
    }
}
