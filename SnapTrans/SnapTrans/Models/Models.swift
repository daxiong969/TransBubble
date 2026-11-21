import Foundation
import CoreGraphics
import SwiftUI

// MARK: - OCR 识别出的单块文字
struct TextBlock: Identifiable, Codable, Hashable {
    var id = UUID()
    var original: String              // 原文
    var bounding: CGRect              // 归一化坐标（0~1，左上原点，相对整张截图）
    var confidence: Double            // 识别置信度 0~1
    var deepl: String = ""            // DeepL 译文
    var apple: String = ""            // 苹果翻译译文
    var hidden: Bool = false          // 用户单独隐藏该块译文
    var ignored: Bool = false         // 用户忽略该块（不翻译不显示）
    var fromCache: Bool = false       // 是否来自本地缓存

    var displayOriginal: String { original }
}

// MARK: - 译文叠加样式（浅色/深色两套独立预设）
struct OverlayStyle: Codable, Equatable {
    var fontSize: CGFloat
    var textColorHex: String
    var bgHex: String
    var bgOpacity: Double

    // 浅色模式预设
    static func light() -> OverlayStyle {
        OverlayStyle(fontSize: 13, textColorHex: "#FFFFFF", bgHex: "#1E88E5", bgOpacity: 0.75)
    }
    // 深色模式预设
    static func dark() -> OverlayStyle {
        OverlayStyle(fontSize: 13, textColorHex: "#FFFFFF", bgHex: "#37474F", bgOpacity: 0.82)
    }
}

// MARK: - 颜色工具
func colorFromHex(_ hex: String) -> Color {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    var v: UInt64 = 0
    Scanner(string: h).scanHexInt64(&v)
    let r = Double((v >> 16) & 0xFF) / 255
    let g = Double((v >> 8) & 0xFF) / 255
    let b = Double(v & 0xFF) / 255
    return Color(red: r, green: g, blue: b)
}

// MARK: - 全局设置项（@AppStorage 持久化）
struct AppSettings {
    // DeepL
    // key 存 Keychain，由 KeychainService 管理
    // 翻译
    @AppStorage("defaultEngine") var defaultEngine: String = "deepl"        // deepl | apple
    @AppStorage("sourceLang") var sourceLang: String = "auto"               // auto | en | ja | ko | zh-Hans
    @AppStorage("targetLang") var targetLang: String = "zh-Hans"            // 目标语言
    @AppStorage("compareModeDefault") var compareModeDefault: Bool = false  // 默认开启双语对比
    @AppStorage("requestTimeout") var requestTimeout: Double = 15           // 请求超时（秒）
    // 悬浮球
    @AppStorage("pipEnabled") var pipEnabled: Bool = false                  // 是否已开启悬浮球
    @AppStorage("pipSize") var pipSize: Double = 64                         // 悬浮球尺寸
    @AppStorage("pipOpacity") var pipOpacity: Double = 0.9                  // 透明度
    @AppStorage("pipDoubleTap") var pipDoubleTapEnabled: Bool = true        // 双击打开主界面
    // OCR
    @AppStorage("ocrLanguage") var ocrLanguage: String = "en-US"            // en-US | ja | ko | zh-Hans
    @AppStorage("lowConfidenceAlert") var lowConfidenceAlert: Bool = true   // 低置信度提醒
    // 缓存
    @AppStorage("cacheExpiry") var cacheExpiry: String = "never"            // never | 7d | 30d
    // TTS
    @AppStorage("ttsRate") var ttsRate: Double = 0.5                        // 0~1（AVSpeech 映射）
    @AppStorage("ttsVoiceID") var ttsVoiceID: String = ""                   // 语音标识
    @AppStorage("ttsAutoSpeak") var ttsAutoSpeak: Bool = false              // 翻译完自动朗读
    // 快捷指令
    @AppStorage("allowIntentTrigger") var allowIntentTrigger: Bool = true   // 允许外部触发
    // 样式（浅/深两套，JSON 存储）
    @AppStorage("styleLight") var styleLightRaw: String = ""
    @AppStorage("styleDark") var styleDarkRaw: String = ""

    func style(for dark: Bool) -> OverlayStyle {
        let raw = dark ? styleDarkRaw : styleLightRaw
        if let data = raw.data(using: .utf8),
           let s = try? JSONDecoder().decode(OverlayStyle.self, from: data) {
            return s
        }
        return dark ? .dark() : .light()
    }
    func setStyle(_ s: OverlayStyle, dark: Bool) {
        guard let data = try? JSONEncoder().encode(s), let str = String(data: data, encoding: .utf8) else { return }
        if dark { styleDarkRaw = str } else { styleLightRaw = str }
    }
}

// MARK: - 语言常量
struct LangDefs {
    // OCR / 翻译支持的源语言
    static let sourceLangs: [(code: String, name: String)] = [
        ("auto", "自动检测"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
        ("zh-Hans", "简体中文"),
    ]
    static let targetLangs: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-TW", "繁体中文"),
        ("en", "英语"),
        ("ja", "日语"),
        ("ko", "韩语"),
    ]
    // DeepL 目标语言代码映射
    static func deeplTarget(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "ZH"
        case "zh-TW": return "ZH"
        default: return code.uppercased()
        }
    }
    static func deeplSource(_ code: String) -> String? {
        code == "auto" ? nil : code.uppercased().replacingOccurrences(of: "-HANS", with: "")
    }
    // BCP47 -> TTS 语音
    static func ttsLocale(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-TW": return "zh-TW"
        default: return code
        }
    }
}

// MARK: - 统一翻译错误（每种错误独立提示）
enum TranslateError: LocalizedError, Equatable {
    case emptyKey                 // DeepL 密钥为空
    case authFailed               // 密钥错误
    case quotaExceeded            // 配额耗尽
    case rateLimited              // 接口限流
    case timeout                  // 网络超时
    case badResponse              // 返回格式异常
    case network(String)          // 其他网络错误
    case appleUnavailable         // 系统版本过低（Translation 需要 iOS 17.4+）
    case appleOfflinePackMissing  // 苹果离线翻译包未下载
    case ocrFailed(String)        // OCR 失败
    case captureFailed(String)    // 截图失败

    var errorDescription: String? {
        switch self {
        case .emptyKey: return "DeepL API 密钥为空，请到「设置 → DeepL API Key」填写密钥。"
        case .authFailed: return "DeepL 密钥错误或已失效（401/403），请检查密钥是否复制完整。"
        case .quotaExceeded: return "DeepL 免费配额已耗尽（456），本月额度用完或密钥错误，请登录 DeepL 官网查看用量。"
        case .rateLimited: return "DeepL 接口限流（429），请求过于频繁，请稍后重试。"
        case .timeout: return "网络请求超时，请检查网络连接后重试。"
        case .badResponse: return "DeepL 返回格式异常，可能是服务端临时故障，请重试。"
        case .network(let m): return "网络错误：\(m)。请检查网络或稍后重试。"
        case .appleUnavailable: return "苹果系统翻译需要 iOS 17.4 及以上版本，当前系统不支持。"
        case .appleOfflinePackMissing: return "苹果离线翻译包未下载：请到「设置 → 通用 → 翻译」下载对应语言离线包。"
        case .ocrFailed(let m): return "文字识别失败：\(m)。请尝试重新截图或更换识别语种。"
        case .captureFailed(let m): return "截图失败：\(m)。请确认已在「设置 → 控制中心」添加「屏幕录制」并授权。"
        }
    }
}
