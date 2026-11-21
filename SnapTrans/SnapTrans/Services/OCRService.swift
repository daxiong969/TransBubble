import Foundation
import Vision
import UIKit

// MARK: - OCR 识别服务（Apple Vision，本地离线）
final class OCRService {
    /// 识别截图文字，返回每个文字块的内容/坐标/置信度
    /// - Parameters:
    ///   - image: 截图
    ///   - language: 识别语言（en-US / ja-JP / ko-KR / zh-Hans），Vision 会自动附加中文兜底
    func recognize(image: UIImage, language: String) async throws -> [TextBlock] {
        guard let cgImage = image.cgImage else {
            throw TranslateError.ocrFailed("图片数据无效")
        }
        return try await withCheckedThrowingContinuation { cont in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    cont.resume(throwing: TranslateError.ocrFailed(error.localizedDescription))
                    return
                }
                guard let observations = req.results as? [VNRecognizedTextObservation] else {
                    cont.resume(returning: [])
                    return
                }
                var blocks: [TextBlock] = []
                for ob in observations {
                    // 取置信度最高的候选文本
                    guard let top = ob.topCandidates(1).first else { continue }
                    let text = top.string
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                    // Vision 坐标系原点在左下角，转换为 iOS 视图坐标（左上原点）的归一化值
                    let b = ob.boundingBox
                    let rect = CGRect(x: b.minX,
                                      y: 1 - b.maxY,
                                      width: b.width,
                                      height: b.height)
                    blocks.append(TextBlock(original: text,
                                            bounding: rect,
                                            confidence: Double(top.confidence)))
                }
                // 按从上到下排序，便于阅读
                blocks.sort { $0.bounding.minY < $1.bounding.minY }
                cont.resume(returning: blocks)
            }
            // 识别语种设置：手动锁定 + 中文兜底
            var langs: [String] = [language]
            if language != "zh-Hans" { langs.append("zh-Hans") }
            request.recognitionLanguages = langs
            request.usesLanguageCorrection = true
            request.recognitionLevel = .accurate

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                cont.resume(throwing: TranslateError.ocrFailed(error.localizedDescription))
            }
        }
    }
}
