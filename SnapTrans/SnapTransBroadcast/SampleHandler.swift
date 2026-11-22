import ReplayKit
import Vision
import CoreMedia
import UIKit

// MARK: - 录屏广播扩展（直播翻译核心）
// 这是 iOS 唯一允许一个 App 读取「其他 App 画面」的合法机制：
// 用户在系统弹窗选择「译拍通」并开始直播后，本扩展以后台进程持续接收屏幕帧。
// 处理策略（控制内存与耗电）：跳过开头过渡帧 → 每 2 秒取一帧 → 压缩保存 → OCR →
// 文本有变化才调 DeepL 翻译 → 结果写入 App Group 共享目录。
class SampleHandler: RPBroadcastSampleHandler {

    private var config: BroadcastShared.Config?
    private var lastPTS: Double = -999
    private var lastTextHash: Int = 0
    private var frameIndex = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        config = BroadcastShared.loadConfig()
    }

    override func broadcastFinished() {
        // 结束时不做清理：画面与结果留给主 App 消费
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }
        frameIndex += 1
        // 跳过开头几帧（开始直播瞬间的系统动画）
        guard frameIndex >= 5 else { return }
        // 节流：每 2 秒处理一帧
        let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        guard pts - lastPTS >= 2.0 else { return }
        lastPTS = pts

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            guard let image = Self.downscale(pixelBuffer, maxDimension: 1280) else { return }
            // 1. 保存最新画面（主 App 回到前台时自动处理展示）
            if let jpeg = image.jpegData(compressionQuality: 0.75) {
                BroadcastShared.saveFrame(jpeg)
            }
            // 2. OCR + 翻译
            self.ocrAndMaybeTranslate(image)
        }
    }

    // MARK: OCR（Vision，扩展进程内完成）
    private func ocrAndMaybeTranslate(_ image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        let request = VNRecognizeTextRequest { [weak self] req in
            let observations = req.results as? [VNRecognizedTextObservation] ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard let self, text.count >= 2 else { return }
            // 内容与上次相同则跳过翻译
            let hash = text.hashValue
            guard hash != self.lastTextHash else { return }
            self.lastTextHash = hash
            self.translateIfNeeded(text)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        var langs: [String] = []
        if let ocrLang = config?.ocrLanguage, ocrLang != "auto" {
            langs.append(ocrLang)
        }
        if !langs.contains("en-US") { langs.append("en-US") }
        if !langs.contains("zh-Hans") { langs.append("zh-Hans") }
        request.recognitionLanguages = langs
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
    }

    // MARK: DeepL 翻译（扩展进程内直连，无 Key 则只记录原文）
    private func translateIfNeeded(_ text: String) {
        guard let cfg = config, !cfg.deeplKey.isEmpty else {
            BroadcastShared.saveResult(BroadcastShared.Result(
                timestamp: Date().timeIntervalSince1970,
                originalText: text, translatedText: "", engine: "none"))
            return
        }
        let host = cfg.deeplKey.hasSuffix(":fx") ? "https://api-free.deepl.com" : "https://api.deepl.com"
        guard let url = URL(string: host + "/v2/translate") else { return }
        var body: [String: Any] = [
            "text": [text],
            "target_lang": LangDefsShared.deeplTarget(cfg.targetLang),
        ]
        if let src = LangDefsShared.deeplSource(cfg.sourceLang) {
            body["source_lang"] = src
        }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(cfg.deeplKey, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let payload = try? JSONSerialization.data(withJSONObject: body) {
            req.httpBody = payload
        }
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let translations = obj["translations"] as? [[String: Any]],
                  let translated = translations.first?["text"] as? String else {
                // 请求失败也保存原文，主 App 回来后可自行重试翻译
                BroadcastShared.saveResult(BroadcastShared.Result(
                    timestamp: Date().timeIntervalSince1970,
                    originalText: text, translatedText: "", engine: "none"))
                return
            }
            BroadcastShared.saveResult(BroadcastShared.Result(
                timestamp: Date().timeIntervalSince1970,
                originalText: text, translatedText: translated, engine: "deepl"))
        }.resume()
    }

    // MARK: 像素缓冲降采样（控制扩展内存占用）
    private static func downscale(_ pixelBuffer: CVPixelBuffer, maxDimension: CGFloat) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let w = ciImage.extent.width, h = ciImage.extent.height
        let scale = min(1, maxDimension / max(w, h))
        if scale < 1 {
            let filter = CIFilter(name: "CILanczosScaleTransform")!
            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(scale, forKey: kCIInputScaleKey)
            guard let out = filter.outputImage else { return nil }
            let context = CIContext()
            guard let cg = context.createCGImage(out, from: out.extent) else { return nil }
            return UIImage(cgImage: cg)
        }
        let context = CIContext()
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - 语言映射（扩展 target 内精简版，避免引入 UIKit 重依赖文件）
enum LangDefsShared {
    static func deeplTarget(_ code: String) -> String {
        switch code {
        case "zh-Hans", "zh-TW": return "ZH"
        default: return code.uppercased()
        }
    }
    static func deeplSource(_ code: String) -> String? {
        guard code != "auto" else { return nil }
        return code.uppercased().replacingOccurrences(of: "-HANS", with: "")
    }
}
